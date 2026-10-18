import AppKit

/// Keeps a confirmed process identity independent of the live, reordering list.
final class ProcessTerminationPresenter {
    struct Dependencies {
        var confirm: (EnergyProcess, @escaping (Bool) -> Void) -> Void
        var terminate: (ProcessIdentity, @escaping (ProcessTerminationResult) -> Void) -> Void
        var showFailure: (EnergyProcess, ProcessTerminationResult) -> Void

        static var live: Dependencies {
            Dependencies(
                confirm: { process, completion in
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Force quit “\(process.name)”?"
                    alert.informativeText = "Any unsaved work in this process may be lost."
                    alert.addButton(withTitle: "Cancel")
                    let forceQuit = alert.addButton(withTitle: "Force Quit")
                    forceQuit.hasDestructiveAction = true
                    forceQuit.keyEquivalent = ""
                    // Preserve Escape for Cancel and require an explicit
                    // destructive choice instead of a Return default.
                    alert.window.defaultButtonCell = nil
                    alert.window.appearance = Settings.colorScheme.appearance
                    NSApp.activate(ignoringOtherApps: true)
                    completion(alert.runModal() == .alertSecondButtonReturn)
                },
                terminate: { identity, completion in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = HelperClient.forceQuitProcess(identity)
                        DispatchQueue.main.async { completion(result) }
                    }
                },
                showFailure: { process, result in
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Couldn’t Force Quit “\(process.name)”"
                    alert.informativeText = failureMessage(for: result)
                    alert.addButton(withTitle: "OK")
                    alert.window.appearance = Settings.colorScheme.appearance
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            )
        }
    }

    private enum Phase { case idle, confirming, terminating }
    private let dependencies: Dependencies
    private var phase: Phase = .idle
    private var generation: UInt = 0

    var isBusy: Bool { phase != .idle }

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    func request(_ process: EnergyProcess) {
        guard !isBusy, let identity = process.terminationIdentity,
              identity.isValid, identity.pid == process.pid else { return }
        generation &+= 1
        let requestGeneration = generation
        phase = .confirming
        dependencies.confirm(process) { [weak self] confirmed in
            guard let self, self.generation == requestGeneration,
                  self.phase == .confirming else { return }
            guard confirmed else {
                self.phase = .idle
                return
            }
            self.phase = .terminating
            self.dependencies.terminate(identity) { [weak self] result in
                guard let self, self.generation == requestGeneration,
                      self.phase == .terminating else { return }
                // Keep the action busy while a failure dialog is running.
                defer { self.phase = .idle }
                switch result {
                case .signalSent, .alreadyExited: break
                case .identityChanged, .notPermitted, .unavailable, .failed:
                    self.dependencies.showFailure(process, result)
                }
            }
        }
    }

    static func failureMessage(for result: ProcessTerminationResult) -> String {
        switch result {
        case .identityChanged:
            return "This process has changed since it was measured. Open Process Activity and select it again."
        case .notPermitted:
            return "macOS did not allow Wattson to end this process. Only processes owned by your current user can be ended."
        case .unavailable:
            return "Force Quit is unavailable on this Mac or the Wattson helper needs updating. You can use Activity Monitor instead."
        case .failed:
            return "The process could not be ended. Try again or use Activity Monitor."
        case .signalSent, .alreadyExited:
            return ""
        }
    }
}
