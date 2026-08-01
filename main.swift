import AppKit

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

let statusItemController = StatusItemController()
statusItemController.start()
app.run()
