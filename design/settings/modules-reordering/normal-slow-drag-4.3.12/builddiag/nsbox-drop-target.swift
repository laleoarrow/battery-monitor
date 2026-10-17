import AppKit

// Headless reproduction of the production Modules container hierarchy.
// This creates no application, window, input event, app registration, or preferences.
let box = NSBox(frame: NSRect(x: 0, y: 0, width: 503, height: 360))
box.boxType = .custom
box.titlePosition = .noTitle
box.cornerRadius = 14
box.borderWidth = 1
let rows = NSStackView()
rows.identifier = NSUserInterfaceItemIdentifier("diagnostic.modules.rows")
rows.orientation = .vertical
rows.alignment = .width
rows.distribution = .fillEqually
rows.spacing = 0
rows.wantsLayer = true
rows.translatesAutoresizingMaskIntoConstraints = false
rows.registerForDraggedTypes([NSPasteboard.PasteboardType("com.leoarrow.wattson.module-order")])
for _ in 0..<5 {
    let row = NSView()
    row.wantsLayer = true
    rows.addArrangedSubview(row)
    row.heightAnchor.constraint(equalToConstant: 72).isActive = true
}
box.addSubview(rows)
NSLayoutConstraint.activate([
    rows.leadingAnchor.constraint(equalTo: box.leadingAnchor),
    rows.trailingAnchor.constraint(equalTo: box.trailingAnchor),
    rows.topAnchor.constraint(equalTo: box.topAnchor),
    rows.bottomAnchor.constraint(equalTo: box.bottomAnchor),
])
box.layoutSubtreeIfNeeded()

func rect(_ value: NSRect) -> [Double] {
    [value.minX, value.minY, value.width, value.height].map(Double.init)
}
func ancestry(_ view: NSView?) -> [String] {
    var cursor = view
    var values: [String] = []
    while let current = cursor {
        values.append(String(describing: type(of: current)))
        cursor = current.superview
    }
    return values
}
let points = [3.0, 6.0, 6.5, 7.0, 18.0, 24.0, 35.0].map { y -> [String: Any] in
    // box.superview == nil and box.frame origin == 0, so this is its
    // superview-coordinate point, as required by NSView.hitTest(_:).
    let point = NSPoint(x: 251.5, y: y)
    let hit = box.hitTest(point)
    let chain = ancestry(hit)
    return ["pointInOuterBox": [point.x, point.y],
            "insideStackBounds": rows.bounds.contains(rows.convert(point, from: box)),
            "hitClass": hit.map { String(describing: type(of: $0)) } ?? "nil",
            "hitAncestors": chain,
            "hitAncestryContainsExactStack": {
                var cursor = hit
                while let view = cursor {
                    if view === rows { return true }
                    cursor = view.superview
                }
                return false
            }()]
}
let output: [String: Any] = [
    "scope": "Headless AppKit NSBox hierarchy/hit testing; not a native drag or product acceptance",
    "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
    "boxFrame": rect(box.frame),
    "contentViewMargins": [box.contentViewMargins.width, box.contentViewMargins.height],
    "contentViewFrame": box.contentView.map { rect($0.frame) } ?? [],
    "rowsFrameInImmediateSuperview": rect(rows.frame),
    "rowsBounds": rect(rows.bounds),
    "rowFramesInStack": rows.arrangedSubviews.map { rect($0.frame) },
    "rowsSuperviewIsBoxContentView": rows.superview === box.contentView,
    "points": points,
    "conclusion": "The fixture's outer-stack minY+3 target is outside the NSBox contentView hit region even though stack.bounds contains it. minY+18 and minY+24 hit within the stack.",
    "sourceLines": ["MenuBar/SettingsWindowController.swift:3279-3317", ".build/normal-slow-drag.noindex/fixture/modules-normal-slow-drag.swift:281-283"],
    "hitTestCoordinateDocumentation": "https://developer.apple.com/documentation/appkit/nsview/hittest(_:)",
]
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
guard points[0]["hitAncestryContainsExactStack"] as? Bool == false,
      points[4]["hitAncestryContainsExactStack"] as? Bool == true,
      points[5]["hitAncestryContainsExactStack"] as? Bool == true else { exit(1) }
