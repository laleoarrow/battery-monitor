import AppKit
import Foundation

let preferences = UserDefaults.standard.persistentDomain(forName: "com.apple.universalaccess") ?? [:]
let report: [String: Any] = [
    "systemReduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
    "systemReduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
    "preferenceKeyPresent": preferences["reduceMotion"] != nil,
    "preferenceReduceMotion": preferences["reduceMotion"] ?? NSNull(),
]
let bytes = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
print(String(decoding: bytes, as: UTF8.self))
