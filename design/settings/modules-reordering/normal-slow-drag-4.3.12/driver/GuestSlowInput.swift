import AppKit
import ApplicationServices
import Darwin
import IOKit

struct Point: Decodable { let x: Double; let y: Double }
struct Plan: Decodable {
    let hardwareUUID: String
    let pid: Int32
    let bundleID: String
    let windowID: UInt32
    let caseName: String
    let source: Point
    let target: Point
    let duration: Double
    let holdBefore: Double
    let holdAfter: Double
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "GuestSlowInput", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: message]) }
}

func model() -> String {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0 else { return "" }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "" }
    return String(cString: bytes)
}

func hardwareUUID() -> String {
    let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                              IOServiceMatching("IOPlatformExpertDevice"))
    guard service != 0 else { return "" }
    defer { IOObjectRelease(service) }
    return IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString,
        kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? ""
}

if CommandLine.arguments.dropFirst() == ["--preflight"] {
    guard model().hasPrefix("VirtualMac") else { exit(78) }
    let result: [String: Any] = ["hardwareUUID": hardwareUUID(),
        "postEventAccess": CGPreflightPostEventAccess(), "inputAttempted": false]
    let data = try JSONSerialization.data(withJSONObject: result, options: .sortedKeys)
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

final class Pointer {
    let source = CGEventSource(stateID: .combinedSessionState)!
    let lock = NSLock()
    var down = false
    var stopped = false
    var point = CGPoint.zero
    var journal: [[String: Any]] = []
    func send(_ type: CGEventType, _ target: CGPoint) throws {
        lock.lock(); defer { lock.unlock() }
        try require(!stopped || type == .leftMouseUp, "Input driver was interrupted")
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: target, mouseButton: .left) else {
            throw NSError(domain: "GuestSlowInput", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot construct mouse event"])
        }
        point = target
        if type == .leftMouseDown { down = true }
        if type == .leftMouseUp { down = false }
        event.post(tap: .cghidEventTap)
        journal.append(["type": type.rawValue, "x": target.x, "y": target.y,
                        "uptime": ProcessInfo.processInfo.systemUptime])
    }
    func release() {
        lock.lock(); let held = down; let last = point; lock.unlock()
        if held { try? send(.leftMouseUp, last) }
    }
    func interrupt() {
        lock.lock(); stopped = true; lock.unlock()
        release()
    }
}

var signals: [DispatchSourceSignal] = []
let pointer = Pointer()
var report: [String: Any] = ["inputMethod": "guest-CGEvent", "hostInput": false,
                            "inputAttempted": false, "postSequenceCompleted": false]
var output: URL?
var status: Int32 = 0
do {
    try require(CommandLine.arguments.count == 3, "Expected plan.json and report.json")
    let planURL = URL(fileURLWithPath: CommandLine.arguments[1])
    output = URL(fileURLWithPath: CommandLine.arguments[2])
    let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: planURL))
    try require(model().hasPrefix("VirtualMac"), "Refusing input outside a macOS VM")
    try require(!plan.hardwareUUID.isEmpty && hardwareUUID() == plan.hardwareUUID,
                "Guest UUID does not match the owned VM")
    try require(plan.bundleID.hasPrefix("com.leoarrow.wattson.modules-slow."),
                "Unexpected target bundle identifier")
    try require(plan.duration >= 1 && plan.duration <= 5 &&
                (0.2...2).contains(plan.holdBefore) && (0.2...2).contains(plan.holdAfter),
                "Drag timing is outside the fixed acceptance bounds")
    let app = NSRunningApplication(processIdentifier: plan.pid)
    try require(app?.bundleIdentifier == plan.bundleID && app?.isTerminated == false,
                "Target is not the owned fixture process")
    try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == plan.pid,
                "Owned fixture is not the guest foreground application")
    let windows = CGWindowListCopyWindowInfo([.optionIncludingWindow], plan.windowID)
        as? [[String: Any]] ?? []
    try require(windows.count == 1 && (windows[0][kCGWindowOwnerPID as String] as? Int32) == plan.pid,
                "Target window does not belong to the owned fixture")
    let display = CGDisplayBounds(CGMainDisplayID())
    let start = CGPoint(x: plan.source.x, y: plan.source.y)
    let end = CGPoint(x: plan.target.x, y: plan.target.y)
    try require(start.x.isFinite && start.y.isFinite && end.x.isFinite && end.y.isFinite &&
                display.contains(start) && display.contains(end), "Coordinates leave the guest display")
    let bounds = windows[0][kCGWindowBounds as String] as? [String: Double] ?? [:]
    let frame = CGRect(x: bounds["X"] ?? .nan, y: bounds["Y"] ?? .nan,
                       width: bounds["Width"] ?? .nan, height: bounds["Height"] ?? .nan)
    try require(frame.contains(start), "Source point is outside the owned fixture window")
    let trusted = CGPreflightPostEventAccess()
    report["postEventAccess"] = trusted
    try require(trusted, "Guest event posting is not authorized; no permission request or input sent")
    report["case"] = plan.caseName
    report["pid"] = plan.pid
    report["windowID"] = plan.windowID
    for number in [SIGHUP, SIGINT, SIGTERM] {
        signal(number, SIG_IGN)
        let watcher = DispatchSource.makeSignalSource(signal: number, queue: .global())
        watcher.setEventHandler { pointer.interrupt(); exit(128 + number) }
        watcher.resume(); signals.append(watcher)
    }
    defer { pointer.release() }
    report["inputAttempted"] = true
    try pointer.send(.mouseMoved, start)
    try pointer.send(.leftMouseDown, start)
    Thread.sleep(forTimeInterval: plan.holdBefore)
    let began = ProcessInfo.processInfo.systemUptime
    for step in 1...60 {
        let fraction = Double(step) / 60
        let due = began + plan.duration * fraction
        let wait = due - ProcessInfo.processInfo.systemUptime
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        try pointer.send(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * fraction,
                                                   y: start.y + (end.y - start.y) * fraction))
    }
    Thread.sleep(forTimeInterval: plan.holdAfter)
    try pointer.send(.leftMouseUp, end)
    report["postSequenceCompleted"] = true
} catch {
    pointer.release()
    status = 78
    report["error"] = error.localizedDescription
}
report["exitCode"] = status
report["events"] = pointer.journal
if let output {
    do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(to: output, options: .atomic) }
    catch { fputs("Cannot write driver report\n", stderr); status = 1 }
}
exit(status)
