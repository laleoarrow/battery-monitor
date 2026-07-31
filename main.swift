import AppKit

// Swift only allows top-level statements in a file named main.swift. The app
// was a single translation unit before, so this lived at the bottom of
// BatteryPowerWidget.swift; multi-file compilation requires it to move here.

let app = NSApplication.shared

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
} else {
    let delegate = AppController()
    app.delegate = delegate
    let statusItemController = StatusItemController()
    statusItemController.start()
    app.run()
}
#else
let delegate = AppController()
app.delegate = delegate

// The menu bar extra is the primary surface. The desktop panel is unchanged
// and still owned by AppController.
let statusItemController = StatusItemController()
statusItemController.start()
app.run()
#endif
