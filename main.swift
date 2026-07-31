import AppKit

// Swift only allows top-level statements in a file named main.swift. The app
// was a single translation unit before, so this lived at the bottom of
// BatteryPowerWidget.swift; multi-file compilation requires it to move here.

let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate

// The menu bar extra is the primary surface. The desktop panel is unchanged
// and still owned by AppController.
let statusItemController = StatusItemController()
statusItemController.start()

app.run()
