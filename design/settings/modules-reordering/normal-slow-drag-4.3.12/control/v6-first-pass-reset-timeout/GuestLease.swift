import AppKit
import CryptoKit
import IOKit
import Darwin
let share = URL(fileURLWithPath: "/Volumes/My Shared Files/normaldrag")
let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
guard service != 0 else { exit(78) }
let uuid = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? ""
IOObjectRelease(service)
guard uuid == "602C7F68-8019-5DD5-ABC9-C96B4696157A", NSHomeDirectory() == "/Users/admin" else { exit(78) }
var size = 0
sysctlbyname("hw.model", nil, &size, nil, 0)
var buf = [CChar](repeating: 0, count: size)
sysctlbyname("hw.model", &buf, &size, nil, 0)
let model = String(cString: buf)
guard model.hasPrefix("VirtualMac") else { exit(78) }
let screens = NSScreen.screens
let screen = screens[0]
let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
let b = CGDisplayBounds(displayID)
let dateFormatter = ISO8601DateFormatter()
dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
var lease: [String: Any] = ["ownedVM": "Wattson-NormalSlowDrag-20261017", "guestIP": "192.168.64.27", "platformUUID": uuid, "hwModel": model, "atUTC": dateFormatter.string(from: Date()), "inputAuthorized": true,
"inputGeometry": ["coordinateSpace": "CG-global-top-left", "screenCount": screens.count, "displayID": displayID, "screenFrameAppKit": [screen.frame.minX, screen.frame.minY, screen.frame.width, screen.frame.height], "displayBoundsCG": [b.minX,b.minY,b.width,b.height]]]
if CommandLine.arguments.dropFirst() == ["--cursor"] {
 let point = NSEvent.mouseLocation
 lease["pointerCG"] = ["x": b.minX + point.x - screen.frame.minX, "y": b.minY + screen.frame.maxY - point.y]
 lease["pressedMouseButtons"] = NSEvent.pressedMouseButtons
} else if CommandLine.arguments.count == 2 {
 let stateURL = URL(fileURLWithPath: CommandLine.arguments[1])
 guard stateURL.path.hasPrefix(share.path + "/normal-slow-drag-v6/cases/") else { exit(78) }
 let data = try Data(contentsOf: stateURL)
 let state = try JSONSerialization.jsonObject(with: data) as! [String: Any]
 let pid = (state["pid"] as! NSNumber).int32Value
 let windowID = (state["windowID"] as! NSNumber).uint32Value
 guard let app = NSRunningApplication(processIdentifier: pid), let path = app.executableURL?.path,
 path.hasPrefix("/Users/admin/Project/Wattson-NormalSlowDrag-QA/.build/"),
 app.bundleIdentifier == state["bundleID"] as? String,
 app.bundleIdentifier?.hasPrefix("com.leoarrow.wattson.modules-slow.") == true,
 let window = (CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]])?.first,
 (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
 NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { exit(78) }
 lease["pid"] = pid; lease["windowID"] = windowID; lease["bundleID"] = app.bundleIdentifier
 lease["frontmostPID"] = NSWorkspace.shared.frontmostApplication?.processIdentifier
 lease["executablePath"] = path; lease["window"] = window
 lease["stateSHA256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
let out = try JSONSerialization.data(withJSONObject: lease, options: [.sortedKeys])
print(String(decoding: out, as: UTF8.self))
