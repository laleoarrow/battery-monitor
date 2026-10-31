import AppKit
import CryptoKit

/// Exercises the production content/scroller in owned real windows. Hardware
/// readings and privileged Settings dependencies are deterministic fixtures.
@main
private enum CaptureScrollbar {
    static func main() {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let defaults = MemoryDefaults()
        Settings.configureForTest(defaults: defaults)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let probe = Probe(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        app.delegate = probe
        withExtendedLifetime((defaults, probe)) { app.run() }
        Settings.resetTestConfiguration()
    }
}

private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ value: Bool, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

private final class FixtureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class Probe: NSObject, NSApplicationDelegate {
    private let directory: URL
    private var windows: [NSWindow] = []
    private var content: PopoverContentViewController?
    private var settings: SettingsWindowController?
    private var assertions = 0
    private var records: [[String: Any]] = []
    private var motion: [String: Any] = [:]
    private let fixtures: [(String, PowerSnapshot)] = [
        ("charging", .init(percent: 72, plugged: true, adapterW: 68, batteryW: 22.2, systemW: 45.8, temperatureC: 34.2, batteryTimeEstimate: .charging(42), batteryTimeEstimateSource: .system)),
        ("full", .init(percent: 100, plugged: true, adapterW: 21.1, systemW: 21.1, temperatureC: 31.8, batteryTimeEstimate: .full, batteryTimeEstimateSource: .system)),
        ("on-battery", .init(percent: 67, batteryW: -39.7, systemW: 39.7, temperatureC: 33.1, batteryTimeEstimate: .remaining(265), batteryTimeEstimateSource: .system)),
        ("mixed-supply", .init(percent: 18, plugged: true, adapterW: 28, batteryW: -31.7, systemW: 59.7, temperatureC: 38.6, batteryTimeEstimate: .notCharging)),
        ("low-battery", .init(percent: 14, batteryW: -12, systemW: 12, temperatureC: 32.4, batteryTimeEstimate: .remaining(18), batteryTimeEstimateSource: .system)),
        ("low-power", .init(percent: 67, batteryW: -12, systemW: 12, temperatureC: 32.4, lowPowerMode: true, batteryTimeEstimate: .remaining(310), batteryTimeEstimateSource: .system)),
    ]

    init(directory: URL) { self.directory = directory }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 100) { [weak self] in
            self?.stop()
            fputs("ScrollbarProbe: watchdog expired\n", stderr)
            exit(1)
        }
        Task { @MainActor in
            do {
                try await run()
                stop()
                NSApp.terminate(nil)
            } catch {
                fputs("ScrollbarProbe: \(error)\n", stderr)
                stop()
                exit(1)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { stop() }

    private func stop() {
        content?.setPresentationActive(false)
        content?.setAnimationsEnabled(false)
        content = nil
        settings?.windowForTest?.close()
        settings = nil
        windows.reversed().forEach { $0.close() }
        windows.removeAll()
    }

    @MainActor private func run() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try check(Settings.scrollbarStyle == .flow, "Unconfigured App does not default to Flow")
        Settings.checksForUpdatesOnLaunch = false
        for module in Settings.Module.allCases { Settings.setModule(module, visible: true) }
        guard let screen = NSScreen.main else { throw failure("No GUI screen") }
        let background = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        configure(background)
        background.orderFrontRegardless()
        let window = FixtureWindow(contentRect: NSRect(x: screen.frame.midX - 180, y: screen.frame.midY - 120,
                                                       width: PopoverStyle.width, height: 240),
                                   styleMask: .borderless, backing: .buffered, defer: false)
        configure(window)
        let controller = PopoverContentViewController()
        content = controller
        window.contentViewController = controller
        // Attaching a controller adopts its initial 1pt placeholder height.
        // Establish the real fixture window before testing input or capture.
        window.setContentSize(NSSize(width: PopoverStyle.width, height: 240))
        controller.setViewportHeight(240)
        window.makeKeyAndOrderFront(nil)
        try check(window.contentRect(forFrameRect: window.frame).height == 240,
                  "Fixture window did not retain its 240pt viewport")
        controller.setPresentationActive(true)
        controller.setAnimationsEnabled(false)
        let scroll = controller.scrollViewForTest

        for scheme in [Settings.ColorScheme.light, .dark] {
            Settings.colorScheme = scheme
            NSApp.appearance = scheme.appearance
            window.appearance = scheme.appearance
            background.backgroundColor = scheme == .light ? .init(white: 0.88, alpha: 1) : .init(white: 0.14, alpha: 1)
            window.appearance?.performAsCurrentDrawingAppearance { window.backgroundColor = PopoverStyle.surface }
            for fixture in fixtures {
                controller.update(snapshot: fixture.1, history: [10, 20, 30, 20], peak: 30, degraded: false)
                for nativeStyle in [NSScroller.Style.overlay, .legacy] {
                    controller.setViewportHeight(240)
                    Settings.scrollbarStyle = .simple
                    try await pause(0.03)
                    // A windowed NSScrollView can reapply the system style when
                    // its scroller is enabled. Force the fixture mode only after
                    // viewport setup; subsequent preference switches must keep it.
                    scroll.scrollerStyle = nativeStyle
                    scroll.tile()
                    controller.view.layoutSubtreeIfNeeded()
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    let baseline = geometry(controller)
                    let nativeScroller = scroll.verticalScroller
                    let offset = scroll.contentView.bounds.origin
                    try check(scroll.scrollerStyle == nativeStyle, "Could not establish the requested native fixture mode")
                    for style in [Settings.ScrollbarStyle.hidden, .flow, .simple] {
                        Settings.scrollbarStyle = style
                        try await pause(0.03)
                        controller.view.layoutSubtreeIfNeeded()
                        try check(geometry(controller) == baseline, "Body geometry changed: \(scheme.rawValue)/\(fixture.0)/\(nativeStyle.rawValue)/\(style.rawValue); baseline=\(baseline); actual=\(geometry(controller))")
                        try check(scroll.contentView.bounds.origin == offset, "Style changed reading position")
                        try check(scroll.verticalScroller === nativeScroller, "Style replaced the native scroller instance")
                        try check(scroll.scrollerStyle == nativeStyle, "Style overrides system scroller mode: requested=\(nativeStyle.rawValue), actual=\(scroll.scrollerStyle.rawValue), preference=\(style.rawValue)")
                        if style == .simple {
                            try check(scroll.verticalScroller?.isAccessibilityElement() == true, "Simple must retain the native scrollbar control")
                        } else if style == .flow {
                            let flow = controller.flowScrollbarForTest
                            try check(!flow.isHidden && flow.isEnabled, "Flow scroller is unavailable")
                            let frame = flow.convert(flow.bounds, to: controller.view)
                            try check(frame.midX > controller.view.bounds.midX, "Flow is not on the right")
                            try check(flow.frame.width <= 26, "Flow steals a wide content hit area")
                        } else {
                            try check(controller.flowScrollbarForTest.isHidden, "Hidden retains Flow artwork")
                        }
                        records.append(["case": "\(scheme.rawValue)-\(fixture.0)-\(nativeStyle.rawValue)-\(style.rawValue)",
                                        "bodyGeometry": baseline, "offset": NSStringFromPoint(offset), "passed": true])
                    }
                }
                Settings.scrollbarStyle = .flow
                scroll.scrollerStyle = .overlay
                controller.setViewportHeight(240)
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
                try await pause(0.08)
                try capture(window, background: background, name: "flow-\(scheme.rawValue)-\(fixture.0)")
                if fixture.0 == "charging" {
                    for style in [Settings.ScrollbarStyle.simple, .hidden, .flow] {
                        Settings.scrollbarStyle = style
                        scroll.flashScrollers()
                        try await pause(0.08)
                        try capture(window, background: background, name: "switch-\(scheme.rawValue)-\(style.rawValue)")
                    }
                }
            }
            try await captureSettings(background: background, name: "settings-\(scheme.rawValue)")
            window.makeKeyAndOrderFront(nil)
        }

        Settings.scrollbarStyle = .flow
        controller.setViewportHeight(240)
        try await dragToBoundary(controller.flowScrollbarForTest, window: window, bottom: true)
        try check(abs(scroll.contentView.bounds.minY - (controller.preferredHeight - 240)) < 2, "Native thumb drag did not reach bottom")
        try await dragToBoundary(controller.flowScrollbarForTest, window: window, bottom: false)
        try check(scroll.contentView.bounds.minY < 2, "Native thumb drag did not reach top")
        for style in Settings.ScrollbarStyle.allCases {
            Settings.scrollbarStyle = style
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
            scroll.reflectScrolledClipView(scroll.contentView)
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -80, wheel2: 0, wheel3: 0),
                  let event = NSEvent(cgEvent: cg) else { throw failure("Cannot create wheel fixture") }
            if style == .flow { controller.flowScrollbarForTest.scrollWheel(with: event) }
            else { scroll.scrollWheel(with: event) }
            try await pause(0.08)
            try check(scroll.contentView.bounds.minY > 100, "Native wheel fails in \(style.rawValue)")
        }
        Settings.scrollbarStyle = .flow
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        try await observeMotion(controller, window: window, background: background)
        controller.setViewportHeight(controller.preferredHeight + 10)
        try check(controller.flowScrollbarForTest.isHidden, "No-overflow viewport retains Flow")
        try check(animationCount(controller.flowScrollbarForTest.layer) == 0, "No-overflow viewport animates")
        controller.setViewportHeight(240)
        controller.setPresentationActive(false)
        controller.setAnimationsEnabled(false)
        try check(animationCount(controller.flowScrollbarForTest.layer) == 0, "Closing retained Flow animations")
        window.orderOut(nil)
        try check(animationCount(controller.flowScrollbarForTest.layer) == 0, "Hidden window retained Flow animations")

        let evidence: [String: Any] = [
            "schema": 1, "assertions": assertions, "failures": 0, "cases": records, "motion": motion,
            "method": "Production content and Settings in owned WindowServer fixture windows; six battery states, light/dark, native overlay/legacy and all three preferences. Native NSScroller drag queue and native wheel handling; live Core Animation presentation samples.",
            "limitations": "Fixtures do not read hardware or privileged services. The content window is not a native NSPopover/Glass host; use the separate production popup matrix for host compositing acceptance. Body comparisons cover geometry across preferences, not a pixel baseline from an earlier release.",
        ]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("evidence.json"), options: .atomic)
        print("Scrollbar: \(records.count) records, \(assertions) assertions, 0 failures")
    }

    private func configure(_ window: NSWindow) {
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.hasShadow = false
        window.isOpaque = true
        windows.append(window)
    }

    private func geometry(_ controller: PopoverContentViewController) -> [String] {
        let scroll = controller.scrollViewForTest
        let document = scroll.documentView!
        return [NSStringFromRect(document.frame), NSStringFromSize(scroll.contentSize)]
            + Settings.Module.allCases.map { NSStringFromRect(controller.moduleViewForTest($0).convert(controller.moduleViewForTest($0).bounds, to: document)) }
    }

    @MainActor private func dragToBoundary(_ scroller: NSScroller, window: NSWindow, bottom: Bool) async throws {
        let knob = scroller.rect(for: .knob)
        let slot = scroller.rect(for: .knobSlot)
        try check(!knob.isEmpty && !slot.isEmpty, "Native scroller has no drag region")
        let start = scroller.convert(NSPoint(x: knob.midX, y: knob.midY), to: nil)
        let targetY = bottom == scroller.isFlipped ? slot.maxY + 20 : slot.minY - 20
        let end = scroller.convert(NSPoint(x: knob.midX, y: targetY), to: nil)
        let now = ProcessInfo.processInfo.systemUptime
        func event(_ type: NSEvent.EventType, _ point: NSPoint, _ step: Int) throws -> NSEvent {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: now + Double(step) * 0.02,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: step, clickCount: 1, pressure: 1)
            else { throw failure("Cannot create native drag fixture") }
            return event
        }
        for step in 1...8 {
            let fraction = CGFloat(step) / 8
            let point = NSPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
            NSApp.postEvent(try event(.leftMouseDragged, point, step), atStart: false)
        }
        NSApp.postEvent(try event(.leftMouseUp, end, 9), atStart: false)
        window.sendEvent(try event(.leftMouseDown, start, 0))
        try await pause(0.08)
    }

    @MainActor private func observeMotion(_ controller: PopoverContentViewController, window: NSWindow, background: NSWindow) async throws {
        let scroller = controller.flowScrollbarForTest
        setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
        scroller.refreshAppearance()
        controller.setPresentationActive(true)
        controller.setAnimationsEnabled(true)
        try await pause(0.15)
        guard let capsule = scroller.layer?.sublayers?.first(where: { $0.name == "flow-knob" }),
              let points = capsule.sublayers, points.count == 5 else { throw failure("Missing Flow capsule or five points") }
        try check(capsule.masksToBounds && capsule.cornerRadius > 0 && capsule.bounds.width == 6, "Flow is not clipped to its 6pt capsule")
        try check(animationCount(scroller.layer) == 5, "Flow should animate exactly five points")
        try capture(window, background: background, name: "motion-start")
        var previous: [(CGFloat, Float)] = []
        var resets = 0, downward = 0, frames = 0, uneven = 0
        var samples: [[String: Any]] = []
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < 5.2 {
            let values = points.map { point -> (CGFloat, Float) in
                let sample = point.presentation() ?? point
                return (sample.position.y, sample.opacity)
            }
            let sorted = values.map(\.0).sorted()
            let gaps = zip(sorted, sorted.dropFirst()).map { $1 - $0 }
            if let largest = gaps.max(), let smallest = gaps.min(), largest > smallest * 1.5 { uneven += 1 }
            for (index, value) in values.enumerated() {
                if value.1 > 0.01 {
                    let sample = points[index].presentation() ?? points[index]
                    try check(capsule.bounds.insetBy(dx: -0.1, dy: -0.1).contains(sample.frame), "Visible point escapes capsule")
                }
                if previous.count == values.count {
                    let delta = (value.0 - previous[index].0) * (scroller.isFlipped ? 1 : -1)
                    if delta < -capsule.bounds.height / 2 {
                        resets += 1
                        try check(value.1 <= 0.01 && previous[index].1 <= 0.01, "Point visibly returns to top")
                    } else {
                        try check(delta >= -0.15, "Point visibly moves upward")
                        if delta > 0.05 { downward += 1 }
                    }
                }
            }
            previous = values
            if frames % 20 == 0 {
                samples.append(["seconds": CACurrentMediaTime() - start,
                                "positions": values.map { Double($0.0) },
                                "opacity": values.map { Double($0.1) },
                                "beginTimes": points.map { $0.animation(forKey: "flow")?.beginTime ?? -1 },
                                "layerSpeed": scroller.layer?.speed ?? -1])
            }
            frames += 1
            try await pause(1 / 60)
        }
        try JSONSerialization.data(withJSONObject: ["frames": frames, "resets": resets,
            "downward": downward, "uneven": uneven, "samples": samples], options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("motion-samples.json"), options: .atomic)
        try check(frames >= 20 && resets >= 5 && downward > frames && uneven >= frames * 9 / 10,
                  "Flow motion is missing or evenly spaced: frames=\(frames), resets=\(resets), downward=\(downward), uneven=\(uneven)")
        try check(!scroller.isHidden && scroller.alphaValue > 0.99 && !capsule.isHidden, "Flow faded away after five seconds")
        try capture(window, background: background, name: "motion-after-five-seconds")
        setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
        scroller.refreshAppearance()
        try check(animationCount(scroller.layer) == 0, "Reduce Motion leaves animations running")
        let staticPoints = points.map(\.position)
        try await pause(0.15)
        try check(points.map(\.position) == staticPoints, "Reduce Motion moves points")
        try capture(window, background: background, name: "reduced-motion")
        motion = ["durationSeconds": CACurrentMediaTime() - start, "sampledFrames": frames,
                  "transparentResets": resets, "downwardSteps": downward, "unevenFrames": uneven,
                  "visibleUpwardSteps": 0, "visibleClippingFailures": 0, "reducedMotionStatic": true]
    }

    @MainActor private func captureSettings(background: NSWindow, name: String) async throws {
        let dependencies = SettingsWindowDependencies(loginItemState: { .enabled }, refreshLoginItem: { $0(.enabled) }, setLoginItemEnabled: { value, done in done(.success(value ? .enabled : .notRegistered)) }, systemBatteryIconHidden: { false }, helperAvailable: { true }, refreshSystemBatteryIcon: { $0(false) }, setSystemBatteryIconHidden: { _, done in done(true) }, systemBatteryIconDidChange: Notification.Name("Wattson.ScrollbarCapture.Battery"), currentVersion: { "Development" }, checkForUpdates: { $0(.success(.upToDate(currentVersion: "Development"))) }, openUpdateURL: { _ in true }, increaseContrast: { false }, announceAccessibility: { _ in })
        let controller = SettingsWindowController(dependencies: dependencies, frameAutosaveName: nil)
        settings = controller
        controller.selectSectionForTest(identifier: "general")
        controller.refreshSectionsForTest()
        guard let window = controller.windowForTest, let root = window.contentView else { throw failure("Missing Settings window") }
        window.animationBehavior = .none
        window.makeKeyAndOrderFront(nil)
        try await pause(0.15)
        guard let popup = descendants(root).first(where: { $0.identifier?.rawValue == "settings.appearance.scrollbar-style" }) as? NSPopUpButton,
              let scroll = descendants(root).first(where: { $0.identifier?.rawValue == "settings.general.scroll" }) as? NSScrollView,
              let document = scroll.documentView else { throw failure("Missing Settings scrollbar selector") }
        try check(popup.itemTitles == ["Hidden", "Simple", "Flow"], "Settings lacks three expected styles")
        try check(window.makeFirstResponder(popup), "Settings scrollbar selector cannot receive keyboard focus")
        try await pause(0.1)
        try check(scroll.documentVisibleRect.insetBy(dx: -1, dy: -1).contains(popup.convert(popup.bounds, to: document)), "Settings selector is clipped")
        for style in Settings.ScrollbarStyle.allCases {
            popup.selectItem(withTitle: style.title)
            try check(popup.sendAction(popup.action, to: popup.target), "Selector action not connected")
            try check(Settings.scrollbarStyle == style, "Selector does not save \(style.rawValue)")
        }
        try capture(window, background: background, name: name)
        window.close()
        settings = nil
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func capture(_ window: NSWindow, background: NSWindow, name: String) throws {
        guard let screen = window.screen else { throw failure("No capture screen") }
        let rect = window.frame
        try check(rect.width >= 100 && rect.height >= 100, "Refusing a collapsed window capture")
        let region = NSRect(x: rect.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        guard window.isVisible, let image = WattsonCaptureOwnedWindows(region, CGWindowID(window.windowNumber), CGWindowID(background.windowNumber)),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw failure("WindowServer capture refused") }
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        records.append(["image": name + ".png", "composited": true, "pixels": [image.width, image.height],
                        "imageSHA256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()])
    }
    private func animationCount(_ layer: CALayer?) -> Int {
        guard let layer else { return 0 }
        return (layer.animationKeys()?.count ?? 0) + (layer.sublayers ?? []).reduce(0) { $0 + animationCount($1) }
    }
    private func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func check(_ passed: Bool, _ message: String) throws { assertions += 1; if !passed { throw failure(message) } }
    private func failure(_ message: String) -> NSError { NSError(domain: "ScrollbarProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
