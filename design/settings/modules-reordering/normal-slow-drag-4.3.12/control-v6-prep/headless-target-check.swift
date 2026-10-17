import AppKit
// Typechecks the exact archived helpers; does not invoke NSApplication or create a window.
final class ExactFixtureGeometryHelpers {
    func cgPoint(_ point: NSPoint, screen: NSScreen, displayBounds: CGRect) -> [CGFloat] {
        [displayBounds.minX + point.x - screen.frame.minX,
         displayBounds.minY + screen.frame.maxY - point.y]
    }
    func dropHitTest(_ screenPoint: NSPoint, geometryValid: Bool, window: NSWindow, stack: NSStackView,
                             screen: NSScreen, displayBounds: CGRect) -> [String: Any] {
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let stackPoint = stack.convert(windowPoint, from: nil)
        var ancestry: [[String: Any]] = []
        var containsExactStack = false
        var pointInContent: NSPoint?
        if let content = window.contentView {
            pointInContent = content.convert(windowPoint, from: nil)
            // NSView.hitTest takes a point in its superview's coordinate system.
            let hitPoint = content.superview?.convert(windowPoint, from: nil) ?? windowPoint
            var current = content.hitTest(hitPoint)
            while let view = current {
                let isStack = view === stack
                containsExactStack = containsExactStack || isStack
                ancestry.append(["class": String(describing: type(of: view)), "id": view.identifier?.rawValue ?? "",
                    "objectIdentity": String(describing: ObjectIdentifier(view)), "isExactStack": isStack,
                    "registeredDraggedTypes": view.registeredDraggedTypes.map(\.rawValue)])
                current = view.superview
            }
        }
        let cg = cgPoint(screenPoint, screen: screen, displayBounds: displayBounds)
        var result: [String: Any] = ["passedBool": geometryValid && containsExactStack,
            "containsExactStack": containsExactStack, "candidateGeometryValid": geometryValid,
            "candidateCGPoint": ["x": cg[0], "y": cg[1]],
            "candidateAppKitScreen": [screenPoint.x, screenPoint.y],
            "pointInWindow": [windowPoint.x, windowPoint.y], "pointInStack": [stackPoint.x, stackPoint.y],
            "ancestry": ancestry, "stackIdentity": String(describing: ObjectIdentifier(stack)),
            "registeredTargetAncestors": ancestry.filter { ($0["registeredDraggedTypes"] as? [String])?.isEmpty == false },
            "inputGeneratedByFixture": false, "nativeHitTestOnly": true]
        if let pointInContent { result["pointInContent"] = [pointInContent.x, pointInContent.y] }
        return result
    }
}

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


let stack = rows
// The bare hierarchy has no window clipping. Use the actual NSBox content bounds
// as an explicit geometry proxy; the real guest preflight must still prove visibleRect.
                let visibleRect = stack.convert(box.contentView!.bounds, from: box.contentView!)
                let effectiveVisibleRect = visibleRect.intersection(stack.bounds)
                let lastRowFrame = stack.arrangedSubviews.last.map { stack.convert($0.bounds, from: $0) } ?? .zero
                // Keep the release inside the visible list and below the last row's center.
                // The outer NSBox clips a border band from the stack's bounds.
                let dropInStack = NSPoint(x: effectiveVisibleRect.midX, y: effectiveVisibleRect.minY + 12)
                let finiteRect: (NSRect) -> Bool = { rect in
                    [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && !rect.isEmpty
                }
                let dropGeometryValid = finiteRect(visibleRect) && finiteRect(effectiveVisibleRect) && finiteRect(lastRowFrame)
                    && dropInStack.x.isFinite && dropInStack.y.isFinite
                    && effectiveVisibleRect.width > 24 && effectiveVisibleRect.height > 24
                    && effectiveVisibleRect.contains(dropInStack) && stack.bounds.contains(dropInStack)
                    && lastRowFrame.contains(dropInStack) && dropInStack.y < lastRowFrame.midY
                let safeDropInStack = dropGeometryValid ? dropInStack : NSPoint(x: stack.bounds.midX, y: stack.bounds.minY)

func containsStack(_ hit: NSView?) -> Bool {
    var cursor = hit
    while let view = cursor { if view === rows { return true }; cursor = view.superview }
    return false
}
let oldBoxPoint = rows.convert(NSPoint(x: rows.bounds.midX, y: rows.bounds.minY + 3), to: box)
let newBoxPoint = rows.convert(safeDropInStack, to: box)
let oldContains = containsStack(box.hitTest(oldBoxPoint))
let newContains = containsStack(box.hitTest(newBoxPoint))
let passed = dropGeometryValid && !oldContains && newContains && abs(safeDropInStack.y - 18) < 0.001
let output: [String: Any] = ["passed": passed, "oldTargetExactStack": oldContains,
    "newTargetExactStack": newContains, "candidateGeometryValid": dropGeometryValid,
    "candidateInStack": [safeDropInStack.x,safeDropInStack.y],
    "effectiveVisibleRectProxy": [effectiveVisibleRect.minX,effectiveVisibleRect.minY,effectiveVisibleRect.width,effectiveVisibleRect.height],
    "lastRowFrame": [lastRowFrame.minX,lastRowFrame.minY,lastRowFrame.width,lastRowFrame.height],
    "inputGenerated": false, "windowCreated": false, "actualWindowVisibleRectProof": false,
    "productAcceptance": false, "scope": "Native headless NSBox clipping reproduction, exact fixture geometry/helper typecheck; guest runtime gate remains required"]
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output,options:[.prettyPrinted,.sortedKeys]))
FileHandle.standardOutput.write(Data([10]))
exit(passed ? 0 : 1)
