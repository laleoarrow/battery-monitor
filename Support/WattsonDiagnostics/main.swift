import AppKit
import Darwin
import IOKit

private let diagnosticsVersion = "1.1.0"
private let wattsonAppPath = "/Applications/Wattson.app"
private let helperLabel = "com.leoarrow.wattson.helper"
private let helperInstallPath = "/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper"
private let helperPlistInstallPath = "/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist"

private enum DiagnosticError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

private enum Command {
    private static let maximumCapturedBytes = 100_000

    private final class CaptureStore {
        private let lock = NSLock()
        private var data = Data()
        private var truncated = false

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }
            let remaining = max(0, maximumCapturedBytes - data.count)
            if remaining > 0 {
                data.append(chunk.prefix(remaining))
            }
            if chunk.count > remaining {
                truncated = true
            }
        }

        func snapshot() -> (Data, Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (data, truncated)
        }
    }

    @discardableResult
    static func run(
        _ executablePath: String,
        _ arguments: [String],
        acceptedExitCodes: Set<Int32> = [0],
        timeout: TimeInterval = 10
    ) throws -> String {
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
        let outputPipe = Pipe()
        process.standardOutput = outputPipe.fileHandleForWriting
        process.standardError = outputPipe.fileHandleForWriting

        do {
            try process.run()
        } catch {
            throw DiagnosticError.message(
                "Could not run \(URL(fileURLWithPath: executablePath).lastPathComponent): "
                    + error.localizedDescription
            )
        }

        let capture = CaptureStore()
        let readerGroup = DispatchGroup()
        readerGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = outputPipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                capture.append(chunk)
            }
            readerGroup.leave()
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
        }
        process.waitUntilExit()
        try? outputPipe.fileHandleForWriting.close()
        readerGroup.wait()

        let (data, wasTruncated) = capture.snapshot()
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard acceptedExitCodes.contains(process.terminationStatus) else {
            let detail = text.isEmpty ? "exit status \(process.terminationStatus)" : text
            throw DiagnosticError.message(detail)
        }
        return wasTruncated
            ? text + "\n(output truncated by Wattson Diagnostics)"
            : text
    }
}

private enum InstallationDiagnostics {
    private static let v3BundleIdentifier = "com.leoarrow.wattson"
    private static let legacyBundleIdentifier = "com.leoarrow.battery-monitor"

    static func report() -> String {
        let home = NSHomeDirectory()
        let paths = [
            wattsonAppPath,
            home + "/Applications/Wattson.app",
            home + "/Applications/电池功率.app",
            home + "/Library/LaunchAgents/com.leoarrow.wattson.login.plist",
            home + "/Library/LaunchAgents/com.leoarrow.battery-monitor.agent.plist",
            home + "/Library/LaunchAgents/com.leoarrow.battery-monitor.plist",
        ]

        var lines = paths.map(pathInventoryLine)
        lines.append("")
        lines.append(contentsOf: runningApplicationLines(
            label: "Wattson v3",
            bundleIdentifier: v3BundleIdentifier
        ))
        lines.append(contentsOf: runningApplicationLines(
            label: "legacy Battery Power",
            bundleIdentifier: legacyBundleIdentifier
        ))
        return lines.joined(separator: "\n")
    }

    private static func pathInventoryLine(_ path: String) -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return "\(path): missing"
        }

        guard path.hasSuffix(".app") else {
            return "\(path): present"
        }
        let info = Bundle(path: path)?.infoDictionary
        let bundleIdentifier = info?["CFBundleIdentifier"] as? String ?? "unavailable"
        let version = info?["CFBundleShortVersionString"] as? String ?? "unavailable"
        let build = info?["CFBundleVersion"] as? String ?? "unavailable"
        return "\(path): present, bundle_id=\(bundleIdentifier), version=\(version), build=\(build)"
    }

    private static func runningApplicationLines(
        label: String,
        bundleIdentifier: String
    ) -> [String] {
        let applications = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .sorted { $0.processIdentifier < $1.processIdentifier }
        guard !applications.isEmpty else {
            return ["\(label) (\(bundleIdentifier)): no running instances"]
        }

        var lines = ["\(label) (\(bundleIdentifier)): \(applications.count) running instance(s)"]
        for application in applications {
            let bundlePath = application.bundleURL?.path ?? "unavailable"
            let executablePath = application.executableURL?.path ?? "unavailable"
            lines.append(
                "pid=\(application.processIdentifier), bundle=\(bundlePath), executable=\(executablePath)"
            )
        }
        return lines
    }
}

private enum BatteryDiagnostics {
    private static let propertyKeys = [
        "CurrentCapacity",
        "ExternalConnected",
        "IsCharging",
        "FullyCharged",
        "CycleCount",
        "Temperature",
        "VirtualTemperature",
        "Voltage",
        "Amperage",
        "InstantAmperage",
        "PowerTelemetryData",
    ]

    private static let telemetryKeys = [
        "SystemPowerIn",
        "SystemLoad",
        "BatteryPower",
        "SystemPowerInAccumulatorCount",
        "SystemLoadAccumulatorCount",
        "BatteryPowerAccumulatorCount",
    ]

    static func report() -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else {
            return "AppleSmartBattery: unavailable (no matching battery service)"
        }
        defer { IOObjectRelease(service) }

        var properties: [String: Any] = [:]
        for key in propertyKeys {
            if let value = IORegistryEntryCreateCFProperty(
                service,
                key as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() {
                properties[key] = value
            }
        }

        var lines = ["AppleSmartBattery: available"]
        for key in propertyKeys where key != "PowerTelemetryData"
            && key != "Temperature" && key != "VirtualTemperature"
            && key != "Amperage" && key != "InstantAmperage" {
            lines.append("\(key)=\(rawDescription(properties[key]))")
        }

        for key in ["Amperage", "InstantAmperage"] {
            lines.append(
                "\(key) raw=\(rawDescription(properties[key])) "
                    + "signed_int32=\(signedInt32Description(properties[key]))"
            )
        }

        let temperatureRaw = integerValue(properties["Temperature"])
        let virtualTemperatureRaw = integerValue(properties["VirtualTemperature"])
        lines.append(
            "Temperature raw=\(rawDescription(properties["Temperature"])) "
                + "decoded_deci_kelvin_c=\(decodedTemperature(temperatureRaw, scale: .deciKelvin))"
        )
        lines.append(
            "VirtualTemperature raw=\(rawDescription(properties["VirtualTemperature"])) "
                + "decoded_centi_celsius=\(decodedTemperature(virtualTemperatureRaw, scale: .centiCelsius))"
        )

        lines.append("PowerTelemetryData (selected power and accumulator fields only):")
        guard let telemetry = properties["PowerTelemetryData"] as? [String: Any] else {
            lines.append("PowerTelemetryData=unavailable")
            return lines.joined(separator: "\n")
        }
        for key in telemetryKeys {
            let isAccumulator = key.contains("Accumulated") || key.contains("Accumulator")
            lines.append("\(key)=\(rawDescription(telemetry[key], unsigned: isAccumulator))")
        }
        return lines.joined(separator: "\n")
    }

    private enum TemperatureScale {
        case deciKelvin
        case centiCelsius
    }

    private static func decodedTemperature(_ raw: Int64?, scale: TemperatureScale) -> String {
        guard let raw else { return "unavailable" }
        let celsius: Double
        switch scale {
        case .deciKelvin:
            guard raw != 0, raw != -1 else { return "unavailable (firmware sentinel)" }
            celsius = Double(raw) / 10.0 - 273.15
        case .centiCelsius:
            guard raw != -1 else { return "unavailable (firmware sentinel)" }
            celsius = Double(raw) / 100.0
        }
        guard (-100.0 ... 150.0).contains(celsius) else {
            return "unavailable (decoded value out of range)"
        }
        return String(format: "%.2f", celsius)
    }

    private static func integerValue(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    private static func signedInt32Description(_ value: Any?) -> String {
        guard let number = value as? NSNumber else { return "unavailable" }
        let signed = Int32(bitPattern: UInt32(truncatingIfNeeded: number.uint64Value))
        return String(signed)
    }

    private static func rawDescription(_ value: Any?, unsigned: Bool = false) -> String {
        guard let value else { return "unavailable" }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return unsigned ? String(number.uint64Value) : number.stringValue
        }
        return "unavailable (unexpected value type)"
    }
}

private enum HelperPowerDiagnostics {
    private static let sampleCount = 5
    private static let sampleInterval: TimeInterval = 1.0

    static func report() -> String {
        var lines = [
            "Probe transport: fixed read-only helper socket \(HelperClient.socketPath)",
            "Probe operations: health and getPower (v3.0.4+); the Wattson app was not launched",
        ]

        let healthStart = DispatchTime.now().uptimeNanoseconds
        let healthy = HelperClient.isHealthy()
        let healthElapsed = elapsedMilliseconds(since: healthStart)
        lines.append(
            "health=\(healthy ? "available" : "unavailable") elapsed_ms=\(format(healthElapsed))"
        )
        guard healthy else {
            lines.append("getPower=unavailable (helper missing, unreachable, or health unsupported)")
            lines.append("available_samples=0/\(sampleCount)")
            lines.append("unique_power_samples=0")
            return lines.joined(separator: "\n")
        }

        var availableCount = 0
        var uniqueSamples = Set<String>()
        for index in 1 ... sampleCount {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let start = DispatchTime.now().uptimeNanoseconds
            let power = HelperClient.livePower()
            let elapsed = elapsedMilliseconds(since: start)
            if let power {
                availableCount += 1
                let adapter = watts(power.adapterW)
                let system = watts(power.systemW)
                uniqueSamples.insert("adapter=\(adapter),system=\(system)")
                lines.append(
                    "sample[\(index)] time=\(timestamp) elapsed_ms=\(format(elapsed)) "
                        + "adapterW=\(adapter) systemW=\(system)"
                )
            } else {
                lines.append(
                    "sample[\(index)] time=\(timestamp) elapsed_ms=\(format(elapsed)) "
                        + "unavailable (getPower requires a v3.0.4+ helper)"
                )
            }
            if index < sampleCount {
                Thread.sleep(forTimeInterval: sampleInterval)
            }
        }
        lines.append("available_samples=\(availableCount)/\(sampleCount)")
        lines.append("unique_power_samples=\(uniqueSamples.count)")
        if availableCount == 0 {
            lines.append("getPower=unavailable (installed helper predates v3.0.4 or rejected the fixed request)")
        }
        return lines.joined(separator: "\n")
    }

    private static func elapsedMilliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func watts(_ value: Double?) -> String {
        value.map { String(format: "%.3f", $0) } ?? "unavailable"
    }
}

private enum HostRedaction {
    static func redactedHostVariants(for hostName: String) -> [String] {
        let original = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return [] }

        let localSuffix = ".local"
        let shortName = original.lowercased().hasSuffix(localSuffix)
            ? String(original.dropLast(localSuffix.count))
            : original
        let candidates = [shortName, shortName + localSuffix, original]
        var seen = Set<String>()
        return candidates
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
    }

    static func redactHost(in output: String, hostName: String) -> String {
        // A private-use marker prevents a short hostname such as "host" from
        // matching inside the final "<redacted-host>" replacement text.
        let marker = "\u{F8FF}WATTSON_PRIVATE_MACHINE\u{F8FF}"
        var redacted = output
        for variant in redactedHostVariants(for: hostName) {
            redacted = redacted.replacingOccurrences(
                of: variant,
                with: marker,
                options: .caseInsensitive
            )
        }
        return redacted.replacingOccurrences(of: marker, with: "<redacted-host>")
    }

    static func selfTestPassed() -> Bool {
        let fullFromShort = redactHost(
            in: "installer host=CODY-MAC.LOCAL",
            hostName: "cody-mac"
        )
        let shortFromFull = redactHost(
            in: "installer host=CoDy-MaC",
            hostName: "cody-mac.local"
        )
        return fullFromShort == "installer host=<redacted-host>"
            && shortFromFull == "installer host=<redacted-host>"
            && redactedHostVariants(for: "cody-mac") == ["cody-mac.local", "cody-mac"]
            && redactedHostVariants(for: "cody-mac.local") == ["cody-mac.local", "cody-mac"]
    }
}

private enum Diagnostics {
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
            return values[key] ?? "(diagnostics incomplete)"
        }
    }

    private static let logPredicate =
        "subsystem == \"com.leoarrow.wattson\" OR subsystem == \"com.leoarrow.wattson.helper\""

    // Every executable and exact argument list is allowlisted. The tool has no
    // elevation path, write command, repair action, network client, or upload step.
    private static let readOnlyCommandArguments: [String: [[String]]] = [
        "/usr/bin/sw_vers": [[]],
        "/usr/bin/uname": [["-m"]],
        "/usr/sbin/sysctl": [["-n", "hw.model"]],
        "/usr/sbin/spctl": [["--status"]],
        "/usr/sbin/pkgutil": [["--pkg-info", "com.leoarrow.wattson.pkg"]],
        "/bin/launchctl": [
            ["print", "system/\(helperLabel)"],
            ["print-disabled", "system"],
        ],
        "/usr/bin/sfltool": [["dumpbtm"]],
        "/bin/ls": [["-dlnO@", wattsonAppPath, helperInstallPath, helperPlistInstallPath]],
        "/usr/bin/codesign": [
            ["-dvv", wattsonAppPath],
            ["-dvv", helperInstallPath],
            ["--verify", "--deep", "--strict", wattsonAppPath],
            ["--verify", "--strict", helperInstallPath],
        ],
        "/usr/bin/xattr": [
            [wattsonAppPath],
            [helperInstallPath],
            [helperPlistInstallPath],
        ],
        "/usr/bin/tail": [["-n", "600", "/var/log/install.log"]],
        "/usr/bin/log": [[
            "show", "--last", "15m", "--style", "compact",
            "--predicate", logPredicate,
        ]],
    ]

    static func collect() -> String {
        let probes = [
            Probe(key: "system", executablePath: "/usr/bin/sw_vers", arguments: [], acceptedExitCodes: [0], timeout: 3),
            Probe(key: "architecture", executablePath: "/usr/bin/uname", arguments: ["-m"], acceptedExitCodes: [0], timeout: 3),
            Probe(key: "model", executablePath: "/usr/sbin/sysctl", arguments: ["-n", "hw.model"], acceptedExitCodes: [0], timeout: 3),
            Probe(key: "gatekeeper", executablePath: "/usr/sbin/spctl", arguments: ["--status"], acceptedExitCodes: [0, 1], timeout: 3),
            Probe(key: "receipt", executablePath: "/usr/sbin/pkgutil", arguments: ["--pkg-info", "com.leoarrow.wattson.pkg"], acceptedExitCodes: [0, 1], timeout: 3),
            Probe(key: "launchd", executablePath: "/bin/launchctl", arguments: ["print", "system/\(helperLabel)"], acceptedExitCodes: [0, 1], timeout: 3),
            Probe(key: "disabled", executablePath: "/bin/launchctl", arguments: ["print-disabled", "system"], acceptedExitCodes: [0], timeout: 3),
            Probe(key: "btm", executablePath: "/usr/bin/sfltool", arguments: ["dumpbtm"], acceptedExitCodes: [0, 1], timeout: 8),
            Probe(key: "files", executablePath: "/bin/ls", arguments: ["-dlnO@", wattsonAppPath, helperInstallPath, helperPlistInstallPath], acceptedExitCodes: [0, 1], timeout: 3),
            Probe(key: "appSignature", executablePath: "/usr/bin/codesign", arguments: ["-dvv", wattsonAppPath], acceptedExitCodes: [0, 1], timeout: 3),
            Probe(key: "helperSignature", executablePath: "/usr/bin/codesign", arguments: ["-dvv", helperInstallPath], acceptedExitCodes: [0, 1], timeout: 3),
            Probe(key: "appVerification", executablePath: "/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", wattsonAppPath], acceptedExitCodes: [0, 1], timeout: 3),
            Probe(key: "helperVerification", executablePath: "/usr/bin/codesign", arguments: ["--verify", "--strict", helperInstallPath], acceptedExitCodes: [0, 1], timeout: 3),
            Probe(key: "appAttributes", executablePath: "/usr/bin/xattr", arguments: [wattsonAppPath], acceptedExitCodes: [0, 1], timeout: 3),
            Probe(key: "helperAttributes", executablePath: "/usr/bin/xattr", arguments: [helperInstallPath], acceptedExitCodes: [0, 1], timeout: 3),
            Probe(key: "plistAttributes", executablePath: "/usr/bin/xattr", arguments: [helperPlistInstallPath], acceptedExitCodes: [0, 1], timeout: 3),
            Probe(key: "installLog", executablePath: "/usr/bin/tail", arguments: ["-n", "600", "/var/log/install.log"], acceptedExitCodes: [0, 1], timeout: 5),
            Probe(key: "unifiedLog", executablePath: "/usr/bin/log", arguments: ["show", "--last", "15m", "--style", "compact", "--predicate", logPredicate], acceptedExitCodes: [0, 1], timeout: 10),
        ]

        let results = ProbeResultStore()
        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "com.leoarrow.wattson.diagnostics.probes",
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
        group.enter()
        queue.async {
            results.set(HelperPowerDiagnostics.report(), for: "helperPower")
            group.leave()
        }
        group.wait()

        let disabledState = matchingWattsonLines(results.value(for: "disabled"))
        let backgroundTasks = matchingWattsonLines(results.value(for: "btm"))
        let installLog = matchingWattsonLines(results.value(for: "installLog"))
        let unifiedLog = bounded(results.value(for: "unifiedLog"), maximumCharacters: 50_000)

        let report = redactPrivateMachineDetails("""
        Wattson Diagnostics
        Generated: \(ISO8601DateFormatter().string(from: Date()))
        Diagnostics version: \(diagnosticsVersion)
        Privacy: Read-only snapshot. No password was requested, no setting was changed, and nothing was uploaded. Review this text before sending it.

        === System ===
        \(results.value(for: "system"))
        Architecture: \(results.value(for: "architecture"))
        Hardware model: \(results.value(for: "model"))
        Gatekeeper: \(results.value(for: "gatekeeper"))

        === Wattson Installation and Exact Running Bundles ===
        \(InstallationDiagnostics.report())

        === AppleSmartBattery Selected Fields ===
        \(BatteryDiagnostics.report())

        === Privileged Helper Live Power (Five 1-Second Samples) ===
        \(results.value(for: "helperPower"))

        === Wattson Package Receipt ===
        \(results.value(for: "receipt"))

        === launchd Service ===
        \(results.value(for: "launchd"))

        === launchd Disabled State (Wattson Lines Only) ===
        \(disabledState)

        === Background Items (Wattson Lines Only) ===
        \(backgroundTasks)

        === Installed Files ===
        \(results.value(for: "files"))

        === App Signature ===
        \(results.value(for: "appSignature"))
        Verification: \(results.value(for: "appVerification"))

        === Helper Signature ===
        \(results.value(for: "helperSignature"))
        Verification: \(results.value(for: "helperVerification"))

        === Extended Attribute Names (Values Not Copied) ===
        App: \(results.value(for: "appAttributes"))
        Helper: \(results.value(for: "helperAttributes"))
        Plist: \(results.value(for: "plistAttributes"))

        === Wattson Lines from the Installer Log ===
        \(installLog)

        === Wattson Unified Logs from the Last 15 Minutes ===
        \(unifiedLog)
        """)
        return bounded(report, maximumCharacters: 100_000)
    }

    private static func command(
        _ executablePath: String,
        _ arguments: [String],
        acceptedExitCodes: Set<Int32>,
        timeout: TimeInterval
    ) -> String {
        guard readOnlyCommandArguments[executablePath]?.contains(arguments) == true else {
            return "(rejected: command is not on the read-only allowlist)"
        }
        do {
            let output = try Command.run(
                executablePath,
                arguments,
                acceptedExitCodes: acceptedExitCodes,
                timeout: timeout
            )
            return output.isEmpty ? "(command succeeded with no output)" : output
        } catch {
            return "(read failed: \(error.localizedDescription))"
        }
    }

    private static func matchingWattsonLines(_ output: String) -> String {
        if output.hasPrefix("(read failed:") {
            return output
        }
        var seen = Set<String>()
        let selected = output.components(separatedBy: .newlines).filter { line in
            let normalized = line.lowercased()
            return normalized.contains("wattson") && seen.insert(line).inserted
        }
        return selected.isEmpty
            ? "(no Wattson-related records found)"
            : bounded(selected.joined(separator: "\n"), maximumCharacters: 50_000)
    }

    private static func bounded(_ output: String, maximumCharacters: Int) -> String {
        guard output.count > maximumCharacters else { return output }
        return String(output.prefix(maximumCharacters))
            + "\n(output truncated by Wattson Diagnostics)"
    }

    private static func redactPrivateMachineDetails(_ output: String) -> String {
        let home = NSHomeDirectory()
        var redacted = output
        if home != "/", !home.isEmpty {
            redacted = redacted.replacingOccurrences(of: home, with: "~")
        }

        return HostRedaction.redactHost(
            in: redacted,
            hostName: ProcessInfo.processInfo.hostName
        )
    }
}

private final class DiagnosticsWindowController: NSWindowController, NSWindowDelegate {
    private let collectButton = NSButton(title: "Collect & Copy Diagnostics", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private var isCollecting = false

    var canTerminate: Bool {
        !isCollecting
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 310),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Wattson Diagnostics"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        configureContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "Wattson Diagnostics")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.alignment = .center

        let detailLabel = NSTextField(wrappingLabelWithString: "This tool collects a read-only snapshot of Wattson, its helper, package receipt, and related installation logs. It never asks for a password, changes settings, or uploads data.")
        detailLabel.font = .systemFont(ofSize: 14)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 4

        let instructionLabel = NSTextField(wrappingLabelWithString: "Click once, then reply to the Wattson email and paste the copied text.")
        instructionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        instructionLabel.alignment = .center

        collectButton.target = self
        collectButton.action = #selector(collectAndCopy)
        collectButton.bezelStyle = .rounded
        collectButton.keyEquivalent = "\r"

        quitButton.target = self
        quitButton.action = #selector(quit)
        quitButton.bezelStyle = .rounded

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center

        let buttonRow = NSStackView(views: [quitButton, collectButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 12

        let statusRow = NSStackView(views: [progressIndicator, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8

        let stack = NSStackView(views: [
            titleLabel,
            detailLabel,
            instructionLabel,
            statusRow,
            buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -36),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            detailLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            instructionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            collectButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 210),
        ])
    }

    func show() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func collectAndCopy() {
        guard !isCollecting else { return }
        isCollecting = true
        collectButton.isEnabled = false
        quitButton.isEnabled = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "Collecting read-only diagnostics…"

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let report = Diagnostics.collect()
            DispatchQueue.main.async {
                guard let self else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                let copied = pasteboard.setString(report, forType: .string)
                self.progressIndicator.stopAnimation(nil)
                self.isCollecting = false
                self.collectButton.isEnabled = true
                self.quitButton.isEnabled = true
                self.statusLabel.stringValue = copied ? "Copied to Clipboard" : "Copy Failed"

                let alert = NSAlert()
                alert.alertStyle = copied ? .informational : .warning
                alert.messageText = copied ? "Diagnostics Copied" : "Could Not Copy Diagnostics"
                alert.informativeText = copied
                    ? "Reply to the Wattson email and paste the copied text into the message body. Review it before sending."
                    : "Please click Collect & Copy Diagnostics again."
                alert.addButton(withTitle: "OK")
                if let window = self.window {
                    alert.beginSheetModal(for: window)
                }
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !isCollecting
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: DiagnosticsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = DiagnosticsWindowController()
        windowController = controller
        controller.show()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        windowController?.canTerminate == false ? .terminateCancel : .terminateNow
    }
}

if CommandLine.arguments.contains("--host-redaction-self-test") {
    exit(HostRedaction.selfTestPassed() ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments.contains("--print-diagnostics") {
    print(Diagnostics.collect())
    exit(EXIT_SUCCESS)
}

private let application = NSApplication.shared
private let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
