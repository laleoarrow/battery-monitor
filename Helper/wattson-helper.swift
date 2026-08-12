import Darwin
import Foundation
import IOKit
import os

private let log = OSLog(subsystem: "com.leoarrow.wattson.helper", category: "ipc")
private let idleTimeout: TimeInterval = 5
private let childTimeout: TimeInterval = 1.5
private let controlCenterDomain = "com.apple.controlcenter" as CFString
private let controlCenterBatteryKey = "Battery" as CFString
private let loginAgentLabel = "com.leoarrow.wattson.login"
private let wattsonBundleIdentifier = "com.leoarrow.wattson"
private let helperSocketPath = "/var/run/wattson-helper.sock"
private let helperExecutablePath = "/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper"

// AppleSMC's read-only user-client protocol uses this frozen 80-byte structure.
// Wattson deliberately exposes only the two fixed whole-machine power keys below;
// no socket input can select an SMC key or reach an SMC write command.
private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

private struct FixedSMCPower {
    let adapterW: Double?
    let systemW: Double?
}

private enum FixedSMCPowerReader {
    // These constants are the entire SMC capability granted to the app:
    // PDTR = adapter/DC-in power, PSTR = total system power.
    private static let adapterKey: UInt32 = 0x5044_5452
    private static let systemKey: UInt32 = 0x5053_5452
    private static let floatType: UInt32 = 0x666c_7420 // "flt "
    private static let sp78Type: UInt32 = 0x7370_3738 // "sp78"
    private static let sp96Type: UInt32 = 0x7370_3936 // "sp96"
    private static let userClientSelector: UInt32 = 2
    private static let readBytesCommand: UInt8 = 5
    private static let readKeyInfoCommand: UInt8 = 9

    static func read() -> FixedSMCPower {
        guard MemoryLayout<SMCKeyData>.size == 80 else {
            return FixedSMCPower(adapterW: nil, systemW: nil)
        }

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else {
            return FixedSMCPower(adapterW: nil, systemW: nil)
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return FixedSMCPower(adapterW: nil, systemW: nil)
        }
        defer { IOServiceClose(connection) }

        return FixedSMCPower(
            adapterW: readWatts(adapterKey, connection: connection),
            systemW: readWatts(systemKey, connection: connection)
        )
    }

    private static func readWatts(_ key: UInt32, connection: io_connect_t) -> Double? {
        var infoRequest = SMCKeyData()
        infoRequest.key = key
        infoRequest.data8 = readKeyInfoCommand
        guard let infoReply = call(infoRequest, connection: connection) else { return nil }

        let size = Int(infoReply.keyInfo.dataSize)
        guard size > 0, size <= 32 else { return nil }

        var valueRequest = SMCKeyData()
        valueRequest.key = key
        valueRequest.keyInfo.dataSize = infoReply.keyInfo.dataSize
        valueRequest.data8 = readBytesCommand
        guard let valueReply = call(valueRequest, connection: connection) else { return nil }

        let bytes = withUnsafeBytes(of: valueReply.bytes) { Array($0.prefix(size)) }
        let watts: Double?
        switch infoReply.keyInfo.dataType {
        case floatType where bytes.count == 4:
            // SMC `flt ` values use host/little-endian byte order on supported Macs.
            let bits = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            watts = Double(Float(bitPattern: bits))
        case sp78Type where bytes.count == 2:
            watts = decodeSignedFixedPoint(bytes, fractionalBits: 8)
        case sp96Type where bytes.count == 2:
            watts = decodeSignedFixedPoint(bytes, fractionalBits: 6)
        default:
            watts = nil
        }

        guard let watts, watts.isFinite, (0 ... 1_000).contains(watts) else { return nil }
        return watts
    }

    private static func decodeSignedFixedPoint(
        _ bytes: [UInt8],
        fractionalBits: Int
    ) -> Double? {
        guard bytes.count == 2, (0 ... 15).contains(fractionalBits) else { return nil }
        let bits = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        return Double(Int16(bitPattern: bits)) / Double(1 << fractionalBits)
    }

    private static func call(_ request: SMCKeyData, connection: io_connect_t) -> SMCKeyData? {
        var request = request
        var reply = SMCKeyData()
        var replySize = MemoryLayout<SMCKeyData>.size
        let result = IOConnectCallStructMethod(
            connection,
            userClientSelector,
            &request,
            MemoryLayout<SMCKeyData>.size,
            &reply,
            &replySize
        )
        guard result == kIOReturnSuccess,
              replySize == MemoryLayout<SMCKeyData>.size,
              reply.result == 0 else { return nil }
        return reply
    }
}

private func fixedPowerReply() -> String {
    let power = FixedSMCPowerReader.read()
    guard power.adapterW != nil || power.systemW != nil else {
        return #"{"ok":false,"error":"power sensors unavailable"}"#
    }

    var object: [String: Any] = ["ok": true]
    if let adapterW = power.adapterW { object["adapterW"] = adapterW }
    if let systemW = power.systemW { object["systemW"] = systemW }
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let reply = String(data: data, encoding: .utf8) else {
        return #"{"ok":false,"error":"power encoding failed"}"#
    }
    return reply
}

/// The console owner is the only UID allowed to talk to us.
private func consoleUID() -> uid_t? {
    var info = stat()
    guard stat("/dev/console", &info) == 0 else { return nil }
    return info.st_uid
}

private enum Mode: String {
    case low, auto, high
}

private enum BatteryPreferenceWorkerOperation: String {
    case read = "--battery-preference-read"
    case hide = "--battery-preference-hide"
    case show = "--battery-preference-show"
}

private func runExitCode(_ args: [String]) -> Int32? {
    var pid: pid_t = 0
    var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
    argv.append(nil)
    defer { argv.forEach { free($0) } }

    guard posix_spawn(&pid, args[0], nil, nil, &argv, environ) == 0 else { return nil }
    var status: Int32 = 0
    let deadline = Date().addingTimeInterval(childTimeout)
    while true {
        let result = waitpid(pid, &status, WNOHANG)
        if result == pid {
            guard (status & 0x7f) == 0 else { return nil }
            return (status >> 8) & 0xff
        }
        if result < 0, errno != EINTR { return nil }
        if Date() >= deadline {
            _ = kill(pid, SIGKILL)
            _ = waitpid(pid, &status, 0)
            return nil
        }
        usleep(10_000)
    }
}

private func run(_ args: [String]) -> Bool {
    runExitCode(args) == 0
}

private func runPmset(_ mode: Mode) -> Bool {
    // Constant argument vectors, one per mode. No caller-supplied value is
    // ever placed here — the request only selects which constant to run.
    switch mode {
    case .low:  return run(["/usr/bin/pmset", "-a", "powermode", "1"])
    case .auto: return run(["/usr/bin/pmset", "-a", "powermode", "0"])
    case .high: return run(["/usr/bin/pmset", "-a", "powermode", "2"])
    }
}

/// The power mode actually in force, for whichever source is supplying power.
///
/// The preference file looks like the obvious source and is the wrong one:
/// powerd writes it lazily and coalesces, so it lags the real setting by a
/// whole transition. Measured on this machine, it held `LowPowerMode = 2`
/// while pmset reported powermode 0, and held 0 right after a switch to high.
/// Reading it is what made High Power look like it never applied — it applied
/// every time, and the readback lost it. `pmset -g live` was correct and
/// immediate across seven consecutive transitions.
private func livePowerMode() -> Mode? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-g", "live"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let text = String(data: data, encoding: .utf8) else { return nil }
    for line in text.split(separator: "\n") {
        let fields = line.split(whereSeparator: { $0.isWhitespace })
        guard fields.first?.lowercased() == "powermode",
              let value = fields.last.flatMap({ Int($0) }) else { continue }
        switch value {
        case 0: return .auto
        case 1: return .low
        case 2: return .high
        default: return nil
        }
    }
    return nil
}

/// The app is sandboxed and cannot read /Library/Preferences, so it cannot see
/// the power-mode keys at all. This process runs as root outside the sandbox,
/// which is the only reason it can answer. Only used to tell whether the
/// hardware has the feature — the key's presence is stable even though its
/// value is not.
private func powerPreferences() -> [String: [String: Any]]? {
    let directory = "/Library/Preferences"
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return nil }
    for name in names
    where name.hasPrefix("com.apple.PowerManagement.") && name.hasSuffix(".plist") {
        guard let raw = NSDictionary(contentsOfFile: "\(directory)/\(name)") as? [String: Any] else { continue }
        let sources = raw.compactMapValues { $0 as? [String: Any] }
        if sources.values.contains(where: { $0["HighPowerMode"] != nil || $0["LowPowerMode"] != nil }) {
            return sources
        }
    }
    return nil
}

/// The HighPowerMode key only exists on hardware that has the feature. Being
/// in high power right now is proof on its own, and does not depend on a file
/// whose values cannot be trusted.
private func supportsHighPower(current: Mode) -> Bool {
    if current == .high { return true }
    return powerPreferences()?.values.contains { $0["HighPowerMode"] != nil } ?? false
}

private func modeReply(_ mode: Mode) -> String {
    let supportsHigh = supportsHighPower(current: mode)
    return #"{"ok":true,"mode":"\#(mode.rawValue)","supportsHigh":\#(supportsHigh),"modeVerified":true}"#
}

/// The installer runs this client mode as root while its rollback backup still
/// exists. It proves the newly bootstrapped service can authenticate the console
/// user and answer over its socket without requiring battery hardware to expose
/// a power-mode value.
private func helperHealthProbeOnce() -> Bool {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }

    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
    guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutSize) == 0,
          setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutSize) == 0 else {
        return false
    }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(helperSocketPath.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.copyBytes(from: pathBytes)
    }

    let addressSize = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, addressSize)
        }
    }
    guard connected == 0 else { return false }

    let request = Data(#"{"op":"health"}"#.utf8)
    let wrote = request.withUnsafeBytes { write(fd, $0.baseAddress, request.count) }
    guard wrote == request.count else { return false }

    var buffer = [UInt8](repeating: 0, count: 512)
    let count = read(fd, &buffer, buffer.count)
    guard count > 0,
          let response = try? JSONSerialization.jsonObject(
              with: Data(buffer[0..<count])
          ) as? [String: Any] else { return false }
    return response["ok"] as? Bool == true
        && response["health"] as? Bool == true
}

private func newlyInstalledHelperIsHealthy() -> Bool {
    let deadline = Date().addingTimeInterval(8)
    repeat {
        if helperHealthProbeOnce() { return true }
        usleep(100_000)
    } while Date() < deadline
    return false
}

private func dropHealthProbePrivilegesToConsoleUser() -> Bool {
    guard geteuid() == 0,
          let uid = consoleUID(), uid != 0,
          let account = getpwuid(uid),
          let name = account.pointee.pw_name else { return false }
    let userName = String(cString: name)
    let gid = account.pointee.pw_gid
    return userName.withCString { initgroups($0, Int32(bitPattern: gid)) == 0 }
        && setgid(gid) == 0
        && setuid(uid) == 0
}

private struct UserAccount {
    let uid: uid_t
    let gid: gid_t
    let name: String
    let home: String

    var appPath: String {
        "/Applications/Wattson.app"
    }

    var legacyAppPath: String {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Applications/Wattson.app")
            .path
    }

    var agentDirectory: String {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/LaunchAgents")
            .path
    }

    var agentPath: String {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/LaunchAgents/\(loginAgentLabel).plist")
            .path
    }
}

/// Account data comes from the authenticated peer UID, never from JSON.
private func userAccount(for uid: uid_t) -> UserAccount? {
    guard uid != 0,
          let record = getpwuid(uid),
          let rawName = record.pointee.pw_name,
          let rawHome = record.pointee.pw_dir else { return nil }
    let name = String(cString: rawName)
    let home = String(cString: rawHome)
    guard !name.isEmpty, home.hasPrefix("/") else { return nil }
    return UserAccount(uid: uid, gid: record.pointee.pw_gid, name: name, home: home)
}

private func currentSupplementaryGroups() -> [gid_t]? {
    let count = getgroups(0, nil)
    guard count >= 0 else { return nil }
    guard count > 0 else { return [] }
    var groups = [gid_t](repeating: 0, count: Int(count))
    let readCount = groups.withUnsafeMutableBufferPointer {
        getgroups(count, $0.baseAddress)
    }
    return readCount == count ? groups : nil
}

private func restoreSupplementaryGroups(_ groups: [gid_t]) -> Bool {
    if groups.isEmpty { return setgroups(0, nil) == 0 }
    return groups.withUnsafeBufferPointer {
        setgroups(Int32($0.count), $0.baseAddress)
    } == 0
}

/// User-controlled home-directory paths are never touched with root file
/// privileges. The helper is single-threaded, so changing effective IDs cannot
/// leak into another request. `defer` also covers every early failure path.
private func withUserPrivileges(_ account: UserAccount, body: () -> Bool) -> Bool {
    let originalUID = geteuid()
    let originalGID = getegid()
    guard originalUID == 0, originalGID == 0,
          let originalGroups = currentSupplementaryGroups() else { return false }

    defer {
        guard seteuid(0) == 0,
              restoreSupplementaryGroups(originalGroups),
              setegid(0) == 0 else {
            os_log("could not restore helper privileges", log: log, type: .fault)
            exit(1)
        }
    }

    let groupsReady = account.name.withCString {
        initgroups($0, Int32(bitPattern: account.gid)) == 0
    }
    guard groupsReady,
          setegid(account.gid) == 0,
          seteuid(account.uid) == 0 else { return false }
    return body()
}

private func loginAgentPlist(
    for account: UserAccount,
    appPath: String? = nil
) -> [String: Any] {
    [
        "Label": loginAgentLabel,
        "ProgramArguments": ["/usr/bin/open", "-gj", appPath ?? account.appPath],
        "RunAtLoad": true,
        "LimitLoadToSessionType": "Aqua",
        "ProcessType": "Interactive",
        "AssociatedBundleIdentifiers": [wattsonBundleIdentifier],
    ]
}

private func loginAgentMatches(_ appPath: String, for account: UserAccount) -> Bool {
    withUserPrivileges(account) {
        var info = stat()
        guard lstat(account.agentPath, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == account.uid,
              info.st_gid == account.gid,
              (info.st_mode & 0o777) == 0o644,
              info.st_size > 0,
              info.st_size <= 65_536,
              let data = try? Data(contentsOf: URL(fileURLWithPath: account.agentPath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                  as? [String: Any] else { return false }

        let expected = loginAgentPlist(for: account, appPath: appPath)
        guard plist.count == expected.count else { return false }
        return plist["Label"] as? String == loginAgentLabel
            && plist["ProgramArguments"] as? [String] == ["/usr/bin/open", "-gj", appPath]
            && plist["RunAtLoad"] as? Bool == true
            && plist["LimitLoadToSessionType"] as? String == "Aqua"
            && plist["ProcessType"] as? String == "Interactive"
            && plist["AssociatedBundleIdentifiers"] as? [String] == [wattsonBundleIdentifier]
    }
}

private func loginAgentIsCanonical(for account: UserAccount) -> Bool {
    loginAgentMatches(account.appPath, for: account)
}

private func loginAgentIsLegacyCanonical(for account: UserAccount) -> Bool {
    loginAgentMatches(account.legacyAppPath, for: account)
}

private func writeLoginAgent(for account: UserAccount) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: account.appPath, isDirectory: &isDirectory),
          isDirectory.boolValue,
          let data = try? PropertyListSerialization.data(
              fromPropertyList: loginAgentPlist(for: account),
              format: .xml,
              options: 0
          ) else { return false }

    let wrote = withUserPrivileges(account) {
        do {
            try FileManager.default.createDirectory(
                atPath: account.agentDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            try data.write(to: URL(fileURLWithPath: account.agentPath), options: .atomic)
            return chmod(account.agentPath, 0o644) == 0
        } catch {
            return false
        }
    }
    return wrote && loginAgentIsCanonical(for: account)
}

private func removeLoginAgent(for account: UserAccount) -> Bool {
    withUserPrivileges(account) {
        var info = stat()
        guard lstat(account.agentPath, &info) == 0 else { return errno == ENOENT }
        guard (info.st_mode & S_IFMT) != S_IFDIR else { return false }
        return unlink(account.agentPath) == 0
    }
}

private func loginAgentTarget(for account: UserAccount) -> String {
    "gui/\(account.uid)/\(loginAgentLabel)"
}

private func loginAgentIsLoaded(for account: UserAccount) -> Bool {
    run(["/bin/launchctl", "print", loginAgentTarget(for: account)])
}

private func launchAtLoginEnabled(for uid: uid_t) -> Bool? {
    guard uid == consoleUID(), let account = userAccount(for: uid) else { return nil }
    guard loginAgentIsLoaded(for: account) else { return false }
    if loginAgentIsCanonical(for: account) { return true }

    // v2 stored the app in ~/Applications. Migrate only its exact, user-owned
    // LaunchAgent contract after the v3 app has landed at /Applications.
    guard loginAgentIsLegacyCanonical(for: account) else { return false }
    return setLaunchAtLoginEnabled(true, for: uid)
}

private func setLaunchAtLoginEnabled(_ enabled: Bool, for uid: uid_t) -> Bool? {
    // Recheck the console owner immediately before mutation in case fast-user
    // switching happened after the socket was authenticated.
    guard uid == consoleUID(), let account = userAccount(for: uid) else { return nil }
    let target = loginAgentTarget(for: account)

    if enabled {
        if loginAgentIsCanonical(for: account) && loginAgentIsLoaded(for: account) { return true }
        _ = run(["/bin/launchctl", "bootout", target])
        guard writeLoginAgent(for: account),
              run(["/bin/launchctl", "enable", target]),
              run(["/bin/launchctl", "bootstrap", "gui/\(account.uid)", account.agentPath]),
              loginAgentIsLoaded(for: account) else {
            _ = run(["/bin/launchctl", "bootout", target])
            _ = removeLoginAgent(for: account)
            return nil
        }
        return true
    }

    // Remove the persistent file first. Even if launchctl reports a transient
    // failure, the app cannot return at the next login.
    guard removeLoginAgent(for: account) else { return nil }
    _ = run(["/bin/launchctl", "bootout", target])
    return loginAgentIsLoaded(for: account) ? nil : false
}

/// A native PKG does not launch the app after installation. Migrate an exact
/// loaded v2 LaunchAgent before postinstall removes the v2 user-local app, so
/// launch at login keeps working even if the user does not open v3 immediately.
private func migrateLegacyLoginAgentForInstaller() -> Bool {
    guard geteuid() == 0 else { return false }
    guard let uid = consoleUID(), uid != 0,
          let account = userAccount(for: uid) else { return true }
    guard loginAgentIsLegacyCanonical(for: account) else { return true }
    return setLaunchAtLoginEnabled(true, for: uid) == true
}

/// Control Center stores Battery as 18 when it is in both Control Center and
/// the menu bar, and 8 when it remains in Control Center only. Unknown values
/// are not guessed at, so a future macOS layout cannot be overwritten from a
/// misleading checkbox state.
private func currentUserSystemBatteryIconHidden() -> Bool? {
    guard CFPreferencesSynchronize(
        controlCenterDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesCurrentHost
    ) else { return nil }
    guard let raw = CFPreferencesCopyValue(
        controlCenterBatteryKey,
        controlCenterDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesCurrentHost
    ) as? NSNumber else { return nil }
    switch raw.intValue {
    case 8: return true
    case 18: return false
    default: return nil
    }
}

private func setCurrentUserSystemBatteryIconHidden(_ hidden: Bool) -> Bool {
    CFPreferencesSetValue(
        controlCenterBatteryKey,
        NSNumber(value: hidden ? 8 : 18),
        controlCenterDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesCurrentHost
    )
    return currentUserSystemBatteryIconHidden() == hidden
}

private func runBatteryPreferenceWorker(
    _ operation: BatteryPreferenceWorkerOperation,
    for uid: uid_t
) -> Int32? {
    guard uid == consoleUID(), userAccount(for: uid) != nil else { return nil }
    return runExitCode([
        "/bin/launchctl", "asuser", "\(uid)", helperExecutablePath,
        operation.rawValue,
    ])
}

private func systemBatteryIconHidden(for uid: uid_t) -> Bool? {
    switch runBatteryPreferenceWorker(.read, for: uid) {
    case 8: return true
    case 18: return false
    default: return nil
    }
}

private func restartControlCenter(for uid: uid_t) -> Bool {
    // uid comes from /dev/console, never from the request. launchd immediately
    // relaunches this per-user agent; launchctl kickstart is rejected by SIP.
    guard let exitCode = runExitCode([
        "/usr/bin/pkill", "-TERM", "-U", "\(uid)", "-x", "ControlCenter",
    ]) else { return false }
    return exitCode == 0 || exitCode == 1
}

private func setSystemBatteryIconHidden(_ hidden: Bool, for uid: uid_t) -> Bool {
    let operation: BatteryPreferenceWorkerOperation = hidden ? .hide : .show
    guard runBatteryPreferenceWorker(operation, for: uid) == 0 else { return false }
    return restartControlCenter(for: uid)
}

private func runBatteryPreferenceWorkerIfRequested() {
    guard CommandLine.arguments.count == 2,
          let operation = BatteryPreferenceWorkerOperation(
              rawValue: CommandLine.arguments[1]
          ) else { return }

    // `launchctl asuser` supplies the console user's bootstrap context but
    // intentionally keeps root credentials. Permanently drop those credentials
    // before touching CurrentUser preferences so both dimensions match the
    // logged-in user's cfprefsd instance.
    guard dropHealthProbePrivilegesToConsoleUser() else { exit(2) }
    switch operation {
    case .read:
        guard let hidden = currentUserSystemBatteryIconHidden() else { exit(2) }
        exit(hidden ? 8 : 18)
    case .hide:
        exit(setCurrentUserSystemBatteryIconHidden(true) ? 0 : 2)
    case .show:
        exit(setCurrentUserSystemBatteryIconHidden(false) ? 0 : 2)
    }
}

private func handle(_ fd: Int32) {
    defer { close(fd) }

    // A same-user process can connect to the public socket. Never let a client
    // that stops mid-request pin this single-threaded on-demand helper.
    var socketTimeout = timeval(tv_sec: 2, tv_usec: 0)
    let socketTimeoutSize = socklen_t(MemoryLayout<timeval>.size)
    guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &socketTimeout, socketTimeoutSize) == 0,
          setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &socketTimeout, socketTimeoutSize) == 0 else {
        return
    }

    var peerUID: uid_t = 0
    var peerGID: gid_t = 0
    guard getpeereid(fd, &peerUID, &peerGID) == 0, peerUID == consoleUID() else {
        os_log("rejected connection from uid %{public}d", log: log, type: .error, Int(peerUID))
        return
    }

    var buffer = [UInt8](repeating: 0, count: 512)
    let count = read(fd, &buffer, buffer.count)
    guard count > 0,
          let object = try? JSONSerialization.jsonObject(with: Data(buffer[0..<count])) as? [String: Any],
          let op = object["op"] as? String else {
        _ = #"{"ok":false,"error":"malformed"}"#.withCString { write(fd, $0, strlen($0)) }
        return
    }

    var reply = #"{"ok":false,"error":"rejected"}"#

    switch op {
    case "health":
        reply = #"{"ok":true,"health":true}"#
    case "getPower":
        reply = fixedPowerReply()
    case "getMode":
        if let mode = livePowerMode() {
            reply = modeReply(mode)
        } else {
            reply = #"{"ok":false,"error":"mode readback failed"}"#
        }
    case "setMode":
        if let raw = object["value"] as? String, let mode = Mode(rawValue: raw) {
            if runPmset(mode), let landed = livePowerMode() {
                reply = modeReply(landed)
            } else {
                reply = #"{"ok":false,"error":"pmset or readback failed"}"#
            }
        } else {
            os_log("rejected setMode with unknown value", log: log, type: .error)
        }
    case "getSystemBatteryIconHidden":
        if let hidden = systemBatteryIconHidden(for: peerUID) {
            reply = hidden ? #"{"ok":true,"hidden":true}"#
                           : #"{"ok":true,"hidden":false}"#
        } else {
            reply = #"{"ok":false,"error":"unknown battery preference"}"#
        }
    case "setSystemBatteryIconHidden":
        if let hidden = object["hidden"] as? Bool {
            let ok = setSystemBatteryIconHidden(hidden, for: peerUID)
            if ok {
                reply = hidden ? #"{"ok":true,"hidden":true}"#
                               : #"{"ok":true,"hidden":false}"#
            } else {
                reply = #"{"ok":false,"error":"control center update failed"}"#
            }
        } else {
            os_log("rejected battery visibility with a non-boolean value", log: log, type: .error)
        }
    case "getLaunchAtLoginEnabled":
        if let enabled = launchAtLoginEnabled(for: peerUID) {
            reply = enabled ? #"{"ok":true,"enabled":true}"#
                            : #"{"ok":true,"enabled":false}"#
        } else {
            reply = #"{"ok":false,"error":"login item readback failed"}"#
        }
    case "setLaunchAtLoginEnabled":
        if let enabled = object["enabled"] as? Bool,
           let landed = setLaunchAtLoginEnabled(enabled, for: peerUID) {
            reply = landed ? #"{"ok":true,"enabled":true}"#
                           : #"{"ok":true,"enabled":false}"#
        } else {
            os_log("login item update failed or received a non-boolean value", log: log, type: .error)
            reply = #"{"ok":false,"error":"login item update failed"}"#
        }
    default:
        os_log("rejected unknown op", log: log, type: .error)
    }

    _ = reply.withCString { write(fd, $0, strlen($0)) }
}

@main
private enum WattsonHelperMain {
    static func main() {
        runBatteryPreferenceWorkerIfRequested()

        if CommandLine.arguments.count == 2,
           CommandLine.arguments[1] == "--migrate-legacy-login-item" {
            exit(migrateLegacyLoginAgentForInstaller() ? 0 : 1)
        }

        if CommandLine.arguments.count == 2,
           CommandLine.arguments[1] == "--health-probe" {
            if !dropHealthProbePrivilegesToConsoleUser() { exit(1) }
            exit(newlyInstalledHelperIsHealthy() ? 0 : 1)
        }

        // Socket activation: launchd already opened and bound the listener.
        // The parameter is a pointer to a non-optional pointer, so this starts as a
        // throwaway allocation that launch_activate_socket overwrites with its own
        // malloc'd array. On success the caller owns that array and must free it.
        var fds = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        var fdCount: size_t = 0
        guard launch_activate_socket("Listener", &fds, &fdCount) == 0, fdCount > 0 else {
            os_log("no launchd socket", log: log, type: .fault)
            exit(1)
        }
        let listener = fds[0]
        free(fds)

        var lastActivity = Date()
        while true {
            var readSet = fd_set()
            __darwin_fd_set(listener, &readSet)
            var timeout = timeval(tv_sec: 1, tv_usec: 0)

            if select(listener + 1, &readSet, nil, nil, &timeout) > 0 {
                let client = accept(listener, nil, nil)
                if client >= 0 {
                    handle(client)
                    lastActivity = Date()
                }
            }

            if Date().timeIntervalSince(lastActivity) > idleTimeout {
                exit(0)
            }
        }
    }
}
