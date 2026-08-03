import AppKit
import Darwin

// Swift only allows top-level statements in a file named main.swift.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

#if DEBUG
if CommandLine.arguments.contains("--popover-preview") {
    let stateArgument = CommandLine.arguments.first { $0.hasPrefix("--preview-state=") }
    let state = stateArgument?.split(separator: "=", maxSplits: 1).last.map(String.init) ?? "idle"
    let appearanceArgument = CommandLine.arguments.first { $0.hasPrefix("--preview-appearance=") }
    let appearance = appearanceArgument?.split(separator: "=", maxSplits: 1).last.map(String.init)
    let previewController = PopoverPreviewWindowController(state: state, appearance: appearance)
    app.setActivationPolicy(.regular)
    previewController.showWindow(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
}
#endif

private func signalInstallerReadinessIfRequested() {
    let prefix = "--installer-ready-token="
    guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }),
          let token = UUID(uuidString: String(argument.dropFirst(prefix.count))),
          let account = getpwuid(getuid()),
          let home = account.pointee.pw_dir else { return }

    let supportURL = URL(fileURLWithPath: String(cString: home), isDirectory: true)
        .appendingPathComponent("Library/Application Support/Wattson", isDirectory: true)
    let readinessURL = supportURL
        .appendingPathComponent("installer-ready-\(token.uuidString).txt")
    do {
        try FileManager.default.createDirectory(
            at: supportURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try token.uuidString.write(to: readinessURL, atomically: true, encoding: .utf8)
        _ = chmod(readinessURL.path, 0o600)
    } catch {
        NSLog("Wattson could not signal installer readiness: %@", error.localizedDescription)
    }
}

let statusItemController = StatusItemController()
if statusItemController.start() {
    // The first main-queue turn proves AppKit actually entered its run loop;
    // writing synchronously before app.run() could acknowledge a process that
    // then dies during launch.
    DispatchQueue.main.async {
        signalInstallerReadinessIfRequested()
    }
}
app.run()
