import AppKit
import Darwin

private let wattsonBundleIdentifier = "com.leoarrow.wattson"
private let wattsonExecutableRelativePath = "Contents/MacOS/Wattson"
private let helperLabel = "com.leoarrow.wattson.helper"
private let helperInstallPath = "/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper"
private let helperPlistInstallPath = "/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist"
private let helperSocketPath = "/var/run/wattson-helper.sock"
private let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
private let applicationReadinessStabilityInterval: TimeInterval = 2
private let expectedWattsonArchiveSHA256 = "__WATTSON_ARCHIVE_SHA256__"
private let expectedInstallHelperSHA256 = "__INSTALL_HELPER_SHA256__"
private let expectedHelperBinarySHA256 = "__HELPER_BINARY_SHA256__"
private let expectedHelperPlistSHA256 = "__HELPER_PLIST_SHA256__"

private enum InstallerError: LocalizedError {
    case message(String)
    case authorizationCancelled

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        case .authorizationCancelled:
            return "已取消管理员授权，Wattson 的辅助助手未安装。"
        }
    }
}

private enum Command {
    @discardableResult
    static func run(
        _ executablePath: String,
        _ arguments: [String],
        acceptedExitCodes: Set<Int32> = [0],
        timeout: TimeInterval = 30
    ) throws -> String {
        let fileManager = FileManager.default
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("WattsonInstallerCommand-\(UUID().uuidString).log")
        guard fileManager.createFile(
            atPath: outputURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw InstallerError.message("无法创建安装命令的临时日志。")
        }
        let outputHandle: FileHandle
        do {
            outputHandle = try FileHandle(forWritingTo: outputURL)
        } catch {
            try? fileManager.removeItem(at: outputURL)
            throw InstallerError.message("无法打开安装命令的临时日志。")
        }
        defer {
            try? outputHandle.close()
            try? fileManager.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let account = getpwuid(getuid())
        let userName = account?.pointee.pw_name.map { String(cString: $0) } ?? ""
        let homeDirectory = account?.pointee.pw_dir.map { String(cString: $0) } ?? "/var/empty"
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": homeDirectory,
            "USER": userName,
            "LOGNAME": userName,
            "LANG": "C",
            "LC_ALL": "C",
        ]
        process.standardOutput = outputHandle
        process.standardError = outputHandle

        do {
            try process.run()
        } catch {
            throw InstallerError.message("无法运行 \(executablePath)：\(error.localizedDescription)")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            throw InstallerError.message(
                "\(URL(fileURLWithPath: executablePath).lastPathComponent) 超过 \(Int(timeout)) 秒未完成，已终止。"
            )
        }
        process.waitUntilExit()
        try? outputHandle.synchronize()
        try? outputHandle.close()

        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard acceptedExitCodes.contains(process.terminationStatus) else {
            let detail = text.isEmpty ? "退出码 \(process.terminationStatus)" : text
            throw InstallerError.message("\(URL(fileURLWithPath: executablePath).lastPathComponent) 失败：\(detail)")
        }
        return text
    }
}

private enum InstallationDiagnostics {
    private struct Probe {
        let key: String
        let executablePath: String
        let arguments: [String]
        let acceptedExitCodes: Set<Int32>
        let timeout: TimeInterval
    }

    private final class ProbeResultStore {
        private let lock = NSLock()
        private var values: [String: String] = [:]

        func set(_ value: String, for key: String) {
            lock.lock()
            values[key] = value
            lock.unlock()
        }

        func value(for key: String) -> String {
            lock.lock()
            defer { lock.unlock() }
            return values[key] ?? "（诊断未完成）"
        }
    }

    private static let logPredicate =
        "(process == \"launchd\" OR process == \"backgroundtaskmanagementd\" OR process == \"syspolicyd\" OR process == \"amfid\") AND eventMessage CONTAINS[c] \"wattson\""

    // The collector rejects every command/argument pair that is not explicitly
    // listed here. This keeps future diagnostics read-only by construction.
    private static let readOnlyCommandArguments: [String: [[String]]] = [
        "/usr/bin/sw_vers": [[]],
        "/usr/bin/uname": [["-m"]],
        "/usr/sbin/spctl": [["--status"]],
        "/bin/launchctl": [
            ["print", "system/\(helperLabel)"],
            ["print-disabled", "system"],
        ],
        "/usr/bin/sfltool": [["dumpbtm"]],
        "/bin/ls": [["-leO@", helperInstallPath, helperPlistInstallPath]],
        "/usr/bin/codesign": [
            ["-dvv", helperInstallPath],
            ["--verify", "--strict", helperInstallPath],
        ],
        "/usr/bin/xattr": [
            [helperInstallPath],
            [helperPlistInstallPath],
        ],
        "/usr/bin/log": [[
            "show", "--last", "15m", "--style", "compact",
            "--predicate", logPredicate,
        ]],
    ]

    static func collect(failureDescription: String) -> String {
        let probes = [
            Probe(
                key: "system", executablePath: "/usr/bin/sw_vers",
                arguments: [], acceptedExitCodes: [0], timeout: 3
            ),
            Probe(
                key: "architecture", executablePath: "/usr/bin/uname",
                arguments: ["-m"], acceptedExitCodes: [0], timeout: 3
            ),
            Probe(
                key: "gatekeeper", executablePath: "/usr/sbin/spctl",
                arguments: ["--status"], acceptedExitCodes: [0, 1], timeout: 3
            ),
            Probe(
                key: "launchd", executablePath: "/bin/launchctl",
                arguments: ["print", "system/\(helperLabel)"],
                acceptedExitCodes: [0], timeout: 3
            ),
            Probe(
                key: "disabled", executablePath: "/bin/launchctl",
                arguments: ["print-disabled", "system"],
                acceptedExitCodes: [0], timeout: 3
            ),
            Probe(
                key: "btm", executablePath: "/usr/bin/sfltool",
                arguments: ["dumpbtm"], acceptedExitCodes: [0], timeout: 6
            ),
            Probe(
                key: "files", executablePath: "/bin/ls",
                arguments: ["-leO@", helperInstallPath, helperPlistInstallPath],
                acceptedExitCodes: [0], timeout: 3
            ),
            Probe(
                key: "signature", executablePath: "/usr/bin/codesign",
                arguments: ["-dvv", helperInstallPath],
                acceptedExitCodes: [0], timeout: 3
            ),
            Probe(
                key: "signatureVerification", executablePath: "/usr/bin/codesign",
                arguments: ["--verify", "--strict", helperInstallPath],
                acceptedExitCodes: [0], timeout: 3
            ),
            Probe(
                key: "helperAttributes", executablePath: "/usr/bin/xattr",
                arguments: [helperInstallPath],
                acceptedExitCodes: [0], timeout: 3
            ),
            Probe(
                key: "plistAttributes", executablePath: "/usr/bin/xattr",
                arguments: [helperPlistInstallPath],
                acceptedExitCodes: [0], timeout: 3
            ),
            Probe(
                key: "logs", executablePath: "/usr/bin/log",
                arguments: [
                    "show", "--last", "15m", "--style", "compact",
                    "--predicate", logPredicate,
                ],
                acceptedExitCodes: [0], timeout: 8
            ),
        ]

        let results = ProbeResultStore()
        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "com.leoarrow.wattson.installer-diagnostics",
            qos: .utility,
            attributes: .concurrent
        )
        for probe in probes {
            group.enter()
            queue.async {
                let output = command(
                    probe.executablePath,
                    probe.arguments,
                    acceptedExitCodes: probe.acceptedExitCodes,
                    timeout: probe.timeout
                )
                results.set(output, for: probe.key)
                group.leave()
            }
        }
        group.wait()

        let installerVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "未知"
        let disabledState = matchingWattsonLines(results.value(for: "disabled"))
        let backgroundTasks = matchingWattsonLines(results.value(for: "btm"))
        let recentLogs = bounded(
            results.value(for: "logs"),
            maximumCharacters: 50_000
        )

        return """
        Wattson 安装诊断
        生成时间：\(ISO8601DateFormatter().string(from: Date()))
        安装器版本：\(installerVersion)
        安装失败信息：\(failureDescription)
        说明：文件与服务状态是安装器完成自动回滚后的只读快照；原始错误与系统日志保留失败时信息。

        === 系统 ===
        \(results.value(for: "system"))
        芯片架构：\(results.value(for: "architecture"))
        Gatekeeper：\(results.value(for: "gatekeeper"))

        === launchd 服务（回滚后） ===
        \(results.value(for: "launchd"))

        === launchd 禁用状态（仅匹配 Wattson 的行） ===
        \(disabledState)

        === 后台项目（仅匹配 Wattson 的行） ===
        \(backgroundTasks)

        === 已安装文件（回滚后） ===
        \(results.value(for: "files"))

        === Helper 签名（回滚后） ===
        \(results.value(for: "signature"))
        验证结果：\(results.value(for: "signatureVerification"))

        === Helper 扩展属性名称（不复制属性值） ===
        \(results.value(for: "helperAttributes"))

        === Plist 扩展属性名称（不复制属性值） ===
        \(results.value(for: "plistAttributes"))

        === 最近 15 分钟相关系统日志 ===
        \(recentLogs)
        """
    }

    private static func command(
        _ executablePath: String,
        _ arguments: [String],
        acceptedExitCodes: Set<Int32>,
        timeout: TimeInterval
    ) -> String {
        guard readOnlyCommandArguments[executablePath]?.contains(arguments) == true else {
            return "（已拒绝未列入只读白名单的诊断命令）"
        }
        do {
            let output = try Command.run(
                executablePath,
                arguments,
                acceptedExitCodes: acceptedExitCodes,
                timeout: timeout
            )
            return output.isEmpty ? "（命令成功，无输出）" : output
        } catch {
            return "（读取失败：\(error.localizedDescription)）"
        }
    }

    private static func matchingWattsonLines(_ output: String) -> String {
        if output.hasPrefix("（读取失败：") {
            return output
        }
        var seen = Set<String>()
        let selected = output.components(separatedBy: .newlines).filter { line in
            let normalized = line.lowercased()
            let matches = normalized.contains("wattson")
            return matches && seen.insert(line).inserted
        }
        return selected.isEmpty
            ? "（未发现 Wattson 相关记录）"
            : selected.joined(separator: "\n")
    }

    private static func bounded(
        _ output: String,
        maximumCharacters: Int
    ) -> String {
        guard output.count > maximumCharacters else { return output }
        return String(output.prefix(maximumCharacters))
            + "\n（日志过长，后续内容已截断）"
    }
}

private struct PreparedPayload {
    let temporaryDirectory: URL
    let appURL: URL
    let installHelperScriptURL: URL
    let helperURL: URL
    let helperPlistURL: URL
}

private struct ApplicationInstallTransaction {
    let installedAppURL: URL
    let backupURL: URL?
    let previousApplicationWasRunning: Bool
}

private final class InstallerEngine {
    private let fileManager = FileManager.default

    func verifyOnly(progress: (String) -> Void) throws {
        let payload = try preparePayload(progress: progress)
        defer { try? fileManager.removeItem(at: payload.temporaryDirectory) }
        try Command.run("/bin/bash", ["-n", "-c", privilegedInstallScript(for: payload)])
        guard let script = NSAppleScript(source: authorizationAppleScriptSource(for: payload)) else {
            throw InstallerError.message("无法创建系统授权请求。")
        }
        var errorInfo: NSDictionary?
        guard script.compileAndReturnError(&errorInfo) else {
            let detail = errorInfo?["NSAppleScriptErrorMessage"] as? String ?? "未知错误"
            throw InstallerError.message("系统授权脚本无法编译：\(detail)")
        }
    }

    func install(progress: @escaping (String) -> Void) throws {
        try requireReadOnlySignedInstallationMedia()
        let payload = try preparePayload(progress: progress)
        defer { try? fileManager.removeItem(at: payload.temporaryDirectory) }

        progress("正在替换旧版 Wattson…")
        let transaction = try installApplication(from: payload.appURL)

        do {
            progress("正在启动 Wattson…")
            let readinessToken = UUID()
            let readinessURL = installerReadinessURL(for: readinessToken)
            try? fileManager.removeItem(at: readinessURL)
            defer { try? fileManager.removeItem(at: readinessURL) }
            try Command.run(
                "/usr/bin/open",
                [
                    "-n", transaction.installedAppURL.path,
                    "--args", "--installer-ready-token=\(readinessToken.uuidString)",
                ]
            )
            try waitForInstalledApplication(
                at: transaction.installedAppURL,
                readinessToken: readinessToken,
                readinessURL: readinessURL
            )

            progress("等待系统管理员授权…")
            try installPrivilegedHelper(using: payload)
            commitApplicationInstall(transaction)
        } catch {
            let installationError = error
            progress("安装未完成，正在恢复之前版本…")
            do {
                try rollbackApplicationInstall(transaction)
            } catch {
                throw InstallerError.message(
                    "\(installationError.localizedDescription) 恢复之前版本时又失败：\(error.localizedDescription)"
                )
            }
            throw installationError
        }
    }

    private func preparePayload(progress: (String) -> Void) throws -> PreparedPayload {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw InstallerError.message("安装器资源目录不存在。")
        }

        let payloadDirectory = resourceURL.appendingPathComponent("Payload", isDirectory: true)
        let archiveURL = payloadDirectory.appendingPathComponent("Wattson.zip")
        let helperURL = payloadDirectory.appendingPathComponent(helperLabel)
        let helperPlistURL = payloadDirectory.appendingPathComponent("\(helperLabel).plist")
        let installHelperScriptURL = resourceURL.appendingPathComponent("install-helper.sh")

        progress("正在验证安装资源…")
        try requireRegularFile(archiveURL, description: "Wattson.zip")
        try requireRegularFile(helperURL, description: "辅助助手")
        try requireRegularFile(helperPlistURL, description: "辅助助手 plist")
        try requireRegularFile(installHelperScriptURL, description: "install-helper.sh")
        try requireSHA256(
            expectedWattsonArchiveSHA256,
            for: archiveURL,
            description: "Wattson.zip"
        )
        try requireSHA256(
            expectedInstallHelperSHA256,
            for: installHelperScriptURL,
            description: "install-helper.sh"
        )
        try requireSHA256(
            expectedHelperBinarySHA256,
            for: helperURL,
            description: "辅助助手"
        )
        try requireSHA256(
            expectedHelperPlistSHA256,
            for: helperPlistURL,
            description: "辅助助手 plist"
        )
        try Command.run("/usr/bin/codesign", ["--verify", "--strict", helperURL.path])
        try validateHelperPlist(at: helperPlistURL)
        try Command.run("/bin/bash", ["-n", installHelperScriptURL.path])

        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("WattsonInstaller-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            progress("正在解压 Wattson…")
            try Command.run("/usr/bin/ditto", ["-x", "-k", archiveURL.path, temporaryDirectory.path])

            let appURL = temporaryDirectory.appendingPathComponent("Wattson.app", isDirectory: true)
            try validateApplication(at: appURL)
            return PreparedPayload(
                temporaryDirectory: temporaryDirectory,
                appURL: appURL,
                installHelperScriptURL: installHelperScriptURL,
                helperURL: helperURL,
                helperPlistURL: helperPlistURL
            )
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    private func requireReadOnlySignedInstallationMedia() throws {
        let installerURL = Bundle.main.bundleURL
        var fileSystem = statfs()
        guard statfs(installerURL.path, &fileSystem) == 0 else {
            throw InstallerError.message("无法检查安装器所在卷。")
        }
        guard (fileSystem.f_flags & UInt32(MNT_RDONLY)) != 0 else {
            throw InstallerError.message(
                "请直接从只读 DMG 中打开 Install Wattson.app，不要先把安装器拷贝到其他位置。"
            )
        }
        try Command.run(
            "/usr/bin/codesign", ["--verify", "--deep", "--strict", installerURL.path]
        )
    }

    private func requireSHA256(_ expected: String, for url: URL, description: String) throws {
        let normalizedExpected = expected.lowercased()
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard normalizedExpected.count == 64,
              normalizedExpected.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw InstallerError.message("安装器没有固化 \(description) 的完整性信息。")
        }
        let output = try Command.run("/usr/bin/shasum", ["-a", "256", url.path])
        let actual = output.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        guard actual.lowercased() == normalizedExpected else {
            throw InstallerError.message("\(description) 的 SHA-256 不匹配，安装已停止。")
        }
    }

    private func validateApplication(at appURL: URL) throws {
        let values = try appURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw InstallerError.message("Wattson.app 不是有效的应用包。")
        }

        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        let info = try propertyList(at: infoURL)
        guard info["CFBundleIdentifier"] as? String == wattsonBundleIdentifier else {
            throw InstallerError.message("Wattson.app 的 bundle identifier 不匹配。")
        }
        guard info["CFBundleExecutable"] as? String == "Wattson" else {
            throw InstallerError.message("Wattson.app 的可执行文件声明不匹配。")
        }
        try requireRegularFile(
            appURL.appendingPathComponent(wattsonExecutableRelativePath),
            description: "Wattson 可执行文件"
        )
        try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
    }

    private func validateHelperPlist(at plistURL: URL) throws {
        let plist = try propertyList(at: plistURL)
        guard plist["Label"] as? String == helperLabel else {
            throw InstallerError.message("辅助助手 plist 的 Label 不匹配。")
        }
        guard let arguments = plist["ProgramArguments"] as? [String],
              arguments == [helperInstallPath] else {
            throw InstallerError.message("辅助助手 plist 的程序路径不匹配。")
        }
        guard let sockets = plist["Sockets"] as? [String: Any],
              let listener = sockets["Listener"] as? [String: Any],
              listener["SockPathName"] as? String == helperSocketPath else {
            throw InstallerError.message("辅助助手 plist 的 socket 路径不匹配。")
        }
    }

    private func propertyList(at url: URL) throws -> [String: Any] {
        try requireRegularFile(url, description: url.lastPathComponent)
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dictionary = object as? [String: Any] else {
                throw InstallerError.message("\(url.lastPathComponent) 不是字典格式。")
            }
            return dictionary
        } catch let error as InstallerError {
            throw error
        } catch {
            throw InstallerError.message("无法读取 \(url.lastPathComponent)：\(error.localizedDescription)")
        }
    }

    private func requireRegularFile(_ url: URL, description: String) throws {
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw InstallerError.message("\(description) 缺失或不是普通文件。")
            }
        } catch let error as InstallerError {
            throw error
        } catch {
            throw InstallerError.message("无法读取 \(description)：\(error.localizedDescription)")
        }
    }

    private func installApplication(from sourceAppURL: URL) throws -> ApplicationInstallTransaction {
        let applicationsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        try fileManager.createDirectory(
            at: applicationsURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )

        let targetURL = applicationsURL.appendingPathComponent("Wattson.app", isDirectory: true)
        let candidateURL = applicationsURL
            .appendingPathComponent(".Wattson.installing-\(UUID().uuidString).app", isDirectory: true)
        let backupURL = applicationsURL
            .appendingPathComponent(".Wattson.previous-\(UUID().uuidString).app", isDirectory: true)
        defer {
            if fileManager.fileExists(atPath: candidateURL.path) {
                try? fileManager.removeItem(at: candidateURL)
            }
        }

        let targetExisted = fileManager.fileExists(atPath: targetURL.path)
        if targetExisted {
            let existingValues = try targetURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard existingValues.isDirectory == true, existingValues.isSymbolicLink != true else {
                throw InstallerError.message("同名目标不是可安全替换的应用包。")
            }
            let existingInfo = try propertyList(at: targetURL.appendingPathComponent("Contents/Info.plist"))
            guard existingInfo["CFBundleIdentifier"] as? String == wattsonBundleIdentifier else {
                throw InstallerError.message("已存在同名但不是 Wattson 的应用，为避免覆盖已停止安装。")
            }
        }

        try Command.run("/usr/bin/ditto", [sourceAppURL.path, candidateURL.path])
        try validateApplication(at: candidateURL)
        // xattr returns 1 when the attribute is absent; either outcome is safe.
        try Command.run(
            "/usr/bin/xattr",
            ["-d", "-r", "com.apple.quarantine", candidateURL.path],
            acceptedExitCodes: [0, 1]
        )
        let remainingAttributes = try Command.run("/usr/bin/xattr", ["-l", "-r", candidateURL.path])
        guard !remainingAttributes.contains("com.apple.quarantine") else {
            throw InstallerError.message("无法移除已验证 Wattson 副本的隔离属性。")
        }
        try validateApplication(at: candidateURL)

        let previousApplicationWasRunning = !applicationsRunning(at: targetURL).isEmpty
        try stopApplicationRunning(at: targetURL)
        try Command.run(lsregisterPath, ["-u", targetURL.path], acceptedExitCodes: [0, 1])
        if targetExisted {
            try fileManager.moveItem(at: targetURL, to: backupURL)
        }

        let transaction = ApplicationInstallTransaction(
            installedAppURL: targetURL,
            backupURL: targetExisted ? backupURL : nil,
            previousApplicationWasRunning: previousApplicationWasRunning
        )
        do {
            try fileManager.moveItem(at: candidateURL, to: targetURL)
            try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: targetURL.path)
            try Command.run(lsregisterPath, ["-f", targetURL.path])
        } catch {
            let replacementError = error
            do {
                try rollbackApplicationInstall(transaction)
            } catch {
                throw InstallerError.message(
                    "\(replacementError.localizedDescription) 恢复之前版本时又失败：\(error.localizedDescription)"
                )
            }
            throw replacementError
        }
        return transaction
    }

    private func commitApplicationInstall(_ transaction: ApplicationInstallTransaction) {
        guard let backupURL = transaction.backupURL,
              fileManager.fileExists(atPath: backupURL.path) else { return }
        try? fileManager.removeItem(at: backupURL)
    }

    private func rollbackApplicationInstall(_ transaction: ApplicationInstallTransaction) throws {
        try stopApplicationRunning(at: transaction.installedAppURL)
        try Command.run(
            lsregisterPath,
            ["-u", transaction.installedAppURL.path],
            acceptedExitCodes: [0, 1]
        )
        if fileManager.fileExists(atPath: transaction.installedAppURL.path) {
            try fileManager.removeItem(at: transaction.installedAppURL)
        }

        guard let backupURL = transaction.backupURL,
              fileManager.fileExists(atPath: backupURL.path) else { return }
        try fileManager.moveItem(at: backupURL, to: transaction.installedAppURL)
        try Command.run(lsregisterPath, ["-f", transaction.installedAppURL.path])
        if transaction.previousApplicationWasRunning {
            try Command.run("/usr/bin/open", ["-n", transaction.installedAppURL.path])
        }
    }

    private func applicationsRunning(at appURL: URL) -> [NSRunningApplication] {
        let expectedBundlePath = appURL.standardizedFileURL.path
        let expectedExecutablePath = appURL
            .appendingPathComponent(wattsonExecutableRelativePath)
            .standardizedFileURL.path
        return NSRunningApplication.runningApplications(withBundleIdentifier: wattsonBundleIdentifier)
            .filter { application in
                application.bundleURL?.standardizedFileURL.path == expectedBundlePath
                    || application.executableURL?.standardizedFileURL.path == expectedExecutablePath
            }
    }

    private func stopApplicationRunning(at appURL: URL) throws {
        let running = applicationsRunning(at: appURL)
        guard !running.isEmpty else { return }

        running.forEach { _ = $0.terminate() }
        if waitUntil(timeout: 3, condition: { self.applicationsRunning(at: appURL).isEmpty }) {
            return
        }

        applicationsRunning(at: appURL).forEach { _ = $0.forceTerminate() }
        guard waitUntil(timeout: 2, condition: { self.applicationsRunning(at: appURL).isEmpty }) else {
            throw InstallerError.message("无法关闭正在运行的旧版 Wattson。")
        }
    }

    private func installerReadinessURL(for token: UUID) -> URL {
        let homeURL: URL
        if let account = getpwuid(getuid()), let home = account.pointee.pw_dir {
            homeURL = URL(fileURLWithPath: String(cString: home), isDirectory: true)
        } else {
            homeURL = fileManager.homeDirectoryForCurrentUser
        }
        return homeURL
            .appendingPathComponent("Library/Application Support/Wattson", isDirectory: true)
            .appendingPathComponent("installer-ready-\(token.uuidString).txt")
    }

    private func waitForInstalledApplication(
        at appURL: URL,
        readinessToken: UUID,
        readinessURL: URL
    ) throws {
        let deadline = Date().addingTimeInterval(12)
        var appeared = false
        var readinessReceivedAt: Date?

        repeat {
            let running = !applicationsRunning(at: appURL).isEmpty
            if running { appeared = true }
            if appeared, !running {
                throw InstallerError.message("Wattson 启动后立即退出，请重新安装或查看系统日志。")
            }
            if running,
               let response = try? String(contentsOf: readinessURL, encoding: .utf8),
               response.trimmingCharacters(in: .whitespacesAndNewlines) == readinessToken.uuidString {
                if readinessReceivedAt == nil {
                    readinessReceivedAt = Date()
                }
            }
            if let readinessReceivedAt,
               Date().timeIntervalSince(readinessReceivedAt) >= applicationReadinessStabilityInterval {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline

        if !appeared {
            throw InstallerError.message("已安装 Wattson，但未检测到它从安装路径启动。")
        }
        throw InstallerError.message("Wattson 进程已启动，但菜单栏项未返回就绪回执。")
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return condition()
    }

    private func privilegedInstallScript(for payload: PreparedPayload) -> String {
        let privilegedCommands = [
            "set -e",
            "umask 077",
            "stage=$(/usr/bin/mktemp -d /private/tmp/com.leoarrow.wattson.install.XXXXXX)",
            "test -n \"$stage\"",
            "cleanup_stage() { status=$?; trap - EXIT HUP INT TERM; if [[ \"$status\" == \"0\" || ! -d \"$stage/Previous\" ]]; then /bin/rm -rf -- \"$stage\"; else /bin/echo \"Wattson rollback data preserved at $stage\" >&2; fi; exit \"$status\"; }",
            "trap cleanup_stage EXIT",
            "trap 'exit 130' HUP INT TERM",
            "/usr/bin/install -d -o root -g wheel -m 700 \"$stage/Payload\"",
            "/usr/bin/install -o root -g wheel -m 500 \(shellQuoted(payload.installHelperScriptURL.path)) \"$stage/install-helper.sh\"",
            "/usr/bin/install -o root -g wheel -m 500 \(shellQuoted(payload.helperURL.path)) \"$stage/Payload/\(helperLabel)\"",
            "/usr/bin/install -o root -g wheel -m 400 \(shellQuoted(payload.helperPlistURL.path)) \"$stage/Payload/\(helperLabel).plist\"",
            "test \"$(/usr/bin/shasum -a 256 \"$stage/install-helper.sh\" | /usr/bin/awk '{print $1}')\" = \(shellQuoted(expectedInstallHelperSHA256))",
            "test \"$(/usr/bin/shasum -a 256 \"$stage/Payload/\(helperLabel)\" | /usr/bin/awk '{print $1}')\" = \(shellQuoted(expectedHelperBinarySHA256))",
            "test \"$(/usr/bin/shasum -a 256 \"$stage/Payload/\(helperLabel).plist\" | /usr/bin/awk '{print $1}')\" = \(shellQuoted(expectedHelperPlistSHA256))",
            "/bin/bash -p \"$stage/install-helper.sh\"",
        ]
        return privilegedCommands.joined(separator: "; ")
    }

    private func authorizationAppleScriptSource(for payload: PreparedPayload) -> String {
        let shellCommand = [
            "/usr/bin/env -i",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME=/var/root",
            "USER=root",
            "LOGNAME=root",
            "/bin/bash -p -c \(shellQuoted(privilegedInstallScript(for: payload)))",
        ].joined(separator: " ")
        return "do shell script \(appleScriptQuoted(shellCommand)) with administrator privileges"
    }

    private func installPrivilegedHelper(using payload: PreparedPayload) throws {
        let source = authorizationAppleScriptSource(for: payload)

        var caughtError: Error?
        DispatchQueue.main.sync {
            guard let script = NSAppleScript(source: source) else {
                caughtError = InstallerError.message("无法创建系统授权请求。")
                return
            }
            var errorInfo: NSDictionary?
            _ = script.executeAndReturnError(&errorInfo)
            if let errorInfo = errorInfo {
                let number = errorInfo["NSAppleScriptErrorNumber"] as? Int
                if number == -128 {
                    caughtError = InstallerError.authorizationCancelled
                } else {
                    let detail = errorInfo["NSAppleScriptErrorMessage"] as? String
                        ?? "系统未返回详细信息。"
                    caughtError = InstallerError.message("安装辅助助手失败：\(detail)")
                }
            }
        }
        if let caughtError = caughtError {
            throw caughtError
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private final class InstallerWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let statusLabel = NSTextField(labelWithString: "准备安装")
    private let progressIndicator = NSProgressIndicator()
    private let installButton = NSButton(title: "安装", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let workerQueue = DispatchQueue(label: "com.leoarrow.wattson.installer", qos: .userInitiated)
    private var isInstalling = false
    private var isCollectingDiagnostics = false

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 290),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        configureWindow()
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureWindow() {
        window.title = "安装 Wattson"
        window.isReleasedWhenClosed = false
        window.delegate = self

        guard let contentView = window.contentView else { return }

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let titleLabel = NSTextField(labelWithString: "安装 Wattson")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        let detailLabel = NSTextField(wrappingLabelWithString:
            "Wattson 将安装到 ~/Applications，并安装用于省电模式、系统电池图标和开机启动的辅助助手。系统会请求一次管理员密码。")
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 3

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle

        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = true
        progressIndicator.isDisplayedWhenStopped = false

        installButton.translatesAutoresizingMaskIntoConstraints = false
        installButton.target = self
        installButton.action = #selector(startInstallation)
        installButton.keyEquivalent = "\r"
        installButton.bezelStyle = .rounded

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded

        [iconView, titleLabel, detailLabel, statusLabel, progressIndicator, installButton, cancelButton]
            .forEach(contentView.addSubview)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 26),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -26),
            titleLabel.topAnchor.constraint(equalTo: iconView.topAnchor, constant: 2),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            progressIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 26),
            progressIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -26),
            progressIndicator.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 30),

            statusLabel.leadingAnchor.constraint(equalTo: progressIndicator.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: progressIndicator.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 10),

            cancelButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -26),
            cancelButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),

            installButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -10),
            installButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            installButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88)
        ])
    }

    @objc private func startInstallation() {
        guard !isInstalling else { return }
        isInstalling = true
        installButton.isEnabled = false
        cancelButton.isEnabled = false
        statusLabel.stringValue = "正在开始…"
        progressIndicator.startAnimation(nil)

        workerQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try InstallerEngine().install { message in
                    DispatchQueue.main.async { [weak self] in
                        self?.statusLabel.stringValue = message
                    }
                }
                DispatchQueue.main.async { [weak self] in self?.showSuccess() }
            } catch {
                DispatchQueue.main.async { [weak self] in self?.showFailure(error) }
            }
        }
    }

    @objc private func cancel() {
        NSApp.terminate(nil)
    }

    private func showSuccess() {
        progressIndicator.stopAnimation(nil)
        statusLabel.stringValue = "安装完成，Wattson 正在菜单栏运行。"

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Wattson 已安装"
        alert.informativeText = "Wattson 已从 ~/Applications/Wattson.app 启动。安装器已确认菜单栏项完成初始化，且辅助助手能够正常响应。若菜单栏空间不足或使用刘海机型，macOS 仍可能隐藏图标。"
        alert.addButton(withTitle: "完成")
        alert.beginSheetModal(for: window) { _ in NSApp.terminate(nil) }
    }

    private func showFailure(_ error: Error) {
        isInstalling = false
        progressIndicator.stopAnimation(nil)
        installButton.isEnabled = true
        cancelButton.isEnabled = true
        statusLabel.stringValue = "安装未完成。可以重试或退出。"

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "安装失败"
        alert.informativeText = error.localizedDescription
            + "\n\n点击“复制诊断信息”即可一键收集只读系统信息，然后直接粘贴回复邮件。"
        alert.addButton(withTitle: "复制诊断信息")
        alert.addButton(withTitle: "关闭")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.copyInstallationDiagnostics(failureDescription: error.localizedDescription)
        }
    }

    private func copyInstallationDiagnostics(failureDescription: String) {
        guard !isCollectingDiagnostics else { return }
        isCollectingDiagnostics = true
        installButton.isEnabled = false
        cancelButton.isEnabled = false
        statusLabel.stringValue = "正在收集只读诊断信息…"

        workerQueue.async { [weak self] in
            let report = InstallationDiagnostics.collect(
                failureDescription: failureDescription
            )
            DispatchQueue.main.async {
                guard let self = self else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                let copied = pasteboard.setString(report, forType: .string)
                self.isCollectingDiagnostics = false
                self.installButton.isEnabled = true
                self.cancelButton.isEnabled = true
                self.statusLabel.stringValue = copied
                    ? "诊断信息已复制；请直接粘贴回复邮件。"
                    : "无法复制诊断信息，请重试。"

                let confirmation = NSAlert()
                confirmation.alertStyle = copied ? .informational : .warning
                confirmation.messageText = copied ? "诊断信息已复制" : "复制失败"
                confirmation.informativeText = copied
                    ? "请回复邮件，在正文中粘贴刚刚复制的全部内容。"
                    : "请重新点击安装，在失败后再次选择“复制诊断信息”。"
                confirmation.addButton(withTitle: "好")
                confirmation.beginSheetModal(for: self.window)
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !isInstalling && !isCollectingDiagnostics
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var installerWindowController: InstallerWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = InstallerWindowController()
        installerWindowController = controller
        controller.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

if CommandLine.arguments.dropFirst().contains("--verify") {
    do {
        try InstallerEngine().verifyOnly { print("  \($0)") }
        print("Wattson installer payload verified.")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("Wattson installer verification failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

private let application = NSApplication.shared
private let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
