import Foundation

/// Reads and changes the Apple battery menu-extra through the privileged
/// helper. A sandboxed app cannot access another process's preferences.
enum SystemBatteryIconController {
    private static let refreshQueue = DispatchQueue(
        label: "com.leoarrow.wattson.system-battery-icon",
        qos: .userInitiated
    )

    static var isHidden: Bool? {
        let reply = HelperClient.send(["op": "getSystemBatteryIconHidden"])
        guard reply?["ok"] as? Bool == true else { return nil }
        return reply?["hidden"] as? Bool
    }

    static func refreshHidden(_ completion: @escaping (Bool?) -> Void) {
        refreshQueue.async {
            let hidden = isHidden
            DispatchQueue.main.async { completion(hidden) }
        }
    }

    @discardableResult
    static func setHidden(_ hidden: Bool) -> Bool {
        let reply = HelperClient.send([
            "op": "setSystemBatteryIconHidden",
            "hidden": hidden,
        ])
        return (reply?["ok"] as? Bool) ?? false
    }
}
