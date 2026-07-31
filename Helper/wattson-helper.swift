import Darwin
import Foundation
import os

private let log = OSLog(subsystem: "com.leoarrow.wattson.helper", category: "ipc")
private let idleTimeout: TimeInterval = 5

/// The console owner is the only UID allowed to talk to us.
private func consoleUID() -> uid_t? {
    var info = stat()
    guard stat("/dev/console", &info) == 0 else { return nil }
    return info.st_uid
}

private func runPmset(low: Bool) -> Bool {
    // Constant argument vectors. No caller-supplied value is ever placed here.
    let args = low
        ? ["/usr/bin/pmset", "-a", "lowpowermode", "1"]
        : ["/usr/bin/pmset", "-a", "lowpowermode", "0"]

    var pid: pid_t = 0
    var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
    argv.append(nil)
    defer { argv.forEach { free($0) } }

    guard posix_spawn(&pid, args[0], nil, nil, &argv, environ) == 0 else { return false }
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    return status == 0
}

private func currentMode() -> String {
    ProcessInfo.processInfo.isLowPowerModeEnabled ? "low" : "auto"
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
        reply = "{\"ok\":true,\"mode\":\"\(currentMode())\"}"
    case "setMode":
        let requested = object["value"] as? String
        if requested == "low" || requested == "auto" {
            let ok = runPmset(low: requested == "low")
            reply = ok ? "{\"ok\":true,\"mode\":\"\(currentMode())\"}"
                       : #"{"ok":false,"error":"pmset failed"}"#
        } else {
            os_log("rejected setMode with unknown value", log: log, type: .error)
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
