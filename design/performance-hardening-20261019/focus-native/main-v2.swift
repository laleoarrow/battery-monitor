import AppKit
import Darwin

// Diagnostic-only mocked process identities. The production handler is replaced;
// this probe never requests process termination or contacts the helper.
let suite = ProcessInfo.processInfo.environment["WATTSON_TEST_DEFAULTS_SUITE"]!
Settings.configureForTest(defaults: UserDefaults(suiteName: suite)!)
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.finishLaunching()
func spin() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
        app.stop(nil)
        if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                                         modifierFlags: [], timestamp: 0, windowNumber: 0,
                                         context: nil, subtype: 0, data1: 0, data2: 0) {
            app.postEvent(wake, atStart: false)
        }
    }
    app.run()
}
func process(_ pid: Int32, _ name: String, _ score: Double) -> EnergyProcess {
    var audit = audit_token_t()
    audit.val.1 = geteuid()
    audit.val.5 = UInt32(bitPattern: pid)
    let token = withUnsafeBytes(of: &audit) { Data($0) }
    return EnergyProcess(pid: pid, name: name, energyImpact: score, cpuPercent: score,
                         idleWakeupsPerSecond: 0,
                         terminationIdentity: ProcessIdentity(pid: pid, startedAt: UInt64(pid), auditToken: token))
}
let a = process(21001, "Fixture A", 84)
let b = process(21002, "Fixture B", 46)
let c = process(21003, "Fixture C", 8)
let initial: TopProcessesState = .ready([a, b, c])
let reranked: TopProcessesState = .ready([b, a, c])
let window = NSWindow(contentRect: NSRect(x: 80, y: 100, width: 380, height: 270),
                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.title = "Wattson isolated focus QA"
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
spin()
var checks: [String: Bool] = [:]
var details: [String: Any] = [:]
var qualified: [String] = []
func record(_ name: String, _ passed: Bool) { checks[name] = passed; print("\(passed ? "PASS" : "FAIL") \(name)") }
func fixture() -> TopProcessesView {
    window.makeFirstResponder(nil)
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 270))
    window.contentView = content
    let view = TopProcessesView()
    view.frame = NSRect(x: 20, y: 40, width: 328, height: TopProcessesView.preferredHeight(count: 3))
    content.addSubview(view)
    view.update(state: initial, count: 3)
    view.layoutSubtreeIfNeeded()
    view.setPresentationActive(true)
    spin()
    return view
}
func space(_ responder: NSResponder?) {
    guard let responder, let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, characters: " ",
        charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49) else { return }
    responder.keyDown(with: event)
}
func isProcessResponder(_ responder: NSResponder?, _ view: TopProcessesView) -> Bool {
    view.processRowsForTest.contains { $0 === responder }
        || view.forceQuitButtonsForTest.contains { $0 === responder }
}
record("keyWindowIsActualFixture", window.isKeyWindow)
record("fixtureIdentitiesValid", [a, b, c].allSatisfy { $0.terminationIdentity?.isValid == true })
do {
    let view = fixture()
    let row = view.processRowsForTest[0]
    record("rowSelectionViaAccessibilityPress", row.accessibilityPerformPress())
    record("rowFocusAccepted", window.makeFirstResponder(row) && window.firstResponder === row)
    view.update(state: reranked, count: 3)
    view.layoutSubtreeIfNeeded()
    record("selectionFollowsIdentityOnRerank", view.selectedProcessForTest?.terminationIdentity == a.terminationIdentity)
    record("rowFocusFollowsIdentityOnRerank", window.firstResponder === view.processRowsForTest[1])
    details["rerankActualFocusedRow"] = view.processRowsForTest.firstIndex { $0 === window.firstResponder } ?? -1
    space(window.firstResponder)
    record("spaceActsOnOriginalProcessAfterRerank", view.selectedProcessForTest == nil)
    details["selectedAfterSpace"] = view.selectedProcessForTest?.name ?? "none"
}
do {
    let view = fixture()
    _ = view.processRowsForTest[0].accessibilityPerformPress()
    let button = view.forceQuitButtonsForTest[0]
    if window.makeFirstResponder(button), window.firstResponder === button {
        record("buttonFocusAcceptedByAppKit", true)
        var requested: EnergyProcess?
        view.forceQuitHandler = { requested = $0 }
        view.update(state: reranked, count: 3)
        view.layoutSubtreeIfNeeded()
        record("buttonFocusFollowsIdentityOnRerank", window.firstResponder === view.forceQuitButtonsForTest[1])
        (window.firstResponder as? NSButton)?.performClick(nil)
        record("focusedButtonActsOnOriginalProcessAfterRerank", requested?.terminationIdentity == a.terminationIdentity)
    } else {
        qualified.append("Focused action-button path not exercised: AppKit rejected makeFirstResponder for the real native button in this environment.")
    }
}
for (name, target, count) in [
    ("removed", TopProcessesState.ready([b, c]), 3),
    ("belowTopN", TopProcessesState.ready([b, a, c]), 1),
    ("loading", TopProcessesState.loading, 3),
    ("unavailable", TopProcessesState.unavailable, 3),
    ("empty", TopProcessesState.ready([]), 3)
] {
    let view = fixture()
    let rows = view.processRowsForTest
    let buttons = view.forceQuitButtonsForTest
    _ = rows[0].accessibilityPerformPress()
    _ = window.makeFirstResponder(rows[0])
    view.update(state: target, count: count)
    view.layoutSubtreeIfNeeded()
    record("\(name)ClearsSelection", view.selectedProcessForTest == nil)
    record("\(name)RetiresProcessFocus", !rows.contains { $0 === window.firstResponder } && !buttons.contains { $0 === window.firstResponder })
}
do {
    let view = fixture()
    _ = view.processRowsForTest[0].accessibilityPerformPress()
    _ = window.makeFirstResponder(view.processRowsForTest[0])
    view.update(state: reranked, count: 3, compact: true)
    view.layoutSubtreeIfNeeded()
    record("compactSelectionFollowsIdentity", view.selectedProcessForTest?.terminationIdentity == a.terminationIdentity)
    record("compactFocusFollowsIdentity", window.firstResponder === view.processRowsForTest[1])
}
do {
    let view = fixture()
    _ = view.processRowsForTest[0].accessibilityPerformPress()
    let text = NSTextField(string: "Unrelated control")
    text.frame = NSRect(x: 20, y: 10, width: 280, height: 24)
    window.contentView!.addSubview(text)
    record("externalTextFocusAccepted", window.makeFirstResponder(text))
    let editor = window.firstResponder
    record("externalTextUsesFieldEditor", editor is NSTextView)
    view.update(state: reranked, count: 3)
    view.layoutSubtreeIfNeeded()
    record("rerankDoesNotStealExternalFocus", window.firstResponder === editor)
    view.update(state: .unavailable, count: 3)
    record("clearDoesNotStealExternalFocus", window.firstResponder === editor)
}
// v2 boundary cases: smaller Top N, cleared selection, and recycled identity.
do {
    let view = fixture()
    _ = view.processRowsForTest[0].accessibilityPerformPress()
    let button = view.forceQuitButtonsForTest[0]
    if window.makeFirstResponder(button), window.firstResponder === button {
        view.update(state: initial, count: 2)
        view.layoutSubtreeIfNeeded()
        record("reducedTopNClearsSelectionForRetainedIdentity", view.selectedProcessForTest == nil)
        record("reducedTopNFocusedActionFallsBackToSameIdentityRow", window.firstResponder === view.processRowsForTest[0])
    } else {
        qualified.append("Top N action fallback not exercised: AppKit rejected native button focus.")
    }
}
do {
    let view = fixture()
    _ = view.processRowsForTest[0].accessibilityPerformPress()
    _ = window.makeFirstResponder(view.processRowsForTest[0])
    let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false, keyCode: 53)!
    window.firstResponder?.keyDown(with: escape)
    record("escapeClearsSelectionButPreservesRowFocus", view.selectedProcessForTest == nil && window.firstResponder === view.processRowsForTest[0])
    view.update(state: reranked, count: 3)
    record("unselectedFocusedRowStillFollowsIdentity", view.selectedProcessForTest == nil && window.firstResponder === view.processRowsForTest[1])
}
let recycled = EnergyProcess(pid: a.pid, name: a.name, energyImpact: a.energyImpact,
    cpuPercent: a.cpuPercent, idleWakeupsPerSecond: a.idleWakeupsPerSecond,
    terminationIdentity: ProcessIdentity(pid: a.pid, startedAt: a.terminationIdentity!.startedAt + 1,
        auditToken: a.terminationIdentity!.auditToken))
let unreadableIdentity = EnergyProcess(pid: a.pid, name: a.name, energyImpact: a.energyImpact,
    cpuPercent: a.cpuPercent, idleWakeupsPerSecond: a.idleWakeupsPerSecond)
for (name, replacement) in [("recycledPID", recycled), ("identityUnavailable", unreadableIdentity)] {
    let view = fixture()
    let rows = view.processRowsForTest
    let buttons = view.forceQuitButtonsForTest
    _ = rows[0].accessibilityPerformPress()
    _ = window.makeFirstResponder(rows[0])
    view.update(state: .ready([replacement, b, c]), count: 3)
    record("\(name)ClearsOriginalSelection", view.selectedProcessForTest == nil)
    record("\(name)RetiresOriginalFocusSafely", !rows.contains { $0 === window.firstResponder } && !buttons.contains { $0 === window.firstResponder })
}
window.makeFirstResponder(nil)
window.orderOut(nil)
window.close()
let report: [String: Any] = ["schema": 2, "allPassed": checks.values.allSatisfy { $0 },
    "checks": checks, "details": details, "qualifiedUnexercisedPaths": qualified,
    "mockedTerminationHandlerOnly": true, "helperContacted": false,
    "keyboardDispatch": "keyDown on actual NSWindow.firstResponder; no system event injection",
    "buttonDispatch": "performClick on actual focused native NSButton; no termination"]
let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
print("FOCUS_PROBE_JSON " + String(data: data, encoding: .utf8)!)
