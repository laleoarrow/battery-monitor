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
    case updateInProgress
    case updateFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This installation is missing the latest helper. Update Wattson using the full installer."
        case .updateInProgress:
            return "Wattson is already updating the login item. Wait for it to finish."
        case .updateFailed:
            return "macOS couldn’t update the login item. Try again later."
        }
    }
}

/// The ad-hoc private build cannot use the signed-app registration API
/// reliably. Its fixed-command helper owns a per-user LaunchAgent instead.
/// Every socket call stays off AppKit's thread, so opening never waits on launchd.
enum LoginItemController {
    private struct SetResult {
        let state: LoginItemState
        let succeeded: Bool
        let helperUnavailable: Bool
        let requiresAuthoritativeReadback: Bool
    }

    private static let operations = CoalescingReadOperationQueue<LoginItemState>(
        label: "com.leoarrow.wattson.login-item"
    )
    private static let canonicalAppPath = "/Applications/Wattson.app"
    private static var generation = 0
    private static var cachedState: LoginItemState = canManageInstalledApp && HelperClient.isInstalled
        ? .checking
        : .unavailable
    private static var lastAuthoritativeState: LoginItemState?
    private static var updateInFlight = false
    private static var refreshWaiters: [(LoginItemState) -> Void] = []

#if DEBUG
    private static var testAvailability: Bool?
    private static var testSend: (([String: Any], Int) -> [String: Any]?)?
#endif

    private static var canManageInstalledApp: Bool {
        Bundle.main.bundleIdentifier == "com.leoarrow.wattson"
            && Bundle.main.bundleURL.standardizedFileURL.path == canonicalAppPath
    }

    private static var isAvailable: Bool {
#if DEBUG
        if let testAvailability { return testAvailability }
#endif
        return canManageInstalledApp && HelperClient.isInstalled
    }

    private static func send(
        _ request: [String: Any],
        timeoutSeconds: Int
    ) -> [String: Any]? {
#if DEBUG
        if let testSend { return testSend(request, timeoutSeconds) }
#endif
        return HelperClient.send(request, timeoutSeconds: timeoutSeconds)
    }

    static var state: LoginItemState { cachedState }

    static func refresh(completion: ((LoginItemState) -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { refresh(completion: completion) }
            return
        }

        if let completion { refreshWaiters.append(completion) }
        guard isAvailable else {
            // An unavailable transition is authoritative and must invalidate
            // any older helper completion, including an in-flight write.
            generation += 1
            cachedState = .unavailable
            completeRefreshWaiters(with: .unavailable)
            return
        }
        guard !updateInFlight else {
            // The in-flight mutation owns the next authoritative state. Keep
            // completion-bearing callers waiting for that result instead of
            // stranding a Settings control in its checking state.
            return
        }

        generation += 1
        let requestGeneration = generation
        operations.enqueueRead(
            operation: {
                state(from: send(
                    ["op": "getLaunchAtLoginEnabled"], timeoutSeconds: 15
                ))
            },
            completion: { refreshed in
                guard requestGeneration == generation else { return }
                cachedState = refreshed
                rememberAuthoritative(refreshed)
                completeRefreshWaiters(with: refreshed)
            }
        )
    }

    static func setEnabled(
        _ enabled: Bool,
        completion: @escaping (Result<LoginItemState, Error>) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { setEnabled(enabled, completion: completion) }
            return
        }

        guard isAvailable else {
            generation += 1
            cachedState = .unavailable
            completeRefreshWaiters(with: .unavailable)
            completion(.failure(LoginItemError.unavailable))
            return
        }
        guard !updateInFlight else {
            completion(.failure(LoginItemError.updateInProgress))
            return
        }

        generation += 1
        let requestGeneration = generation
        updateInFlight = true
        let restorationState = authoritative(cachedState) ?? lastAuthoritativeState
        cachedState = .checking
        operations.enqueueMutation(
            operation: {
                let reply = send(
                    [
                        "op": "setLaunchAtLoginEnabled",
                        "enabled": enabled,
                    ],
                    timeoutSeconds: 15
                )
                let landedState = state(from: reply)
                let succeeded = HelperClient.strictJSONBool(reply?["ok"]) == true
                    && HelperClient.strictJSONBool(reply?["enabled"]) == enabled
                let helperUnavailable = reply?["error"] as? String == "rejected"
                if succeeded {
                    return SetResult(
                        state: landedState,
                        succeeded: true,
                        helperUnavailable: false,
                        requiresAuthoritativeReadback: false
                    )
                }

                // A valid but different `enabled` value is already an
                // authoritative readback. A timeout has consumed this logical
                // update's entire helper budget, so restore prior evidence and
                // schedule (rather than synchronously chaining) a fresh read.
                let recoveredState: LoginItemState
                if let authoritative = authoritative(landedState) {
                    recoveredState = authoritative
                } else {
                    recoveredState = helperUnavailable
                        ? .unavailable
                        : restorationState ?? landedState
                }
                return SetResult(
                    state: recoveredState,
                    succeeded: false,
                    helperUnavailable: helperUnavailable,
                    requiresAuthoritativeReadback:
                        authoritative(landedState) == nil && !helperUnavailable
                )
            },
            completion: { result in
                updateInFlight = false
                if requestGeneration == generation {
                    cachedState = result.state
                    rememberAuthoritative(result.state)
                    if !result.requiresAuthoritativeReadback {
                        completeRefreshWaiters(with: result.state)
                    }
                } else if !refreshWaiters.isEmpty {
                    // An availability transition can supersede a mutation
                    // while a recovered Settings caller is already waiting.
                    // The stale write result is not authoritative for that
                    // caller; start one fresh coalesced read now that the
                    // mutation lane is clear.
                    refresh()
                }
                if result.succeeded {
                    completion(.success(result.state))
                } else {
                    completion(.failure(
                        result.helperUnavailable
                            ? LoginItemError.unavailable
                            : LoginItemError.updateFailed
                    ))
                    // Complete the user's action before a potentially slow
                    // readback. `refresh` enters the coalesced read lane, so
                    // repeated opens retain only the latest request.
                    if requestGeneration == generation,
                       result.state != .unavailable {
                        refresh()
                    }
                }
            }
        )
    }

    private static func authoritative(_ state: LoginItemState) -> LoginItemState? {
        switch state {
        case .enabled, .notRegistered:
            return state
        case .checking, .unavailable, .readFailed:
            return nil
        }
    }

    private static func rememberAuthoritative(_ state: LoginItemState) {
        if let state = authoritative(state) { lastAuthoritativeState = state }
    }

    private static func completeRefreshWaiters(with state: LoginItemState) {
        precondition(Thread.isMainThread)
        let completed = refreshWaiters
        refreshWaiters.removeAll()
        completed.forEach { $0(state) }
    }

    private static func state(from reply: [String: Any]?) -> LoginItemState {
        guard let reply else { return .readFailed }
        guard HelperClient.strictJSONBool(reply["ok"]) == true,
              let enabled = HelperClient.strictJSONBool(reply["enabled"]) else {
            return reply["error"] as? String == "rejected" ? .unavailable : .readFailed
        }
        return enabled ? .enabled : .notRegistered
    }

#if DEBUG
    static func configureForTest(
        available: Bool,
        initialState: LoginItemState,
        send: @escaping ([String: Any], Int) -> [String: Any]?
    ) {
        precondition(Thread.isMainThread)
        operations.performMutation {}
        generation += 1
        testAvailability = available
        testSend = send
        cachedState = initialState
        lastAuthoritativeState = authoritative(initialState)
        updateInFlight = false
        refreshWaiters.removeAll()
    }

    static func setAvailabilityForTest(_ available: Bool) {
        precondition(Thread.isMainThread)
        testAvailability = available
    }

    static func resetTestConfiguration() {
        precondition(Thread.isMainThread)
        // The injected sender is read on the helper worker. Cross that same
        // serial lane before replacing it so teardown cannot race an in-flight
        // readback or leave one running in the following test.
        operations.performMutation {}
        generation += 1
        testAvailability = nil
        testSend = nil
        cachedState = canManageInstalledApp && HelperClient.isInstalled
            ? .checking
            : .unavailable
        lastAuthoritativeState = nil
        updateInFlight = false
        refreshWaiters.removeAll()
    }
#endif
}
