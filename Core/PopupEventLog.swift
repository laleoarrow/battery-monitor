import AppKit
import os

/// Opt-in live collection uses the unified log's info stream. Record only popup
/// routing metadata; never record pointer coordinates, window titles or keys.
enum PopupEventLog {
    private static let log = Logger(subsystem: "com.leoarrow.wattson", category: "popup-events")

    static func record(source: String, event: NSEvent?, openBefore: Bool,
                       openAfter: Bool, anchorHit: Bool) {
        let mouse: NSEvent?
        switch event?.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp: mouse = event
        default: mouse = nil
        }
        let type = mouse.map { Int($0.type.rawValue) } ?? -1
        let number = mouse?.eventNumber ?? -1
        let window = mouse?.windowNumber ?? -1
        log.info("source=\(source, privacy: .public) eventType=\(type) eventNumber=\(number) windowNumber=\(window) openBefore=\(openBefore) openAfter=\(openAfter) anchorHit=\(anchorHit)")
    }
}
