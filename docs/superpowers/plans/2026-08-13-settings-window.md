# Wattson Settings Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native, single-instance C+E Settings window for Wattson's seven existing settings while preserving the current popover, helper semantics, and menu-bar behavior.

**Architecture:** Keep `StatusItemController` as the UI lifetime root. Move app-owned module preferences into the existing `Settings` store, make system-battery-icon state observable from one controller, and compose a pure-AppKit Settings window with a fixed sidebar and registered page controllers. General uses compact native rows; Modules uses the approved 2×2 visual-card layout. The existing quick menu and the new window call the same state APIs; no new polling or timers are introduced.

**Tech Stack:** Swift 5 language mode, AppKit, Foundation `UserDefaults` and notifications, SwiftPM, XCTest, Python `unittest` executable contract harnesses, existing privileged-helper clients.

## Global Constraints

- Target macOS 12 and newer on arm64 and x86_64.
- Keep `LSUIElement=true`; do not add a Dock icon or change activation policy.
- Preserve the current popover layout and every existing quick control.
- Add only General and Modules settings that already exist today.
- Implement the approved `docs/superpowers/specs/assets/wattson-settings-c-plus-e.png` direction: 720×520 content, 176-point sidebar, General list page, Modules 2×2 card page.
- Keep Auto/Low/High out of Settings.
- Keep existing UserDefaults keys and default values unchanged.
- Treat launchd and Control Center as authoritative; do not mirror them into UserDefaults.
- Add no timer, display link, sampling loop, or hidden rendering.
- Use TDD: every production behavior is preceded by a test that fails for the expected reason.
- Do not connect to the installed helper or mutate real user preferences from tests.
- Run at least three independent read-only `review-agent` reviews after implementation.

---

## File Structure

- `Core/Settings.swift`: typed app-owned preferences and effective-change notifications.
- `Core/SystemBatteryIcon.swift`: one cached authoritative battery-icon state and change notification, retaining the shared helper worker.
- `MenuBar/SettingsWindowController.swift`: window lifecycle, section registry, General section, and Modules section.
- `Popover/PopoverContentView.swift`: existing quick menu writes through `Settings`; live module reload; Settings menu callback.
- `Popover/PopoverController.swift`: dismiss-before-present Settings callback relay.
- `MenuBar/StatusItemController.swift`: owns the one Settings controller and installs the minimal application menu/Command-Comma route.
- `MenuBar/AppDelegate.swift`: update the now-stale no-window documentation only if needed; no lifecycle ownership change.
- `SwiftTests/WattsonTests.swift`: executable state, window, synchronization, lifecycle, and concurrency tests.
- `tests/test_settings_store_contract.py`: executable isolated UserDefaults contract.
- `tests/test_system_battery_state_contract.py`: executable isolated system-icon state contract.
- `tests/test_settings_window_contract.py`: compiled AppKit window/section contract.
- `tests/test_settings_integration_contract.py`: source-wiring and menu-command contract.
- `tests/interaction/main.swift`: real AppKit open/close/reopen and popover-dismiss behavior.

---

### Task 1: Centralize App-Owned Settings

**Files:**
- Modify: `Core/Settings.swift`
- Create: `tests/test_settings_store_contract.py`
- Test: `SwiftTests/WattsonTests.swift`

**Interfaces:**
- Produces: `Settings.Module: String, CaseIterable`, with `.flow`, `.ring`, `.lanes`, `.history`, `title`, and `defaultsKey`.
- Produces: `Settings.isModuleVisible(_:) -> Bool`.
- Produces: `Settings.setModule(_:visible:)`.
- Produces: `Settings.Change`, `Settings.changeUserInfoKey`, and existing `Settings.didChange`.
- Preserves: `Settings.showsMenuBarPercentage: Bool` and key `menubar.showsPercentage`.

- [ ] **Step 1: Write the isolated failing executable test**

Create a temporary Swift harness in `tests/test_settings_store_contract.py` that compiles `Core/Settings.swift`, configures a unique `UserDefaults` suite in DEBUG, and asserts:

```swift
let suite = "Wattson.Settings.Tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defaults.removePersistentDomain(forName: suite)
Settings.configureForTest(defaults: defaults)
defer { Settings.resetTestConfiguration() }

require(Settings.showsMenuBarPercentage, "percentage default")
require(Settings.Module.allCases.map(\.rawValue) == ["flow", "ring", "lanes", "history"], "module order")
for module in Settings.Module.allCases {
    require(Settings.isModuleVisible(module), "module default")
}

var changes: [Settings.Change] = []
let token = NotificationCenter.default.addObserver(
    forName: Settings.didChange, object: nil, queue: nil
) { note in
    if let change = note.userInfo?[Settings.changeUserInfoKey] as? Settings.Change {
        changes.append(change)
    }
}
Settings.setModule(.flow, visible: false)
Settings.setModule(.flow, visible: false)
require(changes == [.module(.flow)], "effective module change only")
```

- [ ] **Step 2: Run the focused test and witness RED**

Run: `python3 -m unittest tests.test_settings_store_contract -v`

Expected: compilation fails because `Settings.Module`, module accessors, and test configuration do not exist.

- [ ] **Step 3: Implement the minimal typed store**

Keep the current notification name and keys. Add the exact typed API above. Register all defaults on the active `UserDefaults`. Before each write, compare the current effective value and return without writing or posting if it is unchanged. Post:

```swift
NotificationCenter.default.post(
    name: didChange,
    object: nil,
    userInfo: [changeUserInfoKey: Change.module(module)]
)
```

Use the same effective-change rule for `.menuBarPercentage`. Keep the injected suite behind `#if DEBUG`; production always resolves to `.standard`.

- [ ] **Step 4: Run focused GREEN and package build**

Run:

```bash
python3 -m unittest tests.test_settings_store_contract -v
swift build
git diff --check -- Core/Settings.swift tests/test_settings_store_contract.py
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit the independently reviewable task**

```bash
git add Core/Settings.swift tests/test_settings_store_contract.py
git commit -m "feat: centralize app settings state"
```

---

### Task 2: Make System Battery Icon State Observable

**Files:**
- Modify: `Core/SystemBatteryIcon.swift`
- Create: `tests/test_system_battery_state_contract.py`
- Test: `SwiftTests/WattsonTests.swift`

**Interfaces:**
- Produces: `SystemBatteryIconController.didChange`.
- Produces: `SystemBatteryIconController.cachedHidden: Bool?` as a read-only state.
- Preserves: `refreshHidden(_ completion: @escaping (Bool?) -> Void)`.
- Preserves: `setHidden(_:completion: @escaping (Bool) -> Void)`.
- Uses: existing `CoalescingReadOperationQueue` and `HelperSettingsOperationWorker.shared`.

- [ ] **Step 1: Write a failing isolated state-machine test**

Build the production controller with an injected DEBUG sender and assert real asynchronous behavior:

```swift
SystemBatteryIconController.configureForTest { request, _ in
    switch request["op"] as? String {
    case "getSystemBatteryIconHidden": return ["ok": true, "hidden": authoritative]
    case "setSystemBatteryIconHidden":
        authoritative = request["hidden"] as! Bool
        return ["ok": true, "hidden": authoritative]
    default: return nil
    }
}

SystemBatteryIconController.refreshHidden { hidden in
    require(hidden == false, "initial authority")
}
SystemBatteryIconController.setHidden(true) { succeeded in
    require(succeeded, "mutation readback")
    require(SystemBatteryIconController.cachedHidden == true, "shared cache")
}
```

Count notifications and additionally assert: false-to-false posts none; false-to-true posts once; a failed write preserves true and posts none; unknown refresh produces `nil`, never `false`.

- [ ] **Step 2: Run and witness RED**

Run: `python3 -m unittest tests.test_system_battery_state_contract -v`

Expected: compilation fails because the observable cache and DEBUG sender do not exist.

- [ ] **Step 3: Implement authoritative cache and readback**

Add one main-thread `publish(_ hidden: Bool?)` helper:

```swift
private static func publish(_ hidden: Bool?) {
    precondition(Thread.isMainThread)
    guard cachedHidden != hidden else { return }
    cachedHidden = hidden
    NotificationCenter.default.post(name: didChange, object: nil)
}
```

`refreshHidden` reads on the existing coalesced lane, then publishes and completes on main. `setHidden` remains one mutation operation: send the fixed setter, then send the fixed getter for authoritative readback. It succeeds only when readback equals the requested value. Failed mutations leave the last cache unchanged. Add DEBUG configure/reset barriers on the same worker so injected closures cannot race teardown.

- [ ] **Step 4: Run GREEN and concurrency-focused verification**

Run:

```bash
python3 -m unittest tests.test_system_battery_state_contract -v
swift test --filter WattsonTests.testIndependentControllersShareOneHelperSettingsWorker
swift build
git diff --check -- Core/SystemBatteryIcon.swift tests/test_system_battery_state_contract.py
```

Expected: all commands exit 0, no real helper call occurs.

- [ ] **Step 5: Commit**

```bash
git add Core/SystemBatteryIcon.swift tests/test_system_battery_state_contract.py
git commit -m "feat: share system battery icon state"
```

---

### Task 3: Build the AppKit Settings Window and Sections

**Files:**
- Create: `MenuBar/SettingsWindowController.swift`
- Create: `tests/test_settings_window_contract.py`
- Test: `SwiftTests/WattsonTests.swift`

**Interfaces:**
- Produces protocol:

```swift
protocol SettingsSectionController: AnyObject {
    var identifier: String { get }
    var title: String { get }
    var symbolName: String { get }
    var view: NSView { get }
    func refresh()
}
```

- Produces: `SettingsWindowDependencies.live` with injected closures for login-item and battery-icon state/read/write.
- Produces: `SettingsWindowController.init(sections:dependencies:)` and `show(activateApp: Bool = true)`.
- Consumes: `Settings.Module`, module APIs, `LoginItemState`, `LoginItemController`, `SystemBatteryIconController`.

- [ ] **Step 1: Write the failing compiled-window contract**

Create a temporary Swift executable that constructs the controller under `NSApplication.shared` and asserts:

```swift
let controller = SettingsWindowController(
    sections: SettingsWindowController.defaultSections(dependencies: .fixture)
)
controller.show(activateApp: false)
let first = controller.windowForTest
require(first?.isVisible == true, "visible")
require(first?.isReleasedWhenClosed == false, "retained")
require(first?.isRestorable == false, "not visibility-restored")
require(first?.styleMask.contains(.miniaturizable) == false, "no minimize")
require(first?.styleMask.contains(.resizable) == false, "no zoom/resize")
first?.close()
controller.show(activateApp: false)
require(first === controller.windowForTest, "single instance")
require(controller.sectionIdentifiersForTest == ["general", "modules"], "section order")
require(first?.contentView?.frame.size == NSSize(width: 720, height: 520), "approved content size")
require(controller.selectedSectionIdentifierForTest == "general", "general initially selected")
controller.selectSectionForTest(identifier: "modules")
require(controller.selectedSectionIdentifierForTest == "modules", "modules selectable")
require(controller.visibleSectionIdentifierForTest == "modules", "single content host swaps page")
```

The fixture closures return deterministic states and do not invoke the helper.

- [ ] **Step 2: Run and witness RED**

Run: `python3 -m unittest tests.test_settings_window_contract -v`

Expected: compile fails because `SettingsWindowController` is absent.

- [ ] **Step 3: Implement the smallest native window shell**

Create one standard titled/closable `NSWindow`, fixed 720×520 content size, `isReleasedWhenClosed = false`, `isRestorable = false`, and one autosave name. Build a fixed 176-point sidebar with Wattson identity plus one row per registered section, and one content host with 32-point insets. General is selected initially; close/reopen keeps the in-process selection. Call `center()` only when no saved frame exists. `show` refreshes authoritative state, demniaturizes if needed, orders front, and activates only when requested. It creates no timers or observers outside section lifetimes.

- [ ] **Step 4: Implement General with explicit async state rendering**

Use one compact inset list containing exactly three icon/label/detail/switch rows. Use native switch-style checkboxes plus secondary labels. Map `LoginItemState` exactly:

```swift
switch state {
case .enabled: checked = true; enabled = true
case .notRegistered: checked = false; enabled = true
case .checking: checked = nil; enabled = false; detail = "Checking…"
case .unavailable: checked = nil; enabled = false; detail = "Full installer required"
case .readFailed: checked = nil; enabled = false; detail = "Status unavailable"
}
```

Map battery icon `Bool?` with `.mixed` for nil. Disable each row during its own mutation. On failure restore the last authoritative state and show one inline error; never use a modal alert from the Settings section. Capture views/controllers weakly in asynchronous completions.

- [ ] **Step 5: Implement Modules through the shared store**

Create exactly four compact visual cards from `Settings.Module.allCases`, arranged in a 2×2 grid. Each card has a static code-native preview glyph, title, one-line description, and switch. Reads call `Settings.isModuleVisible`, writes call `Settings.setModule`. Observe `Settings.didChange` weakly and refresh the checkbox states. Remove the observer in `deinit`. Preview glyphs must not animate, sample, or render live data.

- [ ] **Step 6: Run focused GREEN and leak-sensitive loop**

Run:

```bash
python3 -m unittest tests.test_settings_window_contract -v
swift build
git diff --check -- MenuBar/SettingsWindowController.swift tests/test_settings_window_contract.py
```

The executable harness must also switch General↔Modules at least 1,000 times without growing section/view counts, then create/show/close/release 500 controllers and assert weak controller/window references clear and `/dev/fd` returns to baseline.

- [ ] **Step 7: Commit**

```bash
git add MenuBar/SettingsWindowController.swift tests/test_settings_window_contract.py
git commit -m "feat: add native settings window"
```

---

### Task 4: Synchronize the Existing Quick Menu and Popover

**Files:**
- Modify: `Popover/PopoverContentView.swift`
- Modify: `Popover/PopoverController.swift`
- Create: `tests/test_settings_integration_contract.py`
- Test: `SwiftTests/WattsonTests.swift`

**Interfaces:**
- Consumes: Task 1 `Settings.Module` and app-owned accessors.
- Produces: `PopoverContentViewController.setSettingsHandler(_:)`.
- Produces: `PopoverController.setSettingsHandler(_:)` and `closeBeforePresentingSettings()` behavior.

- [ ] **Step 1: Write failing synchronization tests**

Add executable Swift tests that load a popover content controller, write a module through `Settings`, drain the main run loop, and assert the module is hidden and preferred height changes. Write the opposite direction through the existing quick-menu action and assert `Settings.isModuleVisible` changes.

Add source contract assertions that the Settings menu item calls a callback and that the callback is relayed through `PopoverController` only after `close()`.

- [ ] **Step 2: Run and witness RED**

Run:

```bash
python3 -m unittest tests.test_settings_integration_contract -v
swift test --filter WattsonTests.testSettingsModuleChangeUpdatesLivePopover
```

Expected: source/wiring assertion or Swift compilation fails because no Settings presentation handler exists and module visibility still has a private source of truth.

- [ ] **Step 3: Replace module source of truth without changing layout**

Replace `PopoverModule` with `typealias PopoverModule = Settings.Module` if compatibility helps keep call sites small. Load visibility through `Settings`, observe `Settings.didChange`, and reuse the existing `applyModuleVisibility()` method. Quick-menu actions call the typed setter. Preserve all module ordering, titles, animations, height behavior, and the ability to hide every module.

- [ ] **Step 4: Add Settings to the existing quick menu**

Insert `Settings…` above version/quit. The footer button still opens the same quick menu. The new item invokes the content callback once.

- [ ] **Step 5: Relay dismiss-before-present**

Add the callback relay through `PopoverController`. Its handler must set `wantsOpen = false`, stop the outside monitor, call `performClose`, and then invoke the Settings presenter on the next main-queue turn so the delegate teardown owns the old popover.

- [ ] **Step 6: Run focused GREEN**

Run:

```bash
python3 -m unittest tests.test_settings_integration_contract tests.test_popover_controls_contract tests.test_popover_modules_contract -v
swift test --filter WattsonTests.testSettingsModuleChangeUpdatesLivePopover
git diff --check -- Popover/PopoverContentView.swift Popover/PopoverController.swift tests/test_settings_integration_contract.py SwiftTests/WattsonTests.swift
```

- [ ] **Step 7: Commit**

```bash
git add Popover/PopoverContentView.swift Popover/PopoverController.swift tests/test_settings_integration_contract.py SwiftTests/WattsonTests.swift
git commit -m "feat: connect popover to settings"
```

---

### Task 5: Own the Window and Install Standard Commands

**Files:**
- Modify: `MenuBar/StatusItemController.swift`
- Modify: `MenuBar/AppDelegate.swift`
- Modify: `tests/test_statusitem_contract.py`
- Modify: `tests/interaction/main.swift`
- Test: `SwiftTests/WattsonTests.swift`

**Interfaces:**
- Consumes: `SettingsWindowController.show(activateApp:)`.
- Consumes: `PopoverController.setSettingsHandler(_:)`.
- Produces: one `@objc private func showSettings()` target used by quick menu and Command-Comma.

- [ ] **Step 1: Write failing ownership and command tests**

Assert StatusItem owns one lazy Settings controller, wires the popover presenter once, and installs an `NSMenuItem` titled `Settings…` with key equivalent `,` and `.command` modifier. In the real interaction harness, open the popover, invoke Settings twice, close and reopen, and assert one identical window, visible/key state, and closed popover.

- [ ] **Step 2: Run and witness RED**

Run:

```bash
python3 -m unittest tests.test_statusitem_contract -v
swift test --filter WattsonTests.testSettingsWindowIsSingleInstance
```

Expected: assertions fail because ownership and application menu are not wired.

- [ ] **Step 3: Wire one lifetime root and menu**

Add one lazy `SettingsWindowController` to `StatusItemController`, configure the popover callback in `start()`, and install a minimal main menu once. The application menu includes `Settings…` and `Quit Wattson`; it does not change activation policy. Both Settings routes call the same target.

- [ ] **Step 4: Synchronize system battery state consumers**

Replace StatusItem's independent system-icon cache flow with the shared `SystemBatteryIconController.cachedHidden` and `didChange` notification. Keep the existing generation guard only if it still protects an actual independent request; remove newly orphaned state created by this change. Popover and Settings must render one shared authoritative result.

- [ ] **Step 5: Run focused unit and real AppKit GREEN**

Run:

```bash
python3 -m unittest tests.test_statusitem_contract tests.test_settings_integration_contract -v
swift test
WATTSON_FORCE_REDUCE_MOTION=0 scripts/verify_interaction.sh
WATTSON_FORCE_LEGACY_KNOB=1 WATTSON_FORCE_REDUCE_MOTION=1 WATTSON_FORCE_REDUCE_TRANSPARENCY=1 scripts/verify_interaction.sh
```

Expected: all exit 0 and both interaction runs print `ALL_INTERACTION_CHECKS_PASSED`.

- [ ] **Step 6: Commit**

```bash
git add MenuBar/StatusItemController.swift MenuBar/AppDelegate.swift tests/test_statusitem_contract.py tests/interaction/main.swift SwiftTests/WattsonTests.swift
git commit -m "feat: expose standard settings commands"
```

---

### Task 6: Full Robustness and Performance Gate

**Files:**
- Modify only tests or production code required by a reproduced failure.

**Interfaces:**
- Verifies all prior tasks; produces no new feature API.

- [ ] **Step 1: Run all functional suites**

```bash
swift test
python3 -m unittest discover -s tests -p 'test_*.py' -q
```

Expected: 0 failures; only documented opt-in GUI skips are allowed.

- [ ] **Step 2: Run sanitizers in independent scratch directories**

```bash
swift test --scratch-path /tmp/wattson-settings-asan --sanitize=address
swift test --scratch-path /tmp/wattson-settings-tsan --sanitize=thread
swift test --scratch-path /tmp/wattson-settings-ubsan --sanitize=undefined
```

Expected: every suite exits 0 with no sanitizer diagnostic.

- [ ] **Step 3: Build both deployment slices**

```bash
swift build -c release --scratch-path /tmp/wattson-settings-arm64 --triple arm64-apple-macosx12.0
swift build -c release --scratch-path /tmp/wattson-settings-x86 --triple x86_64-apple-macosx12.0
```

Expected: both App and helper products link successfully.

- [ ] **Step 4: Measure hidden and churn performance**

Run the Settings harness for at least 1,000 show/close cycles and assert:

- one window identity per controller;
- weak release after controller teardown;
- stable FD count;
- RSS reaches a plateau rather than linear growth;
- no `Timer`, `CVDisplayLink`, or display sampler is created;
- closed-popover render count does not advance due to Settings.

- [ ] **Step 5: Run real bundle verification**

Use the existing project bundle build/preview workflow rather than launching the raw SwiftPM GUI executable. Verify Settings opens, becomes key, Command-Comma reuses it, closing/reopening works, and `LSUIElement` remains true.

- [ ] **Step 6: Diff hygiene**

```bash
git diff --check
git status --short
```

Confirm no generated bundle, temporary socket, test preference domain, or unrelated user file is staged.

---

### Task 7: Three Independent Defect-First Reviews

**Files:**
- Modify only files implicated by a reproduced review finding.

**Interfaces:**
- Review target: complete uncommitted/branch diff from the pre-feature base through current HEAD.
- Review standard: `/Users/leoarrow/.cc-switch/skills/.system/review-agent/SKILL.md`.

- [ ] **Step 1: Dispatch three fresh read-only reviewers**

Reviewer A: state consistency, helper-backed async failure recovery, stale completions, and concurrency.
Reviewer B: AppKit lifecycle, menu commands, accessibility, hidden work, retain cycles, FDs, and performance.
Reviewer C: macOS 12–26 API availability, arm64/x86_64 behavior, packaging, installer, and regression compatibility.

Each reviewer must read `AGENTS.md`, inspect the entire relevant diff, continue after the first finding, cite tight line ranges, and return `No findings.` when none qualify. Reviewers must not edit.

- [ ] **Step 2: Reproduce every finding before editing**

For each reported P0–P3, write the smallest failing unit, executable harness, or real AppKit scenario. Reject speculative findings with concrete counter-evidence; do not patch by deference.

- [ ] **Step 3: Fix each validated finding test-first**

Observe RED, implement the smallest aligned fix, rerun focused GREEN, and request the original reviewer to recheck the latest tree.

- [ ] **Step 4: Repeat independent review until all three are clean**

All three final reports must contain no unresolved actionable findings. Run Task 6 again after the final production edit.

- [ ] **Step 5: Commit reviewed feature**

Stage only intentional project files and commit with a message describing the completed Settings feature and verified hardening.

---

### Task 8: Patch Release, Local Install, and Cody Email

**Files:**
- Modify: `VERSION`
- Modify: release-facing tests/docs required by `.agent/release.md`
- Modify/create: release artifacts only through existing packaging scripts.

**Interfaces:**
- Consumes all clean review and verification evidence.
- Produces a new patch version greater than already-published 3.0.4, exact public PKG/DMG/checksums, installed local receipt, and Cody email thread reply.

- [ ] **Step 1: Bump to a new patch version**

Do not reuse 3.0.4 for changed bytes. Update `VERSION` and exact release contracts together.

- [ ] **Step 2: Run `.agent/release.md` required gates**

Build the universal candidate, validate versions/architectures/minimum OS, run package lifecycle checks, and verify signing/notarization claims match the actual channel.

- [ ] **Step 3: Install the exact candidate PKG locally**

Use the public package, not `scripts/install.sh`, for `/Applications/Wattson.app`. Verify bundle version/build, receipt version, universal slices, helper health and power probes, launchd state, and one running canonical app. Preserve user setting values.

- [ ] **Step 4: Exercise the installed app**

Verify live power freshness, temperature, Settings window, Command-Comma, launch-at-login status, battery-icon state, slider edge contact, and sleep/wake recovery where safely possible.

- [ ] **Step 5: Reply to Cody by email**

Use the existing Cody Gmail thread. Summarize the fixed latency/temperature/settings/compatibility work, attach or link the exact new package and checksum, and provide the one-click Diagnostics v1.1.0 only if further machine-specific evidence is needed. Do not email before the installed candidate passes all gates.
