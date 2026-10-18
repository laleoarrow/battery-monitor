import AppKit

// Type-only fixtures let the production presenter compile in a small native
// alert probe. All alert construction and routing comes from its real source.
struct ProcessIdentity: Equatable, Sendable { let pid: Int32; var isValid: Bool { true } }
struct EnergyProcess { let pid: Int32; let name: String; let terminationIdentity: ProcessIdentity? }
enum ProcessTerminationResult: Equatable, Sendable { case signalSent, alreadyExited, identityChanged, notPermitted, unavailable, failed }
enum Settings {
    struct ColorScheme { var appearance: NSAppearance? { NSAppearance(named: .darkAqua) } }
    static let colorScheme = ColorScheme()
}
enum HelperClient { static func forceQuitProcess(_ identity: ProcessIdentity) -> ProcessTerminationResult { fatalError("This probe must never call a helper") } }

@main
private enum Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = Probe()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

private final class Probe: NSObject, NSApplicationDelegate, @unchecked Sendable {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { self.run() }
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func run() {
        var results: [[String: Any]] = []
        for action in ["Cancel", "Escape", "Return", "Force Quit"] {
            var signals = 0
            var problems: [String] = []
            var returnStayedOpen = false
            var attempts = 0
            var dependencies = ProcessTerminationPresenter.Dependencies.live
            dependencies.terminate = { _, completion in signals += 1; completion(.signalSent) }
            dependencies.showFailure = { _, _ in problems.append("Unexpected failure") }
            let presenter = ProcessTerminationPresenter(dependencies: dependencies)
            let timer = Timer(timeInterval: 0.08, repeats: true) { timer in
                attempts += 1
                guard let modal = NSApp.modalWindow, let content = modal.contentView else {
                    if attempts > 30 { problems.append("No modal alert"); timer.invalidate(); NSApp.abortModal() }
                    return
                }
                let buttons = self.descendants(content).compactMap { $0 as? NSButton }
                guard let cancel = buttons.first(where: { $0.title == "Cancel" }), let force = buttons.first(where: { $0.title == "Force Quit" }) else { return }
                print("ALERT_PROBE action=\(action) cancelKey=\(String(reflecting: cancel.keyEquivalent)) defaultCell=\(modal.defaultButtonCell?.title ?? "nil")")
                timer.invalidate()
                if action == "Cancel" { cancel.performClick(nil); return }
                if action == "Force Quit" { force.performClick(nil); return }
                let fallback = Timer(timeInterval: 0.5, repeats: false) { _ in
                    if action == "Return" {
                        if NSApp.modalWindow === modal { returnStayedOpen = true; cancel.performClick(nil) }
                        else { problems.append("Return unexpectedly dismissed") }
                    } else if NSApp.modalWindow === modal { problems.append("\(action) did not dismiss"); NSApp.abortModal() }
                }
                RunLoop.main.add(fallback, forMode: .common)
                let text = action == "Escape" ? "\u{1b}" : "\r"
                let code: UInt16 = action == "Escape" ? 53 : 36
                guard let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: modal.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code) else { problems.append("No key event"); NSApp.abortModal(); return }
                NSApp.postEvent(key, atStart: true)
            }
            RunLoop.main.add(timer, forMode: .common)
            presenter.request(EnergyProcess(pid: 990_101, name: "Owned UI Fixture", terminationIdentity: ProcessIdentity(pid: 990_101)))
            timer.invalidate()
            let passed = problems.isEmpty && signals == (action == "Force Quit" ? 1 : 0) && !presenter.isBusy && (action != "Return" || returnStayedOpen)
            results.append(["action": action, "passed": passed, "signals": signals, "problems": problems])
        }
        let passed = results.allSatisfy { $0["passed"] as? Bool == true }
        let report: [String: Any] = ["allPassed": passed, "results": results]
        print(String(decoding: try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        fflush(stdout)
        exit(passed ? 0 : 1)
    }
}
