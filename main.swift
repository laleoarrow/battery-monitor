import AppKit
import Darwin

// Swift only allows top-level statements in a file named main.swift.

if CommandLine.arguments.contains("--helper-health-probe") {
    exit(HelperClient.isHealthy() ? 0 : 1)
}
if CommandLine.arguments.contains("--helper-power-probe") {
    guard let power = HelperClient.livePower() else { exit(1) }
    let adapter = power.adapterW.map { String(format: "%.3f", $0) } ?? "unavailable"
    let system = power.systemW.map { String(format: "%.3f", $0) } ?? "unavailable"
    print("adapterW=\(adapter) systemW=\(system)")
    exit(0)
}

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

let statusItemController = StatusItemController()
_ = statusItemController.start()
app.run()
