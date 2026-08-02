import Darwin
import Foundation
import os

private let log = OSLog(subsystem: "com.leoarrow.wattson.helper", category: "ipc")
private let idleTimeout: TimeInterval = 5
private let controlCenterDomain = "com.apple.controlcenter" as CFString
private let controlCenterBatteryKey = "Battery" as CFString

/// The console owner is the only UID allowed to talk to us.
private func consoleUID() -> uid_t? {
    var info = stat()
    guard stat("/dev/console", &info) == 0 else { return nil }
    return info.st_uid
}

private enum Mode: String {
    case low, auto, high
}

private func run(_ args: [String]) -> Bool {
    var pid: pid_t = 0
    var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
    argv.append(nil)
    defer { argv.forEach { free($0) } }

    guard posix_spawn(&pid, args[0], nil, nil, &argv, environ) == 0 else { return false }
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    return status == 0
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

/// The app is sandboxed and cannot read /Library/Preferences, so it cannot see
/// the power-mode keys at all. This process runs as root outside the sandbox,
/// which is the only reason it can answer.
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

private func flag(_ key: String) -> Int {
    guard let prefs = powerPreferences() else { return 0 }
    for source in ["AC Power", "Battery Power"] {
        if let value = prefs[source]?[key] as? Int { return value }
    }
    return 0
}

private func currentMode() -> String {
    if flag("LowPowerMode") == 1 { return "low" }
    return flag("HighPowerMode") == 1 ? "high" : "auto"
}

/// The HighPowerMode key only exists on hardware that has the feature.
private func supportsHighPower() -> Bool {
    powerPreferences()?.values.contains { $0["HighPowerMode"] != nil } ?? false
}

private func userName(for uid: uid_t) -> CFString? {
    guard let record = getpwuid(uid), let name = record.pointee.pw_name else { return nil }
    return String(cString: name) as CFString
}

/// Control Center stores Battery as 18 when it is in both Control Center and
/// the menu bar, and 8 when it remains in Control Center only. Unknown values
/// are not guessed at, so a future macOS layout cannot be overwritten from a
/// misleading checkbox state.
private func systemBatteryIconHidden(for uid: uid_t) -> Bool? {
    guard let user = userName(for: uid),
          let raw = CFPreferencesCopyValue(
              controlCenterBatteryKey,
              controlCenterDomain,
              user,
              kCFPreferencesCurrentHost
          ) as? NSNumber else { return nil }
    switch raw.intValue {
    case 8: return true
    case 18: return false
    default: return nil
    }
}

private func restartControlCenter(for uid: uid_t) -> Bool {
    // uid comes from /dev/console, never from the request. launchd immediately
    // relaunches this per-user agent; launchctl kickstart is rejected by SIP.
    run(["/usr/bin/pkill", "-TERM", "-U", "\(uid)", "-x", "ControlCenter"])
}

private func setSystemBatteryIconHidden(_ hidden: Bool, for uid: uid_t) -> Bool {
    guard let user = userName(for: uid) else { return false }
    let target = hidden ? 8 : 18
    CFPreferencesSetValue(
        controlCenterBatteryKey,
        NSNumber(value: target),
        controlCenterDomain,
        user,
        kCFPreferencesCurrentHost
    )
    guard CFPreferencesSynchronize(
        controlCenterDomain,
        user,
        kCFPreferencesCurrentHost
    ), systemBatteryIconHidden(for: uid) == hidden else { return false }
    return restartControlCenter(for: uid)
}

private func handle(_ fd: Int32) {
    defer { close(fd) }

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
    case "getMode":
        reply = "{\"ok\":true,\"mode\":\"\(currentMode())\",\"supportsHigh\":\(supportsHighPower())}"
    case "setMode":
        if let raw = object["value"] as? String, let mode = Mode(rawValue: raw) {
            let ok = runPmset(mode)
            reply = ok ? "{\"ok\":true,\"mode\":\"\(currentMode())\",\"supportsHigh\":\(supportsHighPower())}"
                       : #"{"ok":false,"error":"pmset failed"}"#
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
    default:
        os_log("rejected unknown op", log: log, type: .error)
    }

    _ = reply.withCString { write(fd, $0, strlen($0)) }
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
