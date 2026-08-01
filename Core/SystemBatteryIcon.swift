import Foundation

/// Reads and changes the Apple battery menu-extra through the privileged
/// helper. A sandboxed app cannot access another process's preferences.
enum SystemBatteryIconController {
    static var isHidden: Bool? {
        let reply = HelperClient.send(["op": "getSystemBatteryIconHidden"])
        guard reply?["ok"] as? Bool == true else { return nil }
        return reply?["hidden"] as? Bool
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
