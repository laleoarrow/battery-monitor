import Foundation

enum LoginItemState: Equatable {
    case checking
    case unavailable
    case readFailed
    case notRegistered
    case enabled
}

enum LoginItemError: LocalizedError {
    case unavailable
    case updateFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "当前安装缺少最新助手，请使用完整安装器更新 Wattson。"
        case .updateFailed:
            return "系统未能更新登录启动项，请稍后重试。"
        }
    }
}

/// The ad-hoc private build cannot use the signed-app registration API
/// reliably. Its fixed-command helper owns a per-user LaunchAgent instead.
/// Every socket call stays off AppKit's thread, so opening never waits on launchd.
enum LoginItemController {
    private static let queue = DispatchQueue(label: "com.leoarrow.wattson.login-item")
    private static var generation = 0
    private static var cachedState: LoginItemState = canManageInstalledApp && HelperClient.isInstalled
        ? .checking
        : .unavailable

    private static var canManageInstalledApp: Bool {
        Bundle.main.bundleIdentifier == "com.leoarrow.wattson"
    }

    static var state: LoginItemState { cachedState }

    static func refresh(completion: ((LoginItemState) -> Void)? = nil) {
        guard canManageInstalledApp, HelperClient.isInstalled else {
            cachedState = .unavailable
            completion?(.unavailable)
            return
        }

        generation += 1
        let requestGeneration = generation
        queue.async {
            let reply = HelperClient.send(["op": "getLaunchAtLoginEnabled"])
            let refreshed = state(from: reply)
            DispatchQueue.main.async {
                guard requestGeneration == generation else { return }
                cachedState = refreshed
                completion?(refreshed)
            }
        }
    }

    static func setEnabled(
        _ enabled: Bool,
        completion: @escaping (Result<LoginItemState, Error>) -> Void
    ) {
        guard canManageInstalledApp, HelperClient.isInstalled else {
            completion(.failure(LoginItemError.unavailable))
            return
        }

        generation += 1
        let requestGeneration = generation
        queue.async {
            let reply = HelperClient.send([
                "op": "setLaunchAtLoginEnabled",
                "enabled": enabled,
            ])
            let refreshed = state(from: reply)
            let succeeded = reply?["ok"] as? Bool == true
                && (reply?["enabled"] as? Bool) == enabled
            let helperUnavailable = reply?["error"] as? String == "rejected"

            DispatchQueue.main.async {
                if succeeded {
                    if requestGeneration == generation { cachedState = refreshed }
                    completion(.success(refreshed))
                } else {
                    completion(.failure(
                        helperUnavailable ? LoginItemError.unavailable : LoginItemError.updateFailed
                    ))
                }
            }
        }
    }

    private static func state(from reply: [String: Any]?) -> LoginItemState {
        guard let reply else { return .readFailed }
        guard reply["ok"] as? Bool == true,
              let enabled = reply["enabled"] as? Bool else {
            return reply["error"] as? String == "rejected" ? .unavailable : .readFailed
        }
        return enabled ? .enabled : .notRegistered
    }
}
