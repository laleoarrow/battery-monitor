import AppKit
import ApplicationServices
import Darwin
// Isolate appearance before any popover/footer is constructed; an installed
// app's saved choice must not change which baseline this harness exercises.
let settingsSuiteName = ProcessInfo.processInfo.environment["WATTSON_TEST_DEFAULTS_SUITE"]!
let settingsDefaults = UserDefaults(suiteName: settingsSuiteName)!
settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
Settings.configureForTest(defaults: settingsDefaults)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func log(_ s: String) { print(s); fflush(stdout) }
var pass = true
func check(_ n: String, _ ok: Bool, _ d: String = "") {
    if !ok { pass = false }
    log("\(ok ? "✅" : "❌") \(n)\(d.isEmpty ? "" : "  — \(d)")")
}

/// A locked screen starts CoreAnimation but never finishes it, so anything
/// waiting on a close animation to complete hangs forever. Reporting that as a
/// failure would be inventing eight bugs that do not exist, and reporting it as
/// a pass would be worse. Say plainly that it could not be checked.
let screenLocked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Int == 1
let initialReduceMotionOverride = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"]
let forcedReduceMotion: Bool
switch initialReduceMotionOverride {
case "1": forcedReduceMotion = true
case "0": forcedReduceMotion = false
default: forcedReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

// ---- 1. 点击路由：AppKit 可能送达的每一种单击形态 ----
func run(_ steps: [NSEvent.EventType?], control: Bool = false) -> [ClickIntent] {
    var router = ClickRouter()
    return steps.flatMap { router.intents(for: $0, controlHeld: control) }
}
let held = run([.leftMouseDown, .leftMouseUp])
check("长按只切换一次", held.filter { $0 == .primary }.count == 1, "\(held)")
check("只送达 up 的轻触仍会切换", run([.leftMouseUp]).contains(.primary))
check("currentEvent 为 nil 时仍会切换", run([nil]).contains(.primary))
check("连续两次轻触切换两次",
      run([.leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp]).filter { $0 == .primary }.count == 2)
let right = run([.rightMouseDown, .rightMouseUp])
check("右键只切模式不开弹窗", right.filter { $0 == .secondary }.count == 1 && !right.contains(.primary))
check("control+点击视为右键", run([.leftMouseDown], control: true).contains(.secondary))
check("按下仍会置 pressed", held.first == .press && held.contains(.release))

var rightClickModes = RightClickModeSequence()
let rapid1 = rightClickModes.next(current: .auto)
let rapid2 = rightClickModes.next(current: .auto)
let rapid3 = rightClickModes.next(current: .auto)
check("三次快速右键仍按乐观状态逐次翻转",
      [rapid1.mode, rapid2.mode, rapid3.mode] == [.low, .auto, .low])
check("同目标的旧右键回调不能冒充最新请求",
      !rightClickModes.finish(generation: rapid1.generation)
          && rightClickModes.finish(generation: rapid3.generation))

// ---- 2. 真实 NSStatusItem + NSPopover ----
// 从这里到第 3 节结束，全部依赖关闭动画真的跑完
if screenLocked {
    log("")
    log("⏭  屏幕已锁定：关闭动画不会完成，弹窗开合与动画停止的检查无法进行")
    log("   解锁后重跑 ./scripts/verify_interaction.sh 才算验过")
    log("SCREEN_LOCKED_CHECKS_SKIPPED")
    log("")
}
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
item.button?.image = NSImage(systemSymbolName: "battery.100", accessibilityDescription: nil)
guard let button = item.button else { log("no button"); exit(1) }
app.finishLaunching()                     // 少了这句状态栏按钮无法承载弹窗
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
func spin(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

func reducedMotionAnimationsAreSafe(
    _ controller: PopoverController,
    descriptions: [String]
) -> Bool {
    guard controller.runningInfiniteAnimationCountForTest == 0,
          controller.runningModuleAnimationCountForTest == 0 else { return false }
    guard !descriptions.isEmpty else { return true }
    guard descriptions.count == 1,
          descriptions[0] == "root:wattson.popover.entrance",
          let group = controller.entranceAnimationForTest as? CAAnimationGroup,
          let animations = group.animations,
          animations.count == 1,
          let fade = animations[0] as? CABasicAnimation else { return false }
    let fromOpacity = (fade.fromValue as? NSNumber)?.doubleValue
    let toOpacity = (fade.toValue as? NSNumber)?.doubleValue
    return fade.keyPath == "opacity"
        && abs(group.duration - 0.12) < 0.000_001
        && abs(fade.duration - 0.12) < 0.000_001
        && fromOpacity.map { abs($0 - 0.65) < 0.000_001 } == true
        && toOpacity.map { abs($0 - 1.0) < 0.000_001 } == true
        && group.repeatCount == 0 && group.repeatDuration == 0
        && fade.repeatCount == 0 && fade.repeatDuration == 0
        && !group.autoreverses && !fade.autoreverses
        && group.isRemovedOnCompletion && fade.isRemovedOnCompletion
}

/// Activation is an NSApplication concern, not just a Foundation run-loop
/// concern. Enter the real application event loop for assertions that depend
/// on key-window ownership, then stop it without injecting user events.
func runApplication(until condition: @escaping () -> Bool,
                    timeout: TimeInterval) -> Bool {
    var satisfied = condition()
    let deadline = Date().addingTimeInterval(timeout)

    func stopApplicationLoop() {
        app.stop(nil)
        if let wake = NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        ) {
            app.postEvent(wake, atStart: false)
        }
    }

    func poll() {
        satisfied = condition()
        guard !satisfied, Date() < deadline else {
            stopApplicationLoop()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
    }

    DispatchQueue.main.async { poll() }
    app.run()
    return satisfied
}

final class StatusClickDispatchProbe: NSObject {
    let controller = PopoverController()
    private var router = ClickRouter()
    private(set) var actionCount = 0
    private(set) var primaryCount = 0

    @objc func clicked(_ sender: NSStatusBarButton) {
        actionCount += 1
        let event = app.currentEvent
        for intent in router.intents(for: event?.type,
                                     controlHeld: event?.modifierFlags.contains(.control) ?? false) {
            if intent == .primary {
                primaryCount += 1
                controller.toggle(relativeTo: sender)
            }
        }
    }
}

func queueClick(in window: NSWindow, at point: NSPoint, number: Int) -> Bool {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        guard let event = NSEvent.mouseEvent(with: type, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: number, clickCount: 1, pressure: 1) else { return false }
        app.postEvent(event, atStart: false)
    }
    return true
}

if !screenLocked {
    app.finishLaunching()

    // The rapid fade/reopen and native didClose counting below intentionally
    // exercise Classic NSPopover, not the independent Glass panel.
    Settings.liquidGlassEnabled = false
    let p = PopoverController()
    let fullSnapshot = PowerSnapshot(
        percent: 100, plugged: true, adapterW: 52,
        batteryW: 0, systemW: 52
    )
    p.update(snapshot: fullSnapshot, history: [50, 52], peak: 52, degraded: false)
    check("关闭时只缓存最新数据而不渲染隐藏弹窗",
          p.contentRenderCountForTest == 0 && p.cachedPercentForTest == 100)
    check("初始未监听外部点击", !p.isWatchingOutsideClicks)
    let anchorReady = runApplication(until: {
        guard let window = button.window, window.isVisible,
              !button.isHiddenOrHasHiddenAncestor else { return false }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        return PopoverPlacement.resolve(
            anchor: anchor,
            displays: NSScreen.screens.map {
                PopoverPlacement.Display(frame: $0.frame, visibleFrame: $0.visibleFrame)
            },
            naturalSize: p.contentViewForTest?.frame.size ?? .zero
        ) != nil
    }, timeout: 2)
    check("真实状态项完成初始屏幕定位后才模拟点击", anchorReady)
    let originalGlassSetting = Settings.liquidGlassEnabled
    let hiddenLaunchHosts: [Bool]
    if #available(macOS 26.0, *) { hiddenLaunchHosts = [false, true] }
    else { hiddenLaunchHosts = [false] }
    for glass in hiddenLaunchHosts {
        Settings.liquidGlassEnabled = glass
        let hiddenController = PopoverController()
        hiddenController.update(snapshot: fullSnapshot, history: [50, 52], peak: 52, degraded: false)
        app.hide(nil)
        check("隐藏启动回归建立真实隐藏状态 glass=\(glass)",
              runApplication(until: { app.isHidden }, timeout: 2))
        hiddenController.toggle(relativeTo: button)
        check("菜单栏打开恢复隐藏 App 的实际弹窗 glass=\(glass)",
              runApplication(until: { hiddenController.isShownForTest && !app.isHidden }, timeout: 2)
                  && hiddenController.isOpen)
        hiddenController.handleOutsideClick()
        spin(0.8)
        app.unhideWithoutActivation()
    }
    Settings.liquidGlassEnabled = originalGlassSetting
    if let anchorWindow = button.window {
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let displays = NSScreen.screens.map {
            PopoverPlacement.Display(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        let placement = PopoverPlacement.resolve(
            anchor: anchor, displays: displays,
            naturalSize: p.contentViewForTest?.frame.size ?? .zero
        )
        let displayDescription = displays.map { "frame=\($0.frame) visible=\($0.visibleFrame)" }
        log("INITIAL_ANCHOR windowVisible=\(anchorWindow.isVisible) hidden=\(button.isHiddenOrHasHiddenAncestor) buttonFrame=\(button.frame) buttonBounds=\(button.bounds) windowFrame=\(anchorWindow.frame) anchor=\(anchor) screens=\(displayDescription) resolved=\(String(describing: placement))")
    } else {
        log("INITIAL_ANCHOR window=nil buttonFrame=\(button.frame) buttonBounds=\(button.bounds)")
    }
    p.toggle(relativeTo: button)
    check("展示前恰好渲染一次最新缓存数据", p.contentRenderCountForTest == 1)
    check("点击打开会安排一次平滑入场动画", p.entranceAnimationCountForTest == 1)
    if forcedReduceMotion {
        let immediateDescriptions = p.runningAnimationDescriptionsForTest
        check("减少动态效果允许经验证的短暂透明度淡入",
              reducedMotionAnimationsAreSafe(p, descriptions: immediateDescriptions),
              "\(immediateDescriptions)")
        check("减少动态效果拒绝任何额外动画",
              !reducedMotionAnimationsAreSafe(
                  p, descriptions: immediateDescriptions + ["root/rogue:opacity"]
              ))
    }
    spin(0.4)
    check("轻触图标弹窗打开", p.isShownForTest && p.isOpen)
    check("Classic 保留原 NSPopover 生命周期与全局监听",
          p.glassPanelForTest == nil && p.hasLocalEventMonitorForTest
              && p.lifetimeObserverCountForTest == 3
              && p.classicPopoverForTest.behavior == .semitransient
              && p.classicLifecycleCountsForTest.shows > 0)
    check("打开后开始监听外部点击", p.isWatchingOutsideClicks)
    if let raw = ProcessInfo.processInfo.environment["WATTSON_EXPECTED_POWER_MODE"],
       let expected = ["0": EnergyMode.auto, "1": .low, "2": .high][raw] {
        let deadline = Date().addingTimeInterval(1.5)
        while EnergyModeController.current != expected && Date() < deadline { spin(0.05) }
        check("沙盒 App 识别真实电源模式",
              EnergyModeController.current == expected,
              "预期 \(expected.rawValue)，实际 \(EnergyModeController.current.rawValue)")
        if HelperClient.isInstalled {
            check("旧 helper 回包错误时仍能确认真实落地档位",
                  EnergyModeController.set(expected),
                  "请求保持 \(expected.rawValue)，落地 \(EnergyModeController.current.rawValue)")
        }
    }
    p.handleOutsideClick()
    check("外部点击后立刻停止监听", !p.isWatchingOutsideClicks)
    spin(1.2)
    check("点击桌面/其他 app 后弹窗收起", !p.isShownForTest && !p.isOpen)

    p.toggle(relativeTo: button); spin(0.4)
    p.toggle(relativeTo: button)                 // 关，不用固定等待猜测动画时长
    let dismissalInFlight = !p.isOpen && p.isShownForTest
    p.toggle(relativeTo: button)                 // 立刻再点想重开
    if dismissalInFlight {
        check("关闭中途重开不会从低透明度重播入场",
              p.entranceAnimationCountForTest == 0)
    } else {
        log("⏭  当前系统同步完成关闭：没有可验证的关闭中途重开窗口")
    }
    spin(1.2)
    check("关闭动画中途再点可立即重开", p.isShownForTest && p.isOpen)
    check("重开后仍在监听外部点击", p.isWatchingOutsideClicks)
    p.handleOutsideClick(); spin(1.2)
    check("重开后的弹窗仍可被外部点击收起", !p.isShownForTest && !p.isOpen)

    p.toggle(relativeTo: button); spin(0.4)
    p.closeBypassingControllerForTest(); spin(1.2)   // AppKit 自行瞬态关闭（Esc 等）
    check("AppKit 自行关闭后意图已复位", !p.isOpen)
    check("AppKit 自行关闭后监听已撤除", !p.isWatchingOutsideClicks)
    p.toggle(relativeTo: button); spin(0.4)
    check("自行关闭后下一次点击仍能打开", p.isShownForTest && p.isOpen)
    p.handleOutsideClick(); spin(1.2)

    if let anchorFrame = button.window?.frame {
        let anchorPoint = NSPoint(x: anchorFrame.midX, y: anchorFrame.maxY)
        p.openForSettingsCommandTest(relativeTo: button)
        let nativeAllowsClose = p.classicShouldCloseForTest(screenPoint: anchorPoint,
            pressedMouseButtons: 1)
        if nativeAllowsClose { p.closeBypassingControllerForTest(); spin(1.2) }
        check("[I19-NATIVE] Classic 自动关闭委托保留同一次锚点按下", !nativeAllowsClose && p.isOpen)
        p.toggle(relativeTo: button); spin(1.2)
        check("[I19-NATIVE] 原生自动关闭先于按钮动作仍只关闭一次", !p.isOpen && !p.isShownForTest)
        p.toggle(relativeTo: button); spin(0.4)
        check("[I19-NATIVE] 被保护的关闭之后下一次图标点击仍能重开", p.isOpen && p.isShownForTest)
        p.handleOutsideClick(); spin(1.2)

        p.openForSettingsCommandTest(relativeTo: button)
        p.handleWorkspaceActivationForTest(screenPoint: anchorPoint, pressedMouseButtons: 1)
        p.toggle(relativeTo: button); spin(1.2)
        check("[I19-WORKSPACE] Classic 激活通知先于同一次按钮动作仍只关闭一次",
              !p.isOpen && !p.isShownForTest)
        p.toggle(relativeTo: button); spin(0.4)
        check("[I19-WORKSPACE] 激活通知保护之后下一次图标点击仍能重开", p.isOpen && p.isShownForTest)
        p.handleOutsideClick(); spin(1.2)

        p.openForSettingsCommandTest(relativeTo: button)
        check("[I19-IDLE] 鼠标仅停在锚点时 Classic 原生关闭仍被允许",
              p.classicShouldCloseForTest(screenPoint: anchorPoint, pressedMouseButtons: 0))
        p.closeBypassingControllerForTest(); spin(1.2)
        check("[I19-IDLE] 无按下时 Classic 自行关闭清理完整", !p.isOpen && !p.isWatchingOutsideClicks)
        p.openForSettingsCommandTest(relativeTo: button)
        p.handleWorkspaceActivationForTest(screenPoint: anchorPoint, pressedMouseButtons: 0)
        spin(1.2)
        check("[I19-IDLE] 鼠标停在锚点不阻止真正切换应用关闭 Classic",
              !p.isOpen && !p.isShownForTest && !p.isWatchingOutsideClicks)

        // Dequeue without dispatch: AppKit's cached last event is independent
        // of the live button state injected at this private policy boundary.
        for type in [NSEvent.EventType.leftMouseUp, .keyDown] {
            p.openForSettingsCommandTest(relativeTo: button)
            let cached: NSEvent
            let mask: NSEvent.EventTypeMask
            if type == .leftMouseUp {
                cached = NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                    eventNumber: 1900, clickCount: 1, pressure: 0)!
                mask = .leftMouseUp
            } else {
                cached = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                    characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 0)!
                mask = .keyDown
            }
            app.postEvent(cached, atStart: true)
            _ = app.nextEvent(matching: mask, until: Date(), inMode: .default, dequeue: true)
            let staleType = app.currentEvent?.type
            let allowed = p.classicShouldCloseForTest(screenPoint: anchorPoint, pressedMouseButtons: 1)
            p.handleWorkspaceActivationForTest(screenPoint: anchorPoint, pressedMouseButtons: 1)
            check("[I19-CACHED] 缓存 \(type) 不覆盖实时主键按下",
                  staleType == type && !allowed && p.isOpen)
            p.handleOutsideClick(); spin(1.2)
        }
    }

    // Route actual queued events through the status window and target/action.
    // Direct toggle calls cannot catch native dismissal swallowing the button.
    if let statusWindow = button.window {
        let probe = StatusClickDispatchProbe()
        probe.controller.update(snapshot: fullSnapshot, history: [50, 52], peak: 52, degraded: false)
        let oldTarget = button.target
        let oldAction = button.action
        let oldMask = button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp])
        button.target = probe
        button.action = #selector(StatusClickDispatchProbe.clicked(_:))
        var rawEvents = 0
        var outsideEvents = 0
        let otherWindow = NSWindow(contentRect: NSRect(x: 40, y: 300, width: 120, height: 80),
            styleMask: [.titled], backing: .buffered, defer: false)
        otherWindow.isReleasedWhenClosed = false
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
            if event.window === statusWindow { rawEvents += 1 }
            if event.window === otherWindow { outsideEvents += 1 }
            return event
        }
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        _ = queueClick(in: statusWindow, at: point, number: 2001)
        let opened = runApplication(until: {
            probe.primaryCount == 1 && probe.controller.isShownForTest
        }, timeout: 2)
        check("真实状态窗口事件通过 target/action 打开 Classic", opened && rawEvents > 0)
        if let root = probe.controller.contentViewForTest, let window = root.window {
            let y = root.isFlipped ? root.bounds.minY + 30 : root.bounds.maxY - 30
            let contentPoint = root.convert(NSPoint(x: root.bounds.midX, y: y), to: nil)
            _ = queueClick(in: window, at: contentPoint, number: 2002)
            app.activate(ignoringOtherApps: true)
            window.makeKey()
            let focused = runApplication(until: { app.isActive && window.isKeyWindow }, timeout: 2)
            check("Classic 内容取得焦点后保留弹窗", focused && probe.controller.isOpen)
        } else { check("真实点击回归具有 Classic 内容窗口", false) }
        _ = queueClick(in: statusWindow, at: point, number: 2003)
        let closed = runApplication(until: {
            !probe.controller.isOpen && !probe.controller.isShownForTest
        }, timeout: 2)
        check("内容聚焦后的第二次点击实际执行按钮关闭动作", closed && probe.primaryCount == 2)
        let previousActions = probe.actionCount
        let previousRaw = rawEvents
        _ = queueClick(in: statusWindow, at: point, number: 2004)
        let reopened = runApplication(until: {
            probe.primaryCount == 3 && probe.controller.isOpen && probe.controller.isShownForTest
        }, timeout: 2)
        check("第三次事件到达后继续调用按钮动作并重开 Classic",
              reopened && rawEvents > previousRaw && probe.actionCount > previousActions)
        _ = queueClick(in: statusWindow, at: point, number: 2005)
        _ = runApplication(until: { !probe.controller.isOpen && !probe.controller.isShownForTest }, timeout: 2)
        for number in 2006...2009 { _ = queueClick(in: statusWindow, at: point, number: number) }
        _ = runApplication(until: { probe.primaryCount == 8 }, timeout: 2)
        spin(1.2)
        check("四次快速真实按钮动作不会留下排队的原生重开",
              probe.primaryCount == 8 && !probe.controller.isOpen && !probe.controller.isShownForTest
                  && !probe.controller.isWatchingOutsideClicks
                  && probe.controller.lifetimeObserverCountForTest == 0)
        _ = queueClick(in: statusWindow, at: point, number: 2010)
        _ = runApplication(until: { probe.controller.isOpen && probe.controller.isShownForTest }, timeout: 2)
        otherWindow.makeKeyAndOrderFront(nil)
        _ = queueClick(in: otherWindow, at: NSPoint(x: 60, y: 40), number: 2011)
        let outsideClosed = runApplication(until: {
            !probe.controller.isOpen && !probe.controller.isShownForTest
        }, timeout: 2)
        check("真实点击本进程其他窗口仍关闭 Classic", outsideClosed && outsideEvents > 0)
        _ = queueClick(in: statusWindow, at: point, number: 2012)
        let outsideReopened = runApplication(until: {
            probe.primaryCount == 10 && probe.controller.isOpen && probe.controller.isShownForTest
        }, timeout: 2)
        check("本进程外部窗口关闭后图标仍能实际重开", outsideReopened)
        otherWindow.orderOut(nil)
        probe.controller.handleOutsideClick()
        probe.controller.retireClassicHostForTest()
        spin(1.2)
        if let monitor { NSEvent.removeMonitor(monitor) }
        button.target = oldTarget
        button.action = oldAction
        button.sendAction(on: NSEvent.EventTypeMask(rawValue: UInt64(oldMask)))
    } else { check("真实点击回归具有状态窗口", false) }

    // ---- 3. 隐藏时必须停止动画：这是省电的全部意义 ----
    p.toggle(relativeTo: button); spin(0.8)
    let openAnims = p.runningAnimationCountForTest
    let openAnimationDescriptions = p.runningAnimationDescriptionsForTest
    check(forcedReduceMotion ? "减少动态效果时打开仅保留短暂淡入" : "打开时内容在动",
          forcedReduceMotion
              ? reducedMotionAnimationsAreSafe(
                  p, descriptions: openAnimationDescriptions
              )
              : openAnims > 0,
          "\(openAnims) 个动画 \(openAnimationDescriptions)")

    // 显示辅助设置会在 app 运行时变化。发送真实 workspace
    // notification，确认打开的弹窗会立即停止或恢复无限动画。
    let toggledReduceMotion = !forcedReduceMotion
    setenv("WATTSON_FORCE_REDUCE_MOTION", toggledReduceMotion ? "1" : "0", 1)
    NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
        object: NSWorkspace.shared
    )
    spin(0.05)
    let toggledAnims = p.runningAnimationCountForTest
    let toggledInfiniteAnims = p.runningInfiniteAnimationCountForTest
    check(toggledReduceMotion ? "运行中开启减少动态效果会立即停止内容动画"
                              : "运行中关闭减少动态效果会恢复内容动画",
          toggledReduceMotion ? toggledInfiniteAnims == 0 : toggledInfiniteAnims > 0,
          "\(toggledInfiniteAnims) 个无限动画，\(toggledAnims) 个总动画")
    setenv("WATTSON_FORCE_REDUCE_MOTION", forcedReduceMotion ? "1" : "0", 1)
    NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
        object: NSWorkspace.shared
    )
    spin(0.05)
    let restoredAnims = p.runningAnimationCountForTest
    let restoredInfiniteAnims = p.runningInfiniteAnimationCountForTest
    check("恢复减少动态效果设置后内容动画状态一致",
          forcedReduceMotion ? restoredInfiniteAnims == 0 : restoredInfiniteAnims > 0,
          "\(restoredInfiniteAnims) 个无限动画，\(restoredAnims) 个总动画")
    // Fallback material may cross-fade its fill for 0.25 s. It is finite and
    // allowed under Reduce Motion; let it finish before testing close cleanup.
    spin(0.3)
    p.handleOutsideClick(); spin(1.2)
    let closedAnims = p.runningAnimationCountForTest
    check("收起后动画已停", closedAnims == 0, "\(closedAnims) 个动画")
    let closedRenderCount = p.contentRenderCountForTest
    p.update(snapshot: fullSnapshot, history: [50, 52, 51], peak: 52, degraded: false)
    check("满电状态在关闭后更新仍不渲染也不重启呼吸动画",
          p.contentRenderCountForTest == closedRenderCount
              && p.runningAnimationCountForTest == 0)

    // 中途重开之后动画必须恢复——迟到的 didClose 不能把它关掉
    p.toggle(relativeTo: button); spin(0.6)
    p.toggle(relativeTo: button); spin(0.2)
    p.toggle(relativeTo: button); spin(1.4)
    let reopenAnims = p.runningAnimationCountForTest
    let reopenAnimationDescriptions = p.runningAnimationDescriptionsForTest
    check(forcedReduceMotion ? "减少动态效果时中途重开仅保留短暂淡入" : "中途重开后动画已恢复",
          forcedReduceMotion
              ? reducedMotionAnimationsAreSafe(
                  p, descriptions: reopenAnimationDescriptions
              )
              : reopenAnims > 0,
          "\(reopenAnims) 个动画 \(reopenAnimationDescriptions)")
    p.handleOutsideClick(); spin(1.2)
    check("重开再收起后动画仍会停", p.runningAnimationCountForTest == 0)

    // 连开关三轮，确认计数不漂
    for _ in 0..<3 { p.toggle(relativeTo: button); spin(0.4); p.toggle(relativeTo: button); spin(0.9) }
    p.toggle(relativeTo: button); spin(0.4)
    check("反复开关后仍能正常打开", p.isShownForTest && p.isOpen)
    p.handleOutsideClick(); spin(1.2)
    check("反复开关后仍能正常收起", !p.isShownForTest && !p.isOpen && !p.isWatchingOutsideClicks)
}

// ---- 4. 模式滑块：拖得到 High Power，松手吸附，拖动中不做多余重绘 ----
let slider = ModeSliderView(modes: [.auto, .low, .high])
let productionTrackWidth = PopoverStyle.contentWidth - 46
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: productionTrackWidth,
                                       height: ModeSliderView.preferredHeight),
                   styleMask: [.borderless], backing: .buffered, defer: false)
win.contentView = slider
slider.frame = win.contentView!.bounds
slider.update(selected: .auto, enabledModes: [.auto, .low, .high], tint: .systemBlue)
slider.layoutSubtreeIfNeeded()
// Keep a transparent composited window on the active display. A window-owned
// display link follows that display (including moves between screens) but, by
// design, does not fire for a window placed outside every screen.
win.setFrameOrigin(NSPoint(x: 20, y: 20))
win.alphaValue = 0
win.orderFrontRegardless()
spin(0.1)

var chosen: [EnergyMode] = []
slider.onSelect = { mode, completion in
    chosen.append(mode)
    completion(mode)
}

/// 驱动真实的 mouseDown/Dragged/Up，事件直接投递给视图，不经过系统注入
func drag(from startX: CGFloat, to endX: CGFloat, steps: Int) {
    func event(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: type,
                           location: NSPoint(x: x, y: ModeSliderView.preferredHeight / 2),
                           modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    slider.mouseDown(with: event(.leftMouseDown, startX))
    for i in 1...steps {
        slider.mouseDragged(with: event(.leftMouseDragged, startX + (endX - startX) * CGFloat(i) / CGFloat(steps)))
    }
    slider.mouseUp(with: event(.leftMouseUp, endX))
}

let autoCentre = slider.detentCentreForTest(0)
let lowCentre = slider.detentCentreForTest(1)
let highCentre = slider.detentCentreForTest(2)
let autoRestingFrame = slider.glassViewFrameForTest
check("静止选中片不超过一个档位的宽度",
      slider.restingKnobWidthForTest <= slider.segmentWidthForTest + 0.01,
      String(format: "选中片 %.1f，单档 %.1f",
             slider.restingKnobWidthForTest, slider.segmentWidthForTest))
check("静止 Auto 选中片与轨道上下和左边无缝贴合",
      abs(autoRestingFrame.minX - slider.bounds.minX) < 0.01
          && abs(autoRestingFrame.minY - slider.bounds.minY) < 0.01
          && abs(autoRestingFrame.maxY - slider.bounds.maxY) < 0.01,
      "选中片 \(autoRestingFrame)，轨道 \(slider.bounds)")
check("静止选中片与轨道使用同心圆角",
      abs(slider.knobCornerRadiusForTest - slider.bounds.height / 2) < 0.01
          && abs(slider.selectorCornerRadiusForTest - slider.bounds.height / 2) < 0.01,
      String(format: "host %.1f，selector %.1f，轨道 %.1f",
             slider.knobCornerRadiusForTest, slider.selectorCornerRadiusForTest,
             slider.bounds.height / 2))

let allowsNativeGlass = ProcessInfo.processInfo.environment["WATTSON_FORCE_LEGACY_KNOB"] != "1"
let expectsHighContrast = ProcessInfo.processInfo.environment["WATTSON_FORCE_INCREASE_CONTRAST"]
    .map { $0 == "1" } ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
let expectedRestingGlassOpacity: CGFloat = expectsHighContrast ? 1 : 0.045
let expectsNativeGlass: Bool
if #available(macOS 26.0, *) {
    expectsNativeGlass = allowsNativeGlass
} else {
    expectsNativeGlass = false
}
if expectsNativeGlass {
    let selectorFill = slider.nativeSelectorFillAlphaForTest ?? 0
    let nativeStructureMatches = slider.nativeTrackStyleForTest == 0
        && slider.nativeTrackHasTintForTest == false
        && slider.nativeSelectorStyleForTest == 1
        && abs((slider.nativeGlassContainerSpacingForTest ?? -1)) < 0.01
        && slider.nativeSelectorIsInsideContainerForTest == true
        && slider.nativeSelectorBorderWidthForTest == 0
        && slider.nativeSelectorHasCustomChromeForTest == false
    if ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] == "1" {
        check("原生透镜在减少透明度时由不透明高对比内容层覆盖折射",
              nativeStructureMatches
                  && selectorFill >= 0.999
                  && (slider.nativeSelectorContentFillAlphaForTest ?? 0) >= 0.999,
              "selector=\(selectorFill) "
                  + "content=\(slider.nativeSelectorContentFillAlphaForTest ?? -1)")
    } else {
        check(expectsHighContrast
                  ? "增强对比度保留 Regular/Clear 原生玻璃的完整边缘"
                  : "原生材质用 Regular 底轨与 Clear 移动透镜",
              nativeStructureMatches
                  && selectorFill <= 0.001
                  && (slider.nativeSelectorContentFillAlphaForTest ?? 1) <= 0.001
                  && abs((slider.nativeSelectorOpacityForTest ?? -1) - expectedRestingGlassOpacity) < 0.001,
              "track=\(String(describing: slider.nativeTrackStyleForTest)) "
                  + "selector=\(String(describing: slider.nativeSelectorStyleForTest)) "
                  + "fill=\(selectorFill) opacity=\(slider.nativeSelectorOpacityForTest ?? -1)")
    }
} else {
    check("旧系统路径不向普通 NSView 发送 Liquid Glass 属性",
          slider.nativeTrackStyleForTest == nil)
    if ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] == "1" {
        check("旧系统减少透明度时 selector 使用不透明填充",
              (slider.fallbackSelectorOpacityForTest ?? 0) >= 0.999,
              "alpha \(slider.fallbackSelectorOpacityForTest ?? -1)")
        check("旧系统减少透明度时不执行背景采样或折射",
              slider.fallbackLensSamplingEnabledForTest == false
                  && slider.fallbackLensSampleImageForTest == nil
                  && abs((slider.fallbackLensMagnificationForTest ?? -1) - 1) < 0.001,
              "sampling=\(String(describing: slider.fallbackLensSamplingEnabledForTest)) "
                  + "captures=\(slider.fallbackLensCaptureCountForTest)")
    } else {
        check("旧系统静止时只缓存轨道像素，不叠加折射字形",
              slider.fallbackLensSampleImageForTest != nil
                  && slider.fallbackLensSamplingEnabledForTest == false
                  && abs((slider.fallbackLensMagnificationForTest ?? -1) - 1) < 0.001,
              "sampling=\(String(describing: slider.fallbackLensSamplingEnabledForTest)) "
                  + "captures=\(slider.fallbackLensCaptureCountForTest)")
    }
}

let fallbackCaptureAtRest = slider.fallbackLensCaptureCountForTest
var fallbackFirstLiftedSample: CGRect?

// 只有真正拖动才增强玻璃材质；按下和触控板轻微抖动都维持静止形态。
do {
    func ev(_ t: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: t,
                           location: NSPoint(x: x, y: ModeSliderView.preferredHeight / 2),
                           modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    slider.mouseDown(with: ev(.leftMouseDown, autoCentre))
    if expectsNativeGlass {
        if ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] == "1" {
            check("单纯按下仍保持不透明高对比选中胶囊",
                  (slider.nativeSelectorFillAlphaForTest ?? 0) >= 0.999
                      && (slider.nativeSelectorContentFillAlphaForTest ?? 0) >= 0.999
                      && slider.nativeSelectorBorderWidthForTest == 0
                      && slider.nativeSelectorHasCustomChromeForTest == false)
        } else {
            check("单纯按下不改变中性选中胶囊",
                  (slider.nativeSelectorFillAlphaForTest ?? 1) <= 0.001
                      && (slider.nativeSelectorContentFillAlphaForTest ?? 1) <= 0.001
                      && slider.nativeSelectorBorderWidthForTest == 0
                      && slider.nativeSelectorHasCustomChromeForTest == false)
        }
    }
    let pressed = slider.knobScaleForTest
    check("单纯按下不放大",
          abs(pressed.width - 1) < 0.01 && abs(pressed.height - 1) < 0.01,
          String(format: "%.2f × %.2f", pressed.width, pressed.height))

    slider.mouseDragged(with: ev(.leftMouseDragged, autoCentre + 2))
    let wobble = slider.knobScaleForTest
    check("小于拖动阈值的抖动仍不放大",
          abs(wobble.width - 1) < 0.01 && abs(wobble.height - 1) < 0.01,
          String(format: "%.2f × %.2f", wobble.width, wobble.height))

    slider.mouseDragged(with: ev(.leftMouseDragged, autoCentre + 6))
    let dragged = slider.knobScaleForTest
    if expectsNativeGlass {
        let liftedFill = slider.nativeSelectorFillAlphaForTest ?? 0
        if ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] == "1" {
            check("减少透明度时拖动仍保持不透明高对比透镜",
                  liftedFill >= 0.999
                      && (slider.nativeSelectorContentFillAlphaForTest ?? 0) >= 0.999)
        } else {
            let expectedDragOpacity: CGFloat = expectsHighContrast
                ? 1 : (slider.reducesMotionForTest ? 0.045 : 0.14)
            check(expectsHighContrast
                      ? "增强对比度拖动仍保持完整的原生 Clear 玻璃边缘"
                      : "开始拖动后 Clear 折射透镜仍保持原生材质",
                  liftedFill <= 0.001
                      && (slider.nativeSelectorContentFillAlphaForTest ?? 1) <= 0.001
                      && abs((slider.nativeSelectorOpacityForTest ?? -1) - expectedDragOpacity) < 0.001
                      && slider.nativeSelectorStyleForTest == 1
                      && slider.nativeSelectorBorderWidthForTest == 0
                      && slider.nativeSelectorHasCustomChromeForTest == false)
        }
        slider.update(selected: .auto,
                      enabledModes: [.auto, .low, .high],
                      tint: .systemBlue)
        check("拖动中的 1 Hz 刷新不会压平浮起材质",
              abs((slider.nativeSelectorFillAlphaForTest ?? 0) - liftedFill) < 0.001,
              "刷新前 \(liftedFill)，刷新后 \(slider.nativeSelectorFillAlphaForTest ?? -1)")
    } else if !slider.reducesMotionForTest
                && ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] != "1" {
        fallbackFirstLiftedSample = slider.fallbackLensSampleRectForTest
        check("旧系统只在越过拖动阈值后开启真实像素折射",
              slider.fallbackLensSamplingEnabledForTest == true
                  && slider.fallbackLensSampleImageForTest != nil
                  && abs((slider.fallbackLensMagnificationForTest ?? -1) - 1.105) < 0.001,
              "sampling=\(String(describing: slider.fallbackLensSamplingEnabledForTest)) "
                  + "magnification=\(slider.fallbackLensMagnificationForTest ?? -1)")
    }
    check("拖动期间始终保持静止态尺寸",
          abs(dragged.width - 1) < 0.01 && abs(dragged.height - 1) < 0.01,
          String(format: "%.2f × %.2f", dragged.width, dragged.height))
    slider.mouseDragged(with: ev(.leftMouseDragged, (autoCentre + lowCentre) / 2))
    if let first = fallbackFirstLiftedSample {
        let moved = slider.fallbackLensSampleRectForTest ?? .zero
        check("旧系统透镜跟随拖动移动采样区且不逐帧截图",
              moved.midX > first.midX + 0.08
                  && slider.fallbackLensCaptureCountForTest == fallbackCaptureAtRest,
              "first=\(first) moved=\(moved) "
                  + "captures=\(slider.fallbackLensCaptureCountForTest)")
    }
    let midpointBlend = slider.activeLabelOpacitiesForTest
    check("拖到两档正中时两侧文字各约一半亮度",
          midpointBlend.count == 3
              && abs(midpointBlend[0] - 0.5) < 0.06
              && abs(midpointBlend[1] - 0.5) < 0.06
              && midpointBlend[2] < 0.02,
          "\(midpointBlend)")
    slider.mouseDragged(with: ev(.leftMouseDragged, autoCentre + 6))
    check("拖动预览不会提前提交系统模式", chosen.isEmpty, "\(chosen)")
    slider.mouseUp(with: ev(.leftMouseUp, autoCentre + 6))
    if expectsNativeGlass {
        if ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] == "1" {
            check("释放后选中胶囊回到不透明高对比静止材质",
                  (slider.nativeSelectorFillAlphaForTest ?? 0) >= 0.999
                      && (slider.nativeSelectorContentFillAlphaForTest ?? 0) >= 0.999
                      && slider.nativeSelectorBorderWidthForTest == 0
                      && slider.nativeSelectorHasCustomChromeForTest == false)
        } else {
            check("释放后选中胶囊回到中性静止材质",
                  (slider.nativeSelectorFillAlphaForTest ?? 1) <= 0.001
                      && (slider.nativeSelectorContentFillAlphaForTest ?? 1) <= 0.001
                      && slider.nativeSelectorBorderWidthForTest == 0
                      && slider.nativeSelectorHasCustomChromeForTest == false)
        }
    } else {
        check("旧系统释放后关闭折射，不让模型裁剪与呈现层动画错位",
              slider.fallbackLensSamplingEnabledForTest == false
                  && abs((slider.fallbackLensMagnificationForTest ?? -1) - 1) < 0.001)
    }
    spin(0.3)
    if expectsNativeGlass,
       ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] != "1" {
        check(expectsHighContrast
                  ? "增强对比度吸附后保留原生边缘且不叠加自绘底色"
                  : "吸附完成后恢复近乎透明的静止玻璃",
              abs((slider.nativeSelectorOpacityForTest ?? -1) - expectedRestingGlassOpacity) < 0.001
                  && (slider.nativeSelectorFillAlphaForTest ?? 1) <= 0.001
                  && (slider.nativeSelectorContentFillAlphaForTest ?? 1) <= 0.001
                  && slider.nativeSelectorStyleForTest == 1
                  && slider.nativeSelectorBorderWidthForTest == 0
                  && slider.nativeSelectorHasCustomChromeForTest == false,
              "opacity=\(slider.nativeSelectorOpacityForTest ?? -1)")
    }
}

let before = slider.highlightCallCountForTest
let highReleaseCentre = highCentre - 18
drag(from: autoCentre, to: highReleaseCentre, steps: 60)
let relabels = slider.highlightCallCountForTest - before
check("拖到最右会选中 High Power", chosen.last == .high, "\(chosen)")
if slider.reducesMotionForTest {
    check("减少动态效果时释放直接吸附且不添加弹簧",
          !slider.settleIsAnimatingForTest
              && abs(slider.knobCentreForTest - highCentre) < 0.5)
} else {
    check("非精确落点松手仍有吸附弹簧动画",
          slider.settleIsAnimatingForTest
              && slider.settleUsesSpringForTest
              && (slider.settleDurationForTest ?? 1) <= 0.24
              && abs((slider.settleStartCentreForTest ?? .infinity) - highReleaseCentre) < 1.5)
}
// 60 次拖动事件里只该跨过 1 个档位；每帧都重着色正是当初卡顿的原因
check("拖动 60 帧只重着色跨档的那几次", relabels <= 3, "\(relabels) 次")
spin(0.6)
check("松手后吸附到 High 档位",
      abs(slider.knobCentreForTest - highCentre) < 0.5,
      String(format: "旋钮 %.1f vs 档位 %.1f", slider.knobCentreForTest, highCentre))

let backBefore = slider.highlightCallCountForTest
drag(from: highCentre, to: lowCentre, steps: 60)
check("能一路拖回 Low Power", chosen.last == .low, "\(chosen)")
check("拖回后吸附到 Low 档位",
      abs(slider.knobCentreForTest - lowCentre) < 0.5)
check("回程同样不逐帧重着色", slider.highlightCallCountForTest - backBefore <= 3)
spin(0.3)

// 不支持 High Power 的机器上，拖过去必须停在最近的可用档位 Low
let limited = ModeSliderView(modes: [.auto, .low, .high])
let win2 = NSWindow(contentRect: win.contentRect(forFrameRect: win.frame), styleMask: [.borderless],
                    backing: .buffered, defer: false)
win2.contentView = limited
limited.frame = win2.contentView!.bounds
limited.update(selected: .auto, enabledModes: [.auto, .low], tint: .systemBlue)
limited.layoutSubtreeIfNeeded(); spin(0.1)
var limitedChosen: [EnergyMode] = []
limited.onSelect = { mode, completion in
    limitedChosen.append(mode)
    completion(mode)
}
do {
    func ev(_ t: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: t, location: NSPoint(x: x, y: ModeSliderView.preferredHeight / 2),
                           modifierFlags: [], timestamp: 0, windowNumber: win2.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    limited.mouseDown(with: ev(.leftMouseDown, limited.detentCentreForTest(0)))
    for i in 1...30 { limited.mouseDragged(with: ev(.leftMouseDragged, limited.detentCentreForTest(0) + CGFloat(i) * 6)) }
    limited.mouseUp(with: ev(.leftMouseUp, limited.bounds.maxX - 4))
}
check("不支持 High 时拖过去停在最近可用的 Low",
      limitedChosen.last == .low && limited.selectedIndexForTest == 1,
      "选中索引 \(limited.selectedIndexForTest) 回调 \(limitedChosen)")

// ---- 5. 点击/轻触档位，不只是拖动 ----
/// 按下即抬起，中间没有移动——触控板单指轻触就是这个形状
func tap(_ view: ModeSliderView, in window: NSWindow, atX x: CGFloat, wobble: CGFloat = 0) {
    func ev(_ t: NSEvent.EventType, _ px: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: t, location: NSPoint(x: px, y: ModeSliderView.preferredHeight / 2),
                           modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    view.mouseDown(with: ev(.leftMouseDown, x))
    if wobble != 0 { view.mouseDragged(with: ev(.leftMouseDragged, x + wobble)) }
    view.mouseUp(with: ev(.leftMouseUp, x + wobble))
}

// 命中测试必须回到控件本身，否则 AppKit 会去问一个说 false 的装饰视图
let hit = slider.hitTest(NSPoint(x: 40, y: ModeSliderView.preferredHeight / 2))
check("滑块命中测试返回自身而非装饰子视图",
      hit === slider, "\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
let offsetContainer = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
let offsetSlider = ModeSliderView(modes: [.auto, .low, .high])
offsetSlider.frame = NSRect(x: 18, y: 36, width: 300, height: ModeSliderView.preferredHeight)
offsetContainer.addSubview(offsetSlider)
let offsetHitPoint = NSPoint(x: offsetSlider.frame.minX + 40,
                             y: offsetSlider.frame.minY + ModeSliderView.preferredHeight / 2)
check("滑块放在 footer 的实际偏移位置仍能命中",
      offsetContainer.hitTest(offsetHitPoint) === offsetSlider)
check("滑块偏移后的 frame 外不会误命中",
      offsetContainer.hitTest(NSPoint(x: offsetSlider.frame.minX + 40,
                                      y: offsetSlider.frame.maxY + 4)) !== offsetSlider)
check("滑块接受 first mouse", slider.acceptsFirstMouse(for: nil))
check("鼠标与键盘操作都不会绘制整条蓝色焦点外框",
      slider.focusRingTypeForTest == .none)

// 此刻旋钮在 Low（上一段拖回去了）
chosen.removeAll()
tap(slider, in: win, atX: slider.detentCentreForTest(2))
check("点击 High Power 档位会切过去", chosen.last == .high, "\(chosen)")
if slider.reducesMotionForTest {
    check("减少动态效果时点击直接切换",
          !slider.settleIsAnimatingForTest
              && abs(slider.glassViewCentreForTest - highCentre) < 0.5)
} else {
    check("点击第一帧真实玻璃仍留在 Low，目标文字不会抢先亮",
          abs(slider.glassViewCentreForTest - lowCentre) < 2
              && slider.activeLabelOpacitiesForTest[1] > 0.90
              && slider.activeLabelOpacitiesForTest[2] < 0.10,
          "玻璃 \(slider.glassViewCentreForTest)，文字 \(slider.activeLabelOpacitiesForTest)")
    check("点击换档使用磁吸流动而非拖拽弹簧或瞬移",
          slider.settleIsAnimatingForTest
              && slider.settleUsesMagneticFlowForTest
              && !slider.settleUsesSpringForTest
              && (!expectsNativeGlass || !slider.nativeSettleUsesHostLayerAnimationForTest))
    spin(0.10)
    let visibleCentre = slider.glassViewCentreForTest
    let visibleGlassFrame = slider.glassViewFrameForTest
    let visibleSelectorFrame = slider.nativeSelectorFrameInSliderForTest
    let visibleScale = slider.knobPresentationScaleForTest
    check("点击后原生玻璃沿磁吸路径前进且不越过捕获范围",
          visibleCentre > lowCentre + 3 && visibleCentre <= highCentre + 4,
          String(format: "玻璃位置 %.1f，起点 %.1f，终点 %.1f",
                 visibleCentre, lowCentre, highCentre))
    check("点击磁吸全程不进入拖动放大态",
          visibleScale.width <= 1.001 && visibleScale.height <= 1.001,
          String(format: "%.3f × %.3f", visibleScale.width, visibleScale.height))
    if expectsNativeGlass, let visibleSelectorFrame {
        check("点击迁移时原生玻璃与 selector 边界逐帧同步",
              abs(visibleSelectorFrame.minX - visibleGlassFrame.minX) < 0.5
                  && abs(visibleSelectorFrame.minY - visibleGlassFrame.minY) < 0.5
                  && abs(visibleSelectorFrame.width - visibleGlassFrame.width) < 0.5
                  && abs(visibleSelectorFrame.height - visibleGlassFrame.height) < 0.5,
              "glass=\(visibleGlassFrame) selector=\(visibleSelectorFrame)")
    }
    let visibleBlend = slider.activeLabelPresentationOpacitiesForTest
    let expectedLowBlend = min(max(
        1 - abs(lowCentre - visibleCentre) / slider.segmentWidthForTest, 0
    ), 1)
    let expectedHighBlend = min(max(
        1 - abs(highCentre - visibleCentre) / slider.segmentWidthForTest, 0
    ), 1)
    check("点击移动中文字亮度随玻璃位置连续交叉渐变",
          visibleBlend.count == 3
              && visibleBlend[0] < 0.02
              && abs(visibleBlend[1] - expectedLowBlend) < 0.15
              && abs(visibleBlend[2] - expectedHighBlend) < 0.15,
          "\(visibleBlend)")
}
spin(0.5)
check("点击动画最终精确吸附到 High",
      abs(slider.glassViewCentreForTest - highCentre) < 0.5)
let highRestingFrame = slider.glassViewFrameForTest
check("静止 High 选中片与轨道上下和右边无缝贴合",
      abs(highRestingFrame.maxX - slider.bounds.maxX) < 0.01
          && abs(highRestingFrame.minY - slider.bounds.minY) < 0.01
          && abs(highRestingFrame.maxY - slider.bounds.maxY) < 0.01,
      "选中片 \(highRestingFrame)，轨道 \(slider.bounds)")

// 用户现场路径：当前在 High，直接点击最左侧 Auto。真实玻璃必须反向
// 穿过 Low；layout 与同档 1 Hz update 不能把它提前推到模型层终点。
chosen.removeAll()
slider.resetLabelBlendTraceForTest()
tap(slider, in: win, atX: autoCentre)
check("High 直接点击 Auto 会提交 Auto", chosen.last == .auto, "\(chosen)")
if slider.reducesMotionForTest {
    check("减少动态效果时 High 到 Auto 直接切换",
          abs(slider.glassViewCentreForTest - autoCentre) < 0.5)
} else {
    check("High 到 Auto 第一帧真实玻璃仍在 High",
          abs(slider.glassViewCentreForTest - highCentre) < 2,
          String(format: "%.1f vs %.1f", slider.glassViewCentreForTest, highCentre))
    let beforeRefresh = slider.glassViewCentreForTest
    slider.layoutSubtreeIfNeeded()
    slider.update(selected: .auto, enabledModes: [.auto, .low, .high], tint: .systemBlue)
    check("布局与 1 Hz 更新不会把真实玻璃抢先推到 Auto",
          slider.settleIsAnimatingForTest
              && abs(slider.glassViewCentreForTest - beforeRefresh) < 3
              && slider.glassViewCentreForTest > autoCentre + 3,
          String(format: "刷新前 %.1f，刷新后 %.1f",
                 beforeRefresh, slider.glassViewCentreForTest))
    spin(0.10)
    check("High 到 Auto 的真实玻璃沿反向路径前进",
          slider.glassViewCentreForTest < beforeRefresh - 3
              && slider.glassViewCentreForTest >= autoCentre - 4,
          String(format: "%.1f，终点 %.1f...%.1f",
                 slider.glassViewCentreForTest, autoCentre, highCentre))
}
spin(0.5)
let reverseMiddlePeak = slider.labelBlendTraceForTest.compactMap { weights in
    weights.count == 3 ? weights[1] : nil
}.max() ?? 0
check("High 到 Auto 会经过 Low 且文字随真实玻璃渐亮",
      abs(slider.glassViewCentreForTest - autoCentre) < 0.5
          && (slider.reducesMotionForTest || reverseMiddlePeak > 0.75),
      String(format: "终点 %.1f，Low 峰值 %.3f",
             slider.glassViewCentreForTest, reverseMiddlePeak))

chosen.removeAll()
tap(slider, in: win, atX: slider.detentCentreForTest(1))
check("点击 Low Power 档位会切回来", chosen.last == .low, "\(chosen)")
spin(0.6)

// 轻触难免抖一两个像素，仍应是点击而不是把旋钮推一下又弹回原位
chosen.removeAll()
tap(slider, in: win, atX: slider.detentCentreForTest(0), wobble: 2)
check("轻触抖动 2pt 仍按点击处理", chosen.last == .auto, "\(chosen)")
spin(0.6)

// 点在已选中的档位上不该触发回调
chosen.removeAll()
tap(slider, in: win, atX: slider.detentCentreForTest(0))
check("点击当前档位不重复触发", chosen.isEmpty, "\(chosen)")

// 点在档位之间偏向哪边就选哪边
chosen.removeAll()
let between = (slider.detentCentreForTest(1) + slider.detentCentreForTest(2)) / 2 + 8
slider.resetLabelBlendTraceForTest()
tap(slider, in: win, atX: between)
check("点在两档之间选更近的一个", chosen.last == .high, "\(chosen)")
var middleLabelPeak: CGFloat = 0
var closestToMiddle = CGFloat.greatestFiniteMagnitude
let middlePeakDeadline = Date().addingTimeInterval(0.70)
while Date() < middlePeakDeadline {
    spin(0.005)
    closestToMiddle = min(closestToMiddle,
                          abs(slider.knobPresentationCentreForTest - lowCentre))
    let opacities = slider.activeLabelPresentationOpacitiesForTest
    if opacities.count == 3 { middleLabelPeak = max(middleLabelPeak, opacities[1]) }
}
let appliedMiddlePeak = slider.labelBlendTraceForTest.compactMap { weights in
    weights.count == 3 ? weights[1] : nil
}.max() ?? 0
let directMotionCentres = slider.magneticMotionCentresForTest(from: 0, to: 2)
check("Auto 直接点 High 的连续轨迹精确经过 Low 中心",
      directMotionCentres.contains(where: { abs($0 - lowCentre) < 0.01 })
          && (slider.reducesMotionForTest || appliedMiddlePeak > 0.99),
      String(format: "Low 亮度峰值 %.3f", appliedMiddlePeak))
if slider.reducesMotionForTest {
    check("减少动态效果时 Auto 直接落到 High",
          abs(slider.glassViewCentreForTest - highCentre) < 1)
} else {
    check("离屏降帧时仍能看到 Low 渐亮并最终落到 High",
          middleLabelPeak > 0.45
              && appliedMiddlePeak > 0.45
              && abs(slider.glassViewCentreForTest - highCentre) < 1,
          String(format: "呈现峰值 %.3f，计算峰值 %.3f，最近 %.1fpt，终点 %.1f",
                 middleLabelPeak, appliedMiddlePeak, closestToMiddle,
                 slider.glassViewCentreForTest))
}
spin(0.1)

// 从 Auto 直接点禁用的 High 也必须没有反应；不能偷偷映射到相邻的 Low
limited.update(selected: .auto, enabledModes: [.auto, .low], tint: .systemBlue)
limitedChosen.removeAll()
tap(limited, in: win2, atX: limited.detentCentreForTest(2))
check("不支持 High 时点它无效",
      limitedChosen.isEmpty && limited.selectedIndexForTest == 0,
      "选中索引 \(limited.selectedIndexForTest) 回调 \(limitedChosen)")

// 系统拒绝切换时控件必须回到真实档位，不能只在视觉上假装成功
var rejected: [EnergyMode] = []
slider.onSelect = { mode, completion in
    rejected.append(mode)
    completion(.high)
}
tap(slider, in: win, atX: lowCentre)
check("切换失败后回弹到原档位",
      rejected == [.low]
          && slider.selectedIndexForTest == 2
          && abs(slider.knobCentreForTest - highCentre) < 0.5,
      "选中索引 \(slider.selectedIndexForTest) 回调 \(rejected)")

// helper 回读可以稍后完成；期间 1 Hz 外部刷新不能把乐观预览拽回去。
var delayedMode: EnergyMode?
var delayedCompletion: ((EnergyMode?) -> Void)?
slider.onSelect = { mode, completion in
    delayedMode = mode
    delayedCompletion = completion
}
tap(slider, in: win, atX: lowCentre)
check("模式写入期间控件保持目标档位且不阻塞",
      delayedMode == .low && slider.selectionIsPendingForTest && slider.selectedIndexForTest == 1)
slider.update(selected: .high, enabledModes: [.auto, .low, .high], tint: .systemBlue)
check("拖动后的 1 Hz 刷新不覆盖待确认预览", slider.selectedIndexForTest == 1)
delayedCompletion?(.low)
check("异步确认后目标档位成为已提交状态",
      !slider.selectionIsPendingForTest && slider.selectedIndexForTest == 1)

// A 已落地、B 被拒绝时，B 必须回到真实的 A，不能回到两次请求前的旧档。
var racedSelections: [(mode: EnergyMode, completion: (EnergyMode?) -> Void)] = []
slider.onSelect = { mode, completion in
    racedSelections.append((mode, completion))
}
tap(slider, in: win, atX: highCentre)
tap(slider, in: win, atX: autoCentre)
check("连续选择会各自排队且最后一次保持待确认",
      racedSelections.map(\.mode) == [.high, .auto]
          && slider.selectionIsPendingForTest
          && slider.selectedIndexForTest == 0)
racedSelections[0].completion(.high)
check("较旧写入的迟到回调不会覆盖最新预览",
      slider.selectionIsPendingForTest && slider.selectedIndexForTest == 0)
racedSelections[1].completion(.high)
check("A 成功而 B 失败时回到实际落地的 A",
      !slider.selectionIsPendingForTest && slider.selectedIndexForTest == 2)
spin(0.4)

// 合成层动画中重新抓取必须从屏幕上的实际位置继续，不能跳到 model 终点。
slider.onSelect = { mode, completion in completion(mode) }
tap(slider, in: win, atX: autoCentre)
spin(0.075)
let centreBeforeRegrab = slider.glassViewCentreForTest
do {
    func ev(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: type,
                           location: NSPoint(x: x, y: ModeSliderView.preferredHeight / 2),
                           modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    slider.mouseDown(with: ev(.leftMouseDown, centreBeforeRegrab))
    check("动画中重新抓取不发生位置跳变",
          abs(slider.knobCentreForTest - centreBeforeRegrab) < 1
              && !slider.settleIsAnimatingForTest,
          String(format: "抓取前 %.2f，抓取后 %.2f",
                 centreBeforeRegrab, slider.knobCentreForTest))
    slider.mouseUp(with: ev(.leftMouseUp, centreBeforeRegrab))
}
spin(0.4)

// helper 在动画途中拒绝写入时，回滚也必须从当前 presentation 开始。
slider.update(selected: .high, enabledModes: [.auto, .low, .high], tint: .systemBlue)
spin(0.35)
var rejectionCompletion: ((EnergyMode?) -> Void)?
slider.onSelect = { _, completion in rejectionCompletion = completion }
tap(slider, in: win, atX: autoCentre)
spin(0.08)
let centreBeforeRejection = slider.glassViewCentreForTest
rejectionCompletion?(.high)
let centreAfterRejection = slider.glassViewCentreForTest
if slider.reducesMotionForTest {
    check("减少动态效果时失败回滚直接落到真实档位",
          abs(centreBeforeRejection - autoCentre) < 0.5
              && abs(centreAfterRejection - highCentre) < 0.5
              && !slider.settleIsAnimatingForTest)
} else {
    let rejectionPath = slider.magneticMotionCentresForTest(from: 2, to: 0)
    check("动画中失败回滚从当前可见位置反向启动",
          centreBeforeRejection >= (rejectionPath.min() ?? autoCentre) - 0.5
              && centreBeforeRejection <= (rejectionPath.max() ?? highCentre) + 0.5
              && abs(centreAfterRejection - centreBeforeRejection) < 1
              && slider.settleIsAnimatingForTest,
          String(format: "拒绝前 %.2f，回滚起点 %.2f",
                 centreBeforeRejection, centreAfterRejection))
}
spin(0.4)
check("动画中失败最终回到真实档位",
      abs(slider.glassViewCentreForTest - highCentre) < 0.5)

// 键盘与 VoiceOver 走同一条提交路径，并跳过不可用档位。
let accessible = ModeSliderView(modes: [.auto, .low, .high])
accessible.frame = NSRect(x: 0, y: 0, width: 300, height: ModeSliderView.preferredHeight)
accessible.update(selected: .auto, enabledModes: [.auto, .low], tint: .systemBlue)
accessible.layoutSubtreeIfNeeded()
var accessibleSelections: [EnergyMode] = []
accessible.onSelect = { mode, completion in
    accessibleSelections.append(mode)
    completion(mode)
}
check("模式滑块向 VoiceOver 暴露单一可调控件",
      accessible.isAccessibilityElement()
          && accessible.accessibilityRole() == .slider
          && accessible.accessibilityValueDescription() == EnergyMode.auto.title)
check("VoiceOver 增量可切到下一可用档",
      accessible.accessibilityPerformIncrement()
          && accessibleSelections == [.low]
          && accessible.selectedIndexForTest == 1)
check("VoiceOver 不会进入禁用的 High Power",
      !accessible.accessibilityPerformIncrement() && accessible.selectedIndexForTest == 1)
let leftArrow = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                 timestamp: 0, windowNumber: 0, context: nil,
                                 characters: "", charactersIgnoringModifiers: "",
                                 isARepeat: false, keyCode: 123)!
accessible.keyDown(with: leftArrow)
check("键盘左箭头与可访问性动作使用同一切换路径",
      accessibleSelections == [.low, .auto] && accessible.selectedIndexForTest == 0)

// ---- 6. 粒子池复用：几何变化只换路径，不换 layer 也不重启相位 ----
let pipe = PipeBundle()
let pipeBounds = CGRect(x: 0, y: 0, width: 328, height: 176)
let firstGeometry = PipeGeometry(
    start: CGPoint(x: 53, y: 70), control1: CGPoint(x: 138, y: 70),
    control2: CGPoint(x: 190, y: 38), end: CGPoint(x: 275, y: 38)
)
let movedGeometry = PipeGeometry(
    start: CGPoint(x: 53, y: 64), control1: CGPoint(x: 138, y: 64),
    control2: CGPoint(x: 190, y: 32), end: CGPoint(x: 275, y: 32)
)
pipe.apply(geometry: firstGeometry, thickness: 8, color: .systemBlue,
           bounds: pipeBounds, animated: false)
pipe.rebuildParticles(count: 4, thickness: 8, color: .systemBlue,
                      period: 2.4, seed: 11, hot: false,
                      animating: true, topology: "test.same")
let firstLayers = Array((pipe.container.sublayers ?? []).dropFirst(2))
let firstRideStarts = firstLayers.compactMap {
    ($0.animation(forKey: "ride") as? CAKeyframeAnimation)?.path?.currentPoint.y
}
let firstBeginTimes = firstLayers.compactMap {
    ($0.animation(forKey: "ride") as? CAKeyframeAnimation)?.beginTime
}
let firstTimeOffsets = firstLayers.compactMap {
    ($0.animation(forKey: "ride") as? CAKeyframeAnimation)?.timeOffset
}

pipe.apply(geometry: movedGeometry, thickness: 8, color: .systemBlue,
           bounds: pipeBounds, animated: false)
pipe.rebuildParticles(count: 4, thickness: 8, color: .systemBlue,
                      period: 2.4, seed: 11, hot: false,
                      animating: true, topology: "test.same")
let movedLayers = Array((pipe.container.sublayers ?? []).dropFirst(2))
let movedRideStarts = movedLayers.compactMap {
    ($0.animation(forKey: "ride") as? CAKeyframeAnimation)?.path?.currentPoint.y
}
let movedBeginTimes = movedLayers.compactMap {
    ($0.animation(forKey: "ride") as? CAKeyframeAnimation)?.beginTime
}
let movedTimeOffsets = movedLayers.compactMap {
    ($0.animation(forKey: "ride") as? CAKeyframeAnimation)?.timeOffset
}
check("同拓扑几何变化保留粒子 layer",
      firstLayers.count == movedLayers.count
          && zip(firstLayers, movedLayers).allSatisfy { $0 === $1 })
let expectedStartDelta = movedGeometry.start.y - firstGeometry.start.y
check("复用粒子的 ride path 跟随新几何",
      firstRideStarts.count == movedRideStarts.count
          && zip(firstRideStarts, movedRideStarts).allSatisfy {
              abs(($1 - $0) - expectedStartDelta) < 0.01
          },
      "\(firstRideStarts) -> \(movedRideStarts)")
check("更新路径不重启粒子相位",
      firstBeginTimes == movedBeginTimes && firstTimeOffsets == movedTimeOffsets)

// ---- 7. 功率泳道：亮峰贯穿全宽，1 Hz 改宽/改速不重启相位 ----
let laneView = LaneView()
let laneWindow = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                               width: PopoverStyle.contentWidth,
                                               height: LaneView.preferredHeight),
                          styleMask: [.borderless], backing: .buffered, defer: false)
laneWindow.contentView = laneView
laneView.frame = laneWindow.contentView!.bounds
laneView.layoutSubtreeIfNeeded()
laneView.update(snapshot: PowerSnapshot(percent: 72, plugged: true, adapterW: 68,
                                        batteryW: 22.2, systemW: 45.8,
                                        temperatureC: 34.2, cycleCount: 116,
                                        lowPowerMode: false))
laneView.setAnimationsEnabled(true)
guard let firstLane = laneView.sweepMetricsForTest(at: 1) else {
    log("❌ 无法读取泳道扫光动画")
    exit(1)
}
check("泳道扫光行程覆盖整个填充条",
      abs(firstLane.travel - firstLane.fillWidth * 2) < 0.01,
      String(format: "行程 %.1f，填充宽 %.1f", firstLane.travel, firstLane.fillWidth))

laneView.update(snapshot: PowerSnapshot(percent: 72, plugged: true, adapterW: 80,
                                        batteryW: 34.2, systemW: 45.8,
                                        temperatureC: 34.2, cycleCount: 116,
                                        lowPowerMode: false))
guard let changedLane = laneView.sweepMetricsForTest(at: 1) else {
    log("❌ 无法读取改宽后的泳道扫光动画")
    exit(1)
}
check("泳道宽度变化后更新行程但不重启相位",
      changedLane.fillWidth > firstLane.fillWidth
          && abs(changedLane.travel - changedLane.fillWidth * 2) < 0.01
          && changedLane.beginTime == firstLane.beginTime)
check("总功率变化会重定时现有泳道动画",
      abs(changedLane.layerSpeed - firstLane.layerSpeed) > 0.005)

// ---- 8. 三个模块的非粒子运动共享同一功率节奏 ----
let sharedMotionSnapshot = PowerSnapshot(
    percent: 72, plugged: true, adapterW: 68, batteryW: 22.2, systemW: 45.8,
    temperatureC: 34.2, cycleCount: 116, lowPowerMode: false
)
let flowView = PowerFlowView()
flowView.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                        height: PowerFlowView.preferredHeight)
flowView.layoutSubtreeIfNeeded()
flowView.update(snapshot: sharedMotionSnapshot, animated: false)
flowView.setAnimationsEnabled(true)

Settings.ringMetrics = Settings.defaultRingMetrics
let ringView = RingGaugeView()
ringView.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                        height: RingGaugeView.preferredHeight)
ringView.layoutSubtreeIfNeeded()
let baselineRingFrames = ringView.visibleReadingFramesForTest

func ringPresentationMatches(_ snapshot: PowerSnapshot,
                             caption: String, value: String) -> Bool {
    ringView.update(snapshot: snapshot)
    let trailing = ringView.trailingReadingForTest
    let accessibilityChildren = ringView.accessibilityChildren() ?? []
    let trailingElements = accessibilityChildren.compactMap { $0 as? NSTextField }
        .filter { $0.accessibilityLabel() == caption }
    return trailing.caption == caption
        && trailing.value == value
        && accessibilityChildren.compactMap { $0 as? NSTextField }.count == 4
        && trailingElements.count == 1
        && trailingElements.first?.accessibilityRole() == .staticText
        && trailingElements.first?.accessibilityValue() == value
        && ringView.visibleReadingFramesForTest.count == 8
        && ringView.visibleReadingFramesForTest == baselineRingFrames
        && ringView.statsFitBoundsForTest
}

check("默认显示循环次数并保留原四格布局",
      RingGaugeView.preferredHeight == 138
          && ringView.bounds.height == 138
          && baselineRingFrames.count == 8
          && ringPresentationMatches(sharedMotionSnapshot,
                                     caption: "Cycle Count", value: "116"))

var measuredDeviceOutput = sharedMotionSnapshot
measuredDeviceOutput.deviceOutputW = 7.5
check("设备实测输出不会自动覆盖已选循环次数",
      ringPresentationMatches(measuredDeviceOutput,
                              caption: "Cycle Count", value: "116"))
Settings.ringMetrics = [.systemLoad, .batteryPower, .temperature, .deviceOutput]
ringView.reloadMetrics()
ringView.layoutSubtreeIfNeeded()
check("选择外接设备输出后显示实测标签和功率",
      ringPresentationMatches(measuredDeviceOutput,
                              caption: "Device Output", value: "7.5 W"))

var measuredZeroDeviceOutput = sharedMotionSnapshot
measuredZeroDeviceOutput.deviceOutputW = 0
check("实测零输出与不可用数据保持可区分",
      ringPresentationMatches(measuredZeroDeviceOutput,
                              caption: "Device Output", value: "0.0 W"))

check("选择的输出数据变为不可用时显示破折号",
      ringPresentationMatches(sharedMotionSnapshot,
                              caption: "Device Output", value: "—"))
Settings.ringMetrics = Settings.defaultRingMetrics
ringView.reloadMetrics()
ringView.layoutSubtreeIfNeeded()
check("恢复默认指标后显示循环次数",
      ringPresentationMatches(sharedMotionSnapshot,
                              caption: "Cycle Count", value: "116"))
ringView.setAnimationsEnabled(true)

laneView.update(snapshot: sharedMotionSnapshot)
guard let flowMotion = flowView.flowMetricsForTest(),
      let ringMotion = ringView.rotationMetricsForTest(),
      let laneMotion = laneView.sweepMetricsForTest(at: 0) else {
    log("❌ 无法读取三个模块的共享运动动画")
    exit(1)
}
check("三模块非粒子动画使用同一基准周期",
      abs(flowMotion.duration - ringMotion.duration) < 0.001
          && abs(flowMotion.duration - laneMotion.duration) < 0.001)
check("三模块非粒子动画使用同一功率倍率",
      abs(flowMotion.layerSpeed - ringMotion.layerSpeed) < 0.005
          && abs(flowMotion.layerSpeed - laneMotion.layerSpeed) < 0.005)

// ---- 9. 紧凑顶栏覆盖所有供电状态，不截断也不越界 ----
let header = PopoverHeaderView()
header.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                      height: PopoverHeaderView.preferredHeight)
let headerSnapshots = [
    PowerSnapshot(percent: 72, plugged: true, adapterW: 68, batteryW: 22.2,
                  systemW: 45.8, temperatureC: 34.2, cycleCount: 116),
    PowerSnapshot(percent: 100, plugged: true, adapterW: 52, batteryW: 0,
                  systemW: 52, temperatureC: 31.8, cycleCount: 116,
                  batteryTimeEstimate: .full, batteryTimeEstimateSource: .system),
    PowerSnapshot(percent: 41, plugged: false, adapterW: 0, batteryW: -36.9,
                  systemW: 36.9, temperatureC: 33.1, cycleCount: 116),
    PowerSnapshot(percent: 18, plugged: true, adapterW: 28, batteryW: -31.7,
                  systemW: 59.7, temperatureC: 38.6, cycleCount: 116),
    PowerSnapshot(percent: 18, plugged: true, adapterW: 28, batteryW: -31.7,
                  systemW: 70, temperatureC: 38.6, cycleCount: 116),
    PowerSnapshot(percent: 66, plugged: true, adapterW: 140, batteryW: 32,
                  systemW: 108, temperatureC: 41.4, cycleCount: 116),
]
check("紧凑顶栏在充电/已满/电池/混合/偏差/高功率状态均不截断",
      headerSnapshots.allSatisfy { header.layoutFitsForTest(snapshot: $0) }
          && header.layoutFitsForTest(snapshot: headerSnapshots[4], degraded: true))

let normalStates = headerSnapshots.prefix(4).map {
    header.statePresentationForTest(snapshot: $0)
}
check("顶栏保留四种正常供电状态文案",
      normalStates.map(\.text) == ["Charging", "Plugged In · Full", "On Battery", "Mixed Power · Adapter Limited"]
          && normalStates.allSatisfy { $0.color?.isEqual(PopoverStyle.secondaryText) == true })

let thresholdSnapshot = PowerSnapshot(
    percent: 100, plugged: true, adapterW: 52, batteryW: 0, systemW: 50,
    temperatureC: 31.8, cycleCount: 116,
    batteryTimeEstimate: .full, batteryTimeEstimateSource: .system
)
check("守恒偏差恰好 2 W 时仍显示正常状态",
      header.statePresentationForTest(snapshot: thresholdSnapshot).text == "Plugged In · Full")

let imbalanceState = header.statePresentationForTest(snapshot: headerSnapshots[4])
check("守恒偏差超过 2 W 时右上角显示红色数据异常",
      imbalanceState.text == "Data Issue · Imbalance -10.3 W"
          && imbalanceState.color?.isEqual(PopoverStyle.red) == true)

let degradedState = header.statePresentationForTest(snapshot: headerSnapshots[4], degraded: true)
check("读取失败优先于守恒偏差",
      degradedState.text == "Read Failed · Last Reading"
          && degradedState.color?.isEqual(PopoverStyle.red) == true)

// ---- 9b. Reduce Motion 的 C 玻璃按钮：即时切换与原版恢复 ----
// Only DEBUG-local overrides and isolated defaults change. This never writes
// the user's accessibility preferences or sends a real helper mutation.
do {
    let previous = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"]
    defer {
        Settings.liquidGlassEnabled = false
        if let previous {
            setenv("WATTSON_FORCE_REDUCE_MOTION", previous, 1)
        } else {
            unsetenv("WATTSON_FORCE_REDUCE_MOTION")
        }
    }
    setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
    let footer = PopoverFooterView()
    footer.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                          height: PopoverFooterView.preferredHeight)
    footer.update(mode: .auto, helperInstalled: true,
                  systemBatteryIconHidden: false, tint: .systemBlue)
    let footerWindow = NSWindow(contentRect: footer.bounds,
                                 styleMask: [.titled, .closable],
                                 backing: .buffered, defer: false)
    footerWindow.isReleasedWhenClosed = false
    footerWindow.title = "Wattson Appearance Interaction"
    footerWindow.contentView = footer
    footer.layoutSubtreeIfNeeded()
    func footerDescendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + footerDescendants($0) }
    }
    if let battery = footerDescendants(footer).compactMap({ $0 as? NSButton }).first(where: {
        $0.action == NSSelectorFromString("systemBatteryIconChanged:")
    }) {
        func footerContains(_ text: String) -> Bool {
            footerDescendants(footer).compactMap { $0 as? NSTextField }
                .contains { !$0.isHidden && $0.stringValue == text }
        }
        for phase: SystemBatteryIconReadStatus in [.notRequested, .checking, .failed(.requestFailed)] {
            footer.update(mode: .auto, helperInstalled: true,
                          systemBatteryIconHidden: nil, tint: .systemBlue, readStatus: phase)
            footer.layoutSubtreeIfNeeded()
            check("battery unknown phase disables mutation", !battery.isEnabled && battery.state == .mixed)
            check("battery pending is not reported as failure",
                  footerContains("Status Unavailable") == (phase == .failed(.requestFailed)))
            check("battery reading has explicit feedback", footerContains("Reading…") == (phase == .checking))
        }
        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue, readStatus: .ready)
        check("battery read recovers checkbox and removes status",
              battery.isEnabled && battery.state == .off && !footerContains("Status Unavailable")
                  && !footerContains("Reading…"))
    } else { check("battery footer control exists", false) }
    if let baseline = footerDescendants(footer).compactMap({ $0 as? ModeSliderView }).first,
       let native = footerDescendants(footer).compactMap({ $0 as? NativeModeSegmentedControl }).first,
       let menu = footerDescendants(footer).compactMap({ $0 as? NSButton }).first(where: {
           $0.action == NSSelectorFromString("showMenu")
       }) {
        let originalModeFrame = baseline.frame
        let originalMenuFrame = menu.frame
        let originalNativeBordered = native.cell?.isBordered
        check("外观默认关闭并保持原版控件和菜单按钮尺寸",
              !Settings.liquidGlassEnabled && !baseline.isHidden && native.isHidden
                  && !menu.isBordered && menu.frame.size == NSSize(width: 22, height: 20))
        if #available(macOS 26.0, *) {
            // Match Settings' verified accessory-app activation, inside the
            // application event loop. Cooperative activate() alone may decline.
            DispatchQueue.main.async {
                footerWindow.makeKeyAndOrderFront(nil)
                NSRunningApplication.current.activate(options: [.activateAllWindows])
                app.activate(ignoringOtherApps: true)
                DispatchQueue.main.async {
                    guard footerWindow.isVisible else { return }
                    footerWindow.makeKeyAndOrderFront(nil)
                }
            }
            let footerKeyboardReady = runApplication(
                until: { app.isActive && footerWindow.isKeyWindow }, timeout: 2
            )
            check("玻璃键盘交互前测试 App 已激活且窗口真正获得 key 状态", footerKeyboardReady,
                  "active=\(app.isActive) key=\(footerWindow.isKeyWindow) canKey=\(footerWindow.canBecomeKey) keyTitle=\(app.keyWindow?.title ?? "nil")")
            _ = footerWindow.makeFirstResponder(baseline)
            setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
            Settings.liquidGlassEnabled = true
            footer.layoutSubtreeIfNeeded()
            let glass = footerDescendants(footer).compactMap { $0 as? NativeGlassModeControl }.first!
            let glassButtons = glass.subviews.compactMap { $0 as? NSButton }
            func logGlassFocus(_ stage: String) {
                let responder = footerWindow.firstResponder
                let view = responder as? NSView
                let description = responder.map { String(describing: type(of: $0)) } ?? "nil"
                let title = (responder as? NSButton)?.title ?? ""
                log("GLASS_FOCUS stage=\(stage) active=\(app.isActive) key=\(footerWindow.isKeyWindow) responder=\(description) title=\(title) group=\(responder === glass) child=\(view?.isDescendant(of: glass) == true) menu=\(responder === menu) classic=\(responder === baseline) enabled=\(glassButtons.map(\.isEnabled)) selected=\(String(describing: glass.selectedModeForTest))")
            }
            logGlassFocus("glass-enabled")
            check("减少动态效果的全局玻璃使用三个 C 原生按钮并转移键盘焦点",
                  baseline.isHidden && native.isHidden && !glass.isHiddenOrHasHiddenAncestor
                      && footerWindow.firstResponder === glass.keyboardFocusView
                      && glass.convert(glass.bounds, to: footer)
                          == NSRect(x: 0, y: 36, width: originalModeFrame.width, height: 38)
                      && glassButtons.count == 3
                      && glassButtons.map(\.title) == ["Auto", "Low Power", "High Power"]
                      && native.cell?.isBordered == originalNativeBordered)
            let operationContainers = footer.subviews.compactMap { $0 as? NSGlassEffectContainerView }
            let operationContainer = operationContainers.first
            let operationContent = operationContainer?.contentView
            let operationSurfaces = operationContent?.subviews.compactMap { $0 as? NSGlassEffectView } ?? []
            let modeSurfaceFrame = glass.convert(glass.bounds, to: footer)
            let glassMenuFrame = menu.convert(menu.bounds, to: footer)
            check("底部操作层使用单一容器且没有重复玻璃或不透明分段底槽",
                  operationContainers.count == 1 && operationSurfaces.isEmpty
                      && operationContainer?.spacing == 0
                      && operationContainer?.isHidden == false
                      && glass.superview === operationContent
                      && native.superview === footer && native.isHidden
                      && menu.superview === operationContent
                      && glass.layer?.backgroundColor == nil
                      && glassButtons.allSatisfy { $0.isBordered && $0.bezelStyle == .glass
                          && $0.borderShape == .capsule && $0.frame.height == 38 }
                      && modeSurfaceFrame == NSRect(x: 0, y: 36, width: footer.bounds.width - 46, height: 38))
            check("原生玻璃菜单按钮可点击且不与档位控件重叠",
                  menu.isBordered && menu.bezelStyle == .glass
                      && menu.borderShape == .circle
                      && glassMenuFrame == NSRect(x: footer.bounds.width - 38, y: 36, width: 38, height: 38)
                      && glassMenuFrame.minX - modeSurfaceFrame.maxX == 8)
            let menuLocalPoint = NSPoint(x: glassMenuFrame.midX, y: glassMenuFrame.midY)
            let localPointHit = footer.hitTest(menuLocalPoint)
            // NSView.hitTest takes its superview's coordinates, including the
            // flipped-footer to non-flipped window-content conversion.
            let menuParentPoint = footer.convert(menuLocalPoint, to: footer.superview)
            let menuHit = footer.hitTest(menuParentPoint)
            var menuRequests = 0
            footer.onShowMenu = { sender in if sender === menu { menuRequests += 1 } }
            logGlassFocus("before-menu-click")
            menu.performClick(nil)
            logGlassFocus("after-menu-click")
            log("GLASS_MENU_HIT localPoint=\(menuLocalPoint) localPointHit=\(localPointHit.map { String(describing: type(of: $0)) } ?? "nil") parentPoint=\(menuParentPoint) parentPointHit=\(menuHit.map { String(describing: type(of: $0)) } ?? "nil") menuRequests=\(menuRequests)")
            check("嵌套玻璃不吞掉菜单点击或复制菜单动作",
                  (menuHit === menu || menuHit?.isDescendant(of: menu) == true)
                      && menuRequests == 1)
            glass.update(selected: .auto, enabledModes: [.auto, .low])
            logGlassFocus("after-availability-update")
            check("玻璃按钮组保留可访问性标签、选中语义与禁用档位",
                  glass.accessibilityRole() == .radioGroup
                      && glass.accessibilityLabel() == "Power Mode"
                      && glass.accessibilityValueDescription() == "Auto"
                      && glass.accessibilityChildren()?.count == 3
                      && glassButtons.allSatisfy { !$0.isAccessibilityElement()
                          && $0.cell?.isAccessibilityElement() == true
                          && $0.cell?.accessibilityRole() == .checkBox
                          && $0.cell?.accessibilityLabel() == $0.title
                          && ($0.cell?.accessibilityChildren()?.count ?? 0) == 0 }
                      && glassButtons.map(\.state) == [.on, .off, .off]
                      && (glassButtons[0].cell?.accessibilityValue() as? NSNumber)?.intValue == 1
                      && !glassButtons[2].isEnabled)
            var requests = 0
            var completion: ((EnergyMode?) -> Void)?
            footer.onSelect = { _, callback in requests += 1; completion = callback }
            glassButtons[0].performClick(nil)
            logGlassFocus("after-selected-click")
            glassButtons[2].performClick(nil)
            logGlassFocus("after-disabled-click")
            check("已选模式重复点击不取消选择且禁用模式不发起请求",
                  requests == 0 && glassButtons.map(\.state) == [.on, .off, .off])
            glassButtons[1].performClick(nil)
            logGlassFocus("after-low-request")
            check("真实键盘窗口中忙时焦点暂存于玻璃模式组而不退回窗口",
                  footerWindow.isKeyWindow && footerWindow.firstResponder === glass)
            glass.selectModeForTest(.auto)
            glassButtons[0].performClick(nil)
            logGlassFocus("after-busy-rejected-clicks")
            check("玻璃模式等待确认时禁用全部按钮并拒绝重复请求",
                  requests == 1 && glass.selectedModeForTest == .low
                      && glassButtons.allSatisfy { !$0.isEnabled }
                      && !glass.accessibilityPerformIncrement()
                      && !glass.accessibilityPerformDecrement())
            setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
            Settings.liquidGlassEnabled = false
            footer.layoutSubtreeIfNeeded()
            logGlassFocus("after-glass-disabled")
            log("GLASS_RESTORE sliderVisible=\(!baseline.isHidden) nativeHidden=\(native.isHidden) focus=\(footerWindow.firstResponder === baseline) modeFrame=\(baseline.frame) expectedModeFrame=\(originalModeFrame) menuFrame=\(menu.frame) expectedMenuFrame=\(originalMenuFrame) nativeParent=\(native.superview === footer) menuParent=\(menu.superview === footer) nativeBordered=\(String(describing: native.cell?.isBordered)) expectedBordered=\(String(describing: originalNativeBordered)) containerHidden=\(String(describing: operationContainer?.isHidden)) menuBordered=\(menu.isBordered) selectedIndex=\(baseline.selectedIndexForTest) requests=\(requests)")
            check("关闭全局玻璃恢复原版几何并保留待确认档位和焦点",
                  !baseline.isHidden && native.isHidden
                      && footerWindow.firstResponder === baseline
                      && baseline.frame == originalModeFrame && menu.frame == originalMenuFrame
                      && native.superview === footer && menu.superview === footer
                      && native.cell?.isBordered == originalNativeBordered
                      && operationContainer?.isHidden == true
                      && !menu.isBordered && baseline.selectedIndexForTest == 1
                      && requests == 1)
            completion?(nil)
            check("跨外观切换的失败回调仍回滚档位且没有重复写入",
                  baseline.selectedIndexForTest == 0 && glass.selectedModeForTest == .auto
                      && glassButtons[0].isEnabled && glassButtons[1].isEnabled && requests == 1)
            setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
            Settings.liquidGlassEnabled = true
            check("再次开启玻璃复用原有操作宿主而不堆积容器",
                  footer.subviews.compactMap { $0 as? NSGlassEffectContainerView }.count == 1
                      && footer.subviews.contains { $0 === operationContainer }
                      && glass.superview === operationContent
                      && zip(glass.subviews.compactMap { $0 as? NSButton }, glassButtons).allSatisfy { $0 === $1 }
                      && operationContainer?.isHidden == false)
            for focused in [glass.keyboardFocusView, menu as NSView] {
                _ = footerWindow.makeFirstResponder(focused)
                for enabled in [false, true, false] {
                    Settings.liquidGlassEnabled = enabled
                    footer.layoutSubtreeIfNeeded()
                    let expectedFocus: NSView = focused === menu ? menu
                        : (enabled ? glass.keyboardFocusView : native)
                    check("减少动态效果下玻璃按钮与经典原生分段切换正确转移焦点",
                          footerWindow.firstResponder === expectedFocus
                              && native.isHiddenOrHasHiddenAncestor == enabled
                              && glass.isHiddenOrHasHiddenAncestor == !enabled
                              && baseline.isHidden
                              && operationContainer?.isHidden == !enabled
                              && native.cell?.isBordered == originalNativeBordered
                              && requests == 1 && menuRequests == 1)
                }
            }
            check("关闭玻璃不关闭用户的减少动态效果",
                  baseline.isHidden && !native.isHidden && !menu.isBordered
                      && native.frame == originalModeFrame && menu.frame == originalMenuFrame)
            Settings.liquidGlassEnabled = true
            _ = footerWindow.makeFirstResponder(glass.keyboardFocusView)
            glassButtons[1].performClick(nil)
            check("第二次模式请求仍暂存键盘焦点并禁用所有档位",
                  footerWindow.firstResponder === glass && glassButtons.allSatisfy { !$0.isEnabled }
                      && requests == 2)
            completion?(.low)
            check("确认完成后焦点恢复到实际选中且可用的玻璃按钮",
                  footerWindow.firstResponder === glassButtons[1]
                      && glass.selectedModeForTest == .low && glassButtons[1].isEnabled)
            glassButtons[0].performClick(nil)
            _ = footerWindow.makeFirstResponder(menu)
            completion?(nil)
            check("用户已将焦点移到菜单时失败恢复不抢回模式焦点",
                  footerWindow.firstResponder === menu && glass.selectedModeForTest == .low
                      && glassButtons[1].isEnabled && requests == 3 && menuRequests == 1)
        } else {
            Settings.liquidGlassEnabled = true
            check("旧 macOS 保存选择但不假装支持原生全局玻璃",
                  !Settings.usesLiquidGlass && !baseline.isHidden
                      && native.isHidden && !menu.isBordered)
        }
    } else {
        check("外观交互测试具备原版、原生和菜单控件", false)
    }
    footerWindow.close()
}

// ---- 9c. A2：真实窗口、原生 AX 和共享意图模型 ----
// The drag checks below call the same model boundary as SwiftUI's gesture,
// not injected pointer events. They verify request/cancellation semantics;
// actual pointer tracking, refraction and focus outlines need separate CUA QA.
if #available(macOS 26.0, *) {
    let previous = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"]
    let previousTransparency = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"]
    let previousContrast = ProcessInfo.processInfo.environment["WATTSON_FORCE_INCREASE_CONTRAST"]
    defer {
        Settings.liquidGlassEnabled = false
        if let previous { setenv("WATTSON_FORCE_REDUCE_MOTION", previous, 1) }
        else { unsetenv("WATTSON_FORCE_REDUCE_MOTION") }
        if let previousTransparency { setenv("WATTSON_FORCE_REDUCE_TRANSPARENCY", previousTransparency, 1) }
        else { unsetenv("WATTSON_FORCE_REDUCE_TRANSPARENCY") }
        if let previousContrast { setenv("WATTSON_FORCE_INCREASE_CONTRAST", previousContrast, 1) }
        else { unsetenv("WATTSON_FORCE_INCREASE_CONTRAST") }
    }
    setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
    setenv("WATTSON_FORCE_REDUCE_TRANSPARENCY", "0", 1)
    setenv("WATTSON_FORCE_INCREASE_CONTRAST", "0", 1)
    Settings.liquidGlassEnabled = true
    func a2Descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + a2Descendants($0) }
    }
    func a2Key(_ code: UInt16, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                         timestamp: 0, windowNumber: window.windowNumber, context: nil,
                         characters: "", charactersIgnoringModifiers: "",
                         isARepeat: false, keyCode: code)!
    }
    struct A2AccessibilityNode {
        let element: AXUIElement
        let role: String?
        let name: String?
        let value: String?
        let enabled: Bool?
    }
    func a2SystemAccessibilityNodes() -> [A2AccessibilityNode] {
        // Query only this test's own window using the public assistive-client
        // API. SwiftUI virtual nodes need not declare NSAccessibilityProtocol.
        // Same-process AX can call AppKit/SwiftUI directly on the caller's
        // thread, so these UI reads and actions must stay on the main thread.
        // This never enables a private accessibility mode or changes TCC.
        precondition(Thread.isMainThread)
        let pid = ProcessInfo.processInfo.processIdentifier
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.5)
        var rawWindows: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &rawWindows)
        log("A2_SYSTEM_AX trusted=\(AXIsProcessTrusted()) windowsStatus=\(status.rawValue)")
        let deadline = Date().addingTimeInterval(3)
        var nodes: [A2AccessibilityNode] = []
        var readComplete = status == .success
        func attribute(_ node: AXUIElement, _ name: String, context: String = "window") -> CFTypeRef? {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(node, name as CFString, &value)
            if error != .success && error != .attributeUnsupported && error != .noValue {
                log("A2_SYSTEM_AX context=\(context) attribute=\(name) error=\(error.rawValue)")
                readComplete = false
            }
            return value
        }
        func visit(_ node: AXUIElement, depth: Int) {
            guard depth < 12, nodes.count < 60, Date() < deadline else {
                readComplete = false
                return
            }
            let entry = A2AccessibilityNode(element: node,
                role: attribute(node, kAXRoleAttribute) as? String,
                name: attribute(node, kAXDescriptionAttribute) as? String
                    ?? attribute(node, kAXTitleAttribute) as? String,
                value: attribute(node, kAXValueAttribute) as? String,
                enabled: attribute(node, kAXEnabledAttribute) as? Bool)
            nodes.append(entry)
            if entry.role == nil { readComplete = false }
            var names: CFArray?
            let namesStatus = AXUIElementCopyAttributeNames(node, &names)
            guard namesStatus == .success, let supported = names as? [String] else {
                log("A2_SYSTEM_AX attributes role=\(entry.role ?? "nil") error=\(namesStatus.rawValue)")
                readComplete = false
                return
            }
            // Leaf elements need not advertise AXChildren. Do not mistake
            // that for an incomplete tree, or swallow a real generic error.
            guard supported.contains(kAXChildrenAttribute) else { return }
            if let value = attribute(node, kAXChildrenAttribute,
                                     context: "\(entry.role ?? "nil")/\(entry.name ?? "nil")") {
                guard let children = value as? [AXUIElement] else {
                    readComplete = false
                    return
                }
                for child in children { visit(child, depth: depth + 1) }
            }
        }
        let windows = (rawWindows as? [AXUIElement] ?? []).filter {
            attribute($0, kAXTitleAttribute) as? String == "Wattson A2 Interaction Contract"
        }
        if windows.count != 1 { readComplete = false }
        for window in windows { visit(window, depth: 0) }
        check("A2 公开系统 AX 完整读取唯一测试窗口", readComplete)
        return nodes
    }
    func pressA2Accessibility(_ node: A2AccessibilityNode) -> AXError? {
        precondition(Thread.isMainThread)
        var pid: pid_t = 0
        guard AXUIElementGetPid(node.element, &pid) == .success,
              pid == ProcessInfo.processInfo.processIdentifier else {
            check("A2 AX 动作只能针对本测试进程", false)
            return nil
        }
        AXUIElementSetMessagingTimeout(node.element, 0.5)
        let result = AXUIElementPerformAction(node.element, kAXPressAction as CFString)
        log("A2_SYSTEM_AX press=\(node.name ?? "nil") mainThread=true status=\(result.rawValue)")
        return result
    }
    let footer = PopoverFooterView()
    footer.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                          height: PopoverFooterView.preferredHeight)
    footer.update(mode: .auto, helperInstalled: true,
                  systemBatteryIconHidden: false, tint: .systemBlue)
    let window = NSWindow(contentRect: footer.bounds, styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = "Wattson A2 Interaction Contract"
    window.contentView = footer
    footer.layoutSubtreeIfNeeded()
    window.makeKeyAndOrderFront(nil)
    let a2WindowReady = runApplication(until: { window.isKeyWindow }, timeout: 2)
    check("A2 交互契约使用可见真实窗口", a2WindowReady)
    if let a2 = a2Descendants(footer).compactMap({ $0 as? InteractiveGlassModeControl }).first,
       let classic = a2Descendants(footer).compactMap({ $0 as? ModeSliderView }).first,
       let native = a2Descendants(footer).compactMap({ $0 as? NativeModeSegmentedControl }).first {
        check("正常动态效果选择 A2 并保持原有底栏高度",
              !a2.isHiddenOrHasHiddenAncestor && classic.isHidden && native.isHidden
                  && footer.frame.height == 78
                  && a2.frame.width == footer.bounds.width + 24 && a2.frame.height == 62)
        let padding = NSPoint(x: a2.frame.midX, y: a2.frame.minY + 2)
        let hit = footer.hitTest(footer.convert(padding, to: footer.superview))
        check("A2 透明光学留白不抢占邻接控件点击",
              hit !== a2 && hit?.isDescendant(of: a2) != true)
        var requests: [EnergyMode] = []
        var completion: ((EnergyMode?) -> Void)?
        footer.onSelect = { mode, callback in requests.append(mode); completion = callback }
        a2.update(selected: .auto, enabledModes: [.auto, .low])
        spin(0.1)
        let axButtons = a2SystemAccessibilityNodes().filter {
            $0.role == kAXButtonRole && ["Auto", "Low Power", "High Power"].contains($0.name ?? "")
        }
        check("A2 原生 AX 树恰有三个固定顺序且完整命名的模式按钮",
              axButtons.map(\.name) == ["Auto", "Low Power", "High Power"],
              "count=\(axButtons.count); labels=\(axButtons.map(\.name))")
        if axButtons.count == 3 {
            check("A2 AX 选中值和禁用 High Power 与显示状态一致",
                  axButtons[0].value == "Selected" && axButtons[1].value == "Not selected"
                      && axButtons[0].enabled == true && axButtons[1].enabled == true
                      && axButtons[2].enabled == false)
            let selectedPressSucceeded = pressA2Accessibility(axButtons[0]) == .success
            _ = pressA2Accessibility(axButtons[2])
            check("A2 AX 重复选择和禁用选择不产生请求", selectedPressSucceeded && requests.isEmpty)
        }

        a2.beginDragForTest(startX: 10)
        let origin = a2.dragOriginForTest(translationX: 70)
        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        check("A2 共享拖动状态路径连续移动但不调用 helper 意图",
              origin.map { abs($0 - 70) < 0.01 } == true && requests.isEmpty)
        a2.endDragForTest(translationX: 90)
        a2.endDragForTest(translationX: 90)
        check("A2 松手路径仅提交一次并立即进入 owner 忙态",
              requests == [.low] && a2.selectedModeForTest == .low && a2.enabledModesForTest.isEmpty)
        a2.selectModeForTest(.auto)
        a2.keyDown(with: a2Key(123, window: window))
        a2.beginDragForTest(startX: 100)
        a2.endDragForTest(translationX: -90)
        check("A2 忙态拒绝点击键盘和拖动的重复请求", requests == [.low])
        Settings.liquidGlassEnabled = false
        Settings.liquidGlassEnabled = true
        check("A2 待确认状态跨经典主题来回切换而不丢失",
              a2.enabledModesForTest.isEmpty && a2.selectedModeForTest == .low && requests == [.low])
        footer.update(mode: .high, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        completion?(nil)
        check("A2 失败回滚到 owner 最新观测并恢复可用模式",
              a2.selectedModeForTest == .high && a2.enabledModesForTest.contains(.auto)
                  && a2.enabledModesForTest.contains(.low) && requests == [.low])
        footer.update(mode: .auto, helperInstalled: true,
                      systemBatteryIconHidden: false, tint: .systemBlue)
        a2.beginDragForTest(startX: 10)
        let escapeGeneration = a2.cancellationGenerationForTest
        a2.cancelOperation(nil)
        a2.endDragForTest(translationX: 90)
        check("A2 Escape 取消共享拖动状态且迟到松手不提交",
              a2.cancellationGenerationForTest > escapeGeneration && requests == [.low]
                  && !a2.isDraggingForTest && a2.selectedModeForTest == .auto)
        _ = window.makeFirstResponder(a2.keyboardFocusView)
        a2.keyDown(with: a2Key(124, window: window))
        check("A2 AppKit 键盘入口产生一个可确认的模式请求", requests == [.low, .low])
        completion?(.low)
        a2.keyDown(with: a2Key(36, window: window))
        check("A2 确认后回车重复选择不会取消或重复提交",
              a2.selectedModeForTest == .low && a2.enabledModesForTest.contains(.low)
                  && requests == [.low, .low])

        var menuRequests = 0
        footer.onShowMenu = { anchor in
            if anchor.window === window && anchor.isDescendant(of: a2) { menuRequests += 1 }
        }
        let menus = a2SystemAccessibilityNodes().filter {
            $0.role == kAXButtonRole && $0.name == "Choose Modules"
        }
        check("A2 恰有一个原生可访问设置菜单按钮", menus.count == 1, "count=\(menus.count)")
        let menuPressSucceeded = menus.first.map { pressA2Accessibility($0) == .success } ?? false
        check("A2 菜单使用真实宿主锚点且不产生电源模式写入",
              menuPressSucceeded && menuRequests == 1 && requests == [.low, .low],
              "press=\(menuPressSucceeded); menus=\(menuRequests); modeRequests=\(requests)")

        let slot = (a2.bounds.width - 24 - 46) / 3
        a2.beginDragForTest(startX: slot + 10)
        let fallbackGeneration = a2.cancellationGenerationForTest
        setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
        footer.applyReduceMotionChangeForTest(true)
        footer.layoutSubtreeIfNeeded()
        a2.endDragForTest(translationX: -90)
        let fallback = a2Descendants(footer).compactMap { $0 as? NativeGlassModeControl }.first
        check("运行时减少动态效果切到 C 并取消 A2 未提交拖动",
              a2.isHiddenOrHasHiddenAncestor && fallback?.isHiddenOrHasHiddenAncestor == false
                  && a2.cancellationGenerationForTest > fallbackGeneration
                  && fallback?.selectedModeForTest == .low && requests == [.low, .low])
        setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
        footer.applyReduceMotionChangeForTest(false)
        footer.layoutSubtreeIfNeeded()
        check("恢复动画复用同一 A2 宿主且隐藏 C 不增加请求",
              !a2.isHiddenOrHasHiddenAncestor && fallback?.isHiddenOrHasHiddenAncestor == true
                  && a2Descendants(footer).compactMap { $0 as? InteractiveGlassModeControl }.count == 1
                  && a2.selectedModeForTest == .low && requests == [.low, .low])
        for option in ["WATTSON_FORCE_REDUCE_TRANSPARENCY", "WATTSON_FORCE_INCREASE_CONTRAST"] {
            a2.beginDragForTest(startX: slot + 10)
            setenv(option, "1", 1)
            footer.applyReduceMotionChangeForTest(false)
            a2.endDragForTest(translationX: -90)
            check("\(option) 优先使用可读的 C 并取消 A2 未提交状态",
                  a2.isHiddenOrHasHiddenAncestor && fallback?.isHiddenOrHasHiddenAncestor == false
                      && !a2.isDraggingForTest && requests == [.low, .low])
            setenv(option, "0", 1)
            footer.applyReduceMotionChangeForTest(false)
            check("\(option) 关闭后恢复同一 A2 且模式保持不变",
                  !a2.isHiddenOrHasHiddenAncestor && a2.selectedModeForTest == .low
                      && requests == [.low, .low])
        }
    } else {
        check("A2 真实窗口具备新宿主及两个经典回退", false)
    }
    window.close()

    if !screenLocked {
        let panel = PopoverController()
        var requests = 0
        panel.setModeSelectHandler { _, _ in requests += 1 }
        panel.update(snapshot: headerSnapshots[0], history: [40, 45.8], peak: 45.8, degraded: false)
        panel.openForSettingsCommandTest(relativeTo: button)
        _ = runApplication(until: { panel.isShownForTest }, timeout: 1)
        if let root = panel.contentViewForTest,
           let owner = a2Descendants(root).compactMap({ $0 as? PopoverFooterView }).first,
           let a2 = a2Descendants(root).compactMap({ $0 as? InteractiveGlassModeControl }).first {
            // Configure the authoritative owner as well as its child. This
            // isolated fixture does not install or consult a real helper.
            owner.update(mode: .auto, helperInstalled: true,
                         systemBatteryIconHidden: false, tint: .systemBlue)
            var menuRequests = 0
            owner.onShowMenu = { anchor in
                if anchor.window === owner.window { menuRequests += 1 }
            }
            // This fixture targets the circle's settled padding in model
            // coordinates; entrance motion is verified independently above.
            root.layoutSubtreeIfNeeded()
            owner.scrollToVisible(owner.bounds)
            CATransaction.flush()
            let menuCircle = NSRect(x: owner.bounds.maxX - 38, y: 36, width: 38, height: 38)
            func entranceGeometrySettled() -> Bool {
                guard let layer = root.layer, let presentation = layer.presentation() else { return false }
                return presentation.opacity == layer.opacity
                    && CATransform3DEqualToTransform(presentation.transform, layer.transform)
            }
            let menuGeometryReady = runApplication(until: {
                entranceGeometrySettled() && owner.window?.isKeyWindow == true
                    && owner.visibleRect.contains(menuCircle)
            }, timeout: 1)
            check("设置菜单空白区域点击前画面已稳定且圆形区域完整可见",
                  menuGeometryReady && entranceGeometrySettled()
                      && owner.window?.isKeyWindow == true && owner.visibleRect.contains(menuCircle),
                  "entrance=\(panel.entranceAnimationCountForTest) key=\(owner.window?.isKeyWindow == true) "
                      + "presentationOpacity=\(String(describing: root.layer?.presentation()?.opacity)) "
                      + "presentationTransform=\(String(describing: root.layer?.presentation()?.transform)) "
                      + "circle=\(menuCircle) visible=\(owner.visibleRect)")
            // These points are inside the visible 38-point circle but outside
            // the small symbol. AXPress cannot detect this missing hit area.
            if let window = owner.window {
                for offset in [NSPoint(x: 13, y: 7), NSPoint(x: -13, y: -7)] {
                    let location = owner.convert(NSPoint(
                        x: owner.bounds.maxX - 19 + offset.x, y: 55 + offset.y
                    ), to: nil)
                    let expected = menuRequests + 1
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        let event = NSEvent.mouseEvent(with: type, location: location,
                            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: window.windowNumber, context: nil,
                            eventNumber: 0, clickCount: 1, pressure: 0)!
                        app.postEvent(event, atStart: false)
                    }
                    let opened = runApplication(until: { menuRequests == expected }, timeout: 1)
                    check("设置圆形按钮的空白区域单击即打开菜单 \(offset)",
                          opened && menuRequests == expected && requests == 0)
                }
            } else {
                check("设置按钮点击测试具备真实玻璃窗口", false)
            }
            a2.beginDragForTest(startX: 10)
            let generation = a2.cancellationGenerationForTest
            panel.closeBypassingControllerForTest()
            _ = runApplication(until: { !panel.isShownForTest }, timeout: 1)
            a2.endDragForTest(translationX: 90)
            check("实际玻璃宿主自行关闭也取消 A2 拖动且拒绝迟到松手",
                  a2.cancellationGenerationForTest > generation && !a2.isDraggingForTest && requests == 0)
            panel.openForSettingsCommandTest(relativeTo: button)
            _ = runApplication(until: { panel.isShownForTest }, timeout: 1)
            check("实际玻璃宿主重开复用 A2 并没有恢复旧拖动或新增请求",
                  panel.glassPanelForTest != nil && panel.contentViewForTest === root
                      && !a2.isHiddenOrHasHiddenAncestor && requests == 0)
            owner.update(mode: .auto, helperInstalled: true,
                         systemBatteryIconHidden: false, tint: .systemBlue)
            a2.beginDragForTest(startX: 10)
            a2.endDragForTest(translationX: 90)
            check("重开后的新 A2 手势状态路径可正常提交一次", requests == 1,
                  "requests=\(requests); selected=\(a2.selectedModeForTest); enabled=\(a2.enabledModesForTest)")
        } else {
            check("实际玻璃面板展示生产 A2 控件", false)
        }
        panel.handleOutsideClick()
        _ = runApplication(until: { !panel.isShownForTest }, timeout: 1)
    }
}

// ---- 9d. B Regular / C Clear 的独立玻璃宿主与 Classic 生命周期 ----
// Menu tracking notifications and local-click predicates are deterministic
// decision-path tests, not proof of OS-global input delivery or menu tracking.
// All opens use the no-external-refresh test entry; no helper mutation occurs.
if #available(macOS 26.0, *), !screenLocked {
    let previousAppAppearance = app.appearance
    let previousStyle = Settings.liquidGlassStyle
    let previousArrow = Settings.showPopoverArrow
    let displayOverrides = ["WATTSON_FORCE_REDUCE_MOTION", "WATTSON_FORCE_REDUCE_TRANSPARENCY",
                            "WATTSON_FORCE_INCREASE_CONTRAST"]
    let previousOverrides = displayOverrides.map { ProcessInfo.processInfo.environment[$0] }
    defer {
        Settings.liquidGlassEnabled = false
        Settings.liquidGlassStyle = previousStyle
        Settings.showPopoverArrow = previousArrow
        Settings.colorScheme = .system
        app.appearance = previousAppAppearance
        for (name, value) in zip(displayOverrides, previousOverrides) {
            if let value { setenv(name, value, 1) } else { unsetenv(name) }
        }
    }
    displayOverrides.forEach { setenv($0, "0", 1) }
    app.appearance = NSAppearance(named: .aqua)
    func hostDescendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + hostDescendants($0) }
    }
    func hostA2(_ controller: PopoverController) -> InteractiveGlassModeControl? {
        controller.contentViewForTest.flatMap {
            hostDescendants($0).compactMap { $0 as? InteractiveGlassModeControl }.first
        }
    }
    func hostMonitorsAreRemoved(_ controller: PopoverController) -> Bool {
        !controller.isWatchingOutsideClicks && !controller.hasLocalEventMonitorForTest
            && controller.lifetimeObserverCountForTest == 0
    }
    let controller = PopoverController()
    var visibilityEvents: [Bool] = []
    var modeRequests = 0
    var batteryRequests = 0
    controller.onVisibilityChange { visibilityEvents.append($0) }
    controller.setModeSelectHandler { _, _ in modeRequests += 1 }
    controller.setSystemBatteryIconToggleHandler { _, _ in batteryRequests += 1 }
    controller.update(snapshot: headerSnapshots[0], history: [40, 45.8], peak: 45.8, degraded: false)
    let originalRoot = controller.contentViewForTest
    func checkInstalledHost(_ label: String, glass: Bool) {
        let panel = controller.glassPanelForTest
        let window = glass ? panel : controller.classicPopoverForTest.contentViewController?.view.window
        let installedViews = window?.contentView.map { [$0] + hostDescendants($0) } ?? []
        let fields = installedViews.compactMap { $0 as? NSTextField }
        let footer = installedViews.compactMap { $0 as? PopoverFooterView }.first
        let material = panel?.materialView
        let rootAttached = originalRoot.map { root in
            root.window === window && window != nil && installedViews.contains { $0 === root }
                && root.bounds.width > 0 && root.bounds.height > 0 && !root.isHiddenOrHasHiddenAncestor
        } ?? false
        let correctHost = glass
            ? panel != nil && originalRoot?.superview?.superview === panel?.contentView
                && material?.style == (Settings.liquidGlassStyle == .clear ? .clear : .regular)
            : panel == nil && controller.classicPopoverForTest.isShown
        check(label, controller.isOpen && controller.isShownForTest && window?.isVisible == true
              && correctHost && rootAttached
              && fields.contains { !$0.stringValue.isEmpty && !$0.isHiddenOrHasHiddenAncestor }
              && footer.map { $0.window === window && $0.bounds.width > 0 && $0.bounds.height > 0 } == true,
              "glass=\(glass) rootAttached=\(rootAttached) fields=\(fields.count) footer=\(footer != nil) correctHost=\(correctHost)")
    }
    let originalAnchorNotificationSetting = button.postsFrameChangedNotifications
    let otherWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                               styleMask: [.borderless], backing: .buffered, defer: false)
    let menuWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                              styleMask: [.borderless], backing: .buffered, defer: false)
    menuWindow.level = .popUpMenu
    let outside = NSPoint(x: -10_000, y: -10_000)
    for style in Settings.LiquidGlassStyle.allCases {
        Settings.liquidGlassStyle = style
        Settings.showPopoverArrow = true
        Settings.liquidGlassEnabled = true
        let statusPickPoints: [NSPoint] = button.window.map { window in [
            NSPoint(x: window.frame.midX, y: window.frame.midY),
            NSPoint(x: window.frame.midX, y: window.frame.maxY - 1),
            NSPoint(x: window.frame.midX, y: window.frame.minY + 1),
            NSPoint(x: window.frame.minX + 1, y: window.frame.midY),
            NSPoint(x: window.frame.maxX - 1, y: window.frame.midY),
        ] } ?? []
        let closedStatusPicks = statusPickPoints.map {
            NSWindow.windowNumber(at: $0, belowWindowWithWindowNumber: 0)
        }
        controller.openForSettingsCommandTest(relativeTo: button)
        _ = runApplication(until: { controller.isShownForTest }, timeout: 1)
        guard let panel = controller.glassPanelForTest else {
            check("\(style.rawValue) 使用真实独立玻璃面板", false)
            continue
        }
        let materialViews = panel.contentView?.subviews.compactMap { $0 as? GlassPopoverMaterialView } ?? []
        let material = materialViews.first
        let foreground = originalRoot?.superview
        check("\(style.rawValue) 交互内容位于玻璃背景上方且没有玻璃祖先",
              material?.hitTest(.zero) == nil && foreground?.superview === panel.contentView
                  && panel.contentView?.subviews.last === foreground
                  && foreground?.frame == panel.bodyFrame && originalRoot?.frame == foreground?.bounds
                  && foreground?.layer?.masksToBounds == true
                  && foreground?.layer?.cornerRadius == GlassPopoverShape.cornerRadius
                  && material?.frame.height == panel.bodyFrame.height + PopoverPlacement.glassArrowHeight
                  && material.map { originalRoot?.isDescendant(of: $0) == false } == true)
        check("\(style.rawValue) 背景使用单一原生材质并保持同一生产内容",
              materialViews.count == 1 && material?.style == (style == .clear ? .clear : .regular)
                  && foreground?.superview === panel.contentView && controller.contentViewForTest === originalRoot
                  && controller.contentWindowForTest === panel && panel.styleMask.contains(.nonactivatingPanel)
                  && !panel.isOpaque && panel.backgroundColor == .clear
                  && panel.appearance == nil && panel.canBecomeKey && !panel.canBecomeMain
                  && panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
                  && originalRoot?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
                  && controller.cachedPercentForTest == headerSnapshots[0].percent)
        checkInstalledHost("\(style.rawValue) 当前可见宿主确实挂载完整内容而非空壳", glass: true)
        let backgrounds = panel.contentView?.subviews.compactMap { $0 as? GlassBackgroundView } ?? []
        for transparency in [0.0, 0.5, 1.0] {
            let previousVisibility = visibilityEvents.count
            let previousObservers = controller.lifetimeObserverCountForTest
            Settings.liquidGlassTransparency = transparency
            backgrounds.forEach { $0.updateLayer() }
            let expectedOpacity = GlassBackgroundView.accessibilityRequiresSolidBackground ? 1 : max(1 - transparency, 1.0 / 255.0)
            check("\(style.rawValue) 透明度 \(transparency) 仅改变背景并保留可见宿主和读数",
                  backgrounds.count == 1
                      && abs(Double(backgrounds.first?.layer?.backgroundColor?.alpha ?? 0) - expectedOpacity) < 0.001
                      && backgrounds.first?.hitTest(.zero) == nil
                      && material?.alphaValue == 1 && originalRoot?.alphaValue == 1
                      && controller.glassPanelForTest === panel && panel.isVisible
                      && originalRoot?.superview?.superview === panel.contentView
                      && controller.cachedPercentForTest == headerSnapshots[0].percent
                      && visibilityEvents.count == previousVisibility
                      && controller.lifetimeObserverCountForTest == previousObservers)
        }
        if let root = originalRoot, let material,
           let scroll = hostDescendants(root).compactMap({ $0 as? NSScrollView }).first,
           let document = scroll.documentView {
            let bodyWithArrow = panel.convertToScreen(panel.bodyFrame)
            let frameWithArrow = panel.frame
            let viewportWithArrow = root.frame.height
            let extraViewport = min(PopoverPlacement.glassArrowHeight,
                                    max(0, document.bounds.height - viewportWithArrow))
            let fields = hostDescendants(root).compactMap { $0 as? NSTextField }
            let fieldIDs = fields.map(ObjectIdentifier.init)
            let fieldValues = fields.map(\.stringValue)
            let a2 = hostA2(controller)
            let observerCount = controller.lifetimeObserverCountForTest
            let eventCount = visibilityEvents.count
            let menu = NSMenu(title: "Arrow preference tracking fixture")
            NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
            Settings.showPopoverArrow = false
            root.layoutSubtreeIfNeeded()
            let bodyWithoutArrow = panel.convertToScreen(panel.bodyFrame)
            let currentFields = hostDescendants(root).compactMap { $0 as? NSTextField }
            let mask = backgrounds.first?.layer?.mask as? CAShapeLayer
            check("[ARROW-OPTION] \(style.rawValue) 关闭箭头让正文上移12点并回收受限视口",
                  !panel.showsArrow && !material.showsArrow
                      && abs(bodyWithoutArrow.maxY - bodyWithArrow.maxY - 12) < 0.5
                      && abs(panel.frame.maxY - frameWithArrow.maxY) < 0.5
                      && abs(root.frame.height - viewportWithArrow - extraViewport) < 0.5
                      && foreground?.frame == panel.bodyFrame
                      && root.frame == foreground?.bounds
                      && material.frame.height == panel.bodyFrame.height,
                  "bodyTopGain=\(bodyWithoutArrow.maxY - bodyWithArrow.maxY) "
                      + "viewportGain=\(root.frame.height - viewportWithArrow) expected=\(extraViewport)")
            check("[ARROW-OPTION] \(style.rawValue) 无箭头背景顶边连续且保留圆角裁切",
                  mask?.path?.contains(NSPoint(x: GlassPopoverShape.cornerRadius + 2,
                                               y: material.bounds.maxY - 0.5)) == true
                      && mask?.path?.contains(NSPoint(x: 1, y: material.bounds.maxY - 0.5)) == false
                      && foreground?.layer?.masksToBounds == true)
            panel.cancelOperation(nil)
            check("[ARROW-OPTION] \(style.rawValue) 在线切换保留宿主内容控件菜单和处理器",
                  controller.isOpen && controller.isShownForTest
                      && controller.glassPanelForTest === panel && panel.materialView === material
                      && controller.contentViewForTest === root && hostA2(controller) === a2
                      && currentFields.map(ObjectIdentifier.init) == fieldIDs
                      && currentFields.map(\.stringValue) == fieldValues
                      && visibilityEvents.count == eventCount
                      && controller.lifetimeObserverCountForTest == observerCount
                      && panel.onDismiss != nil && panel.onEscape != nil
                      && modeRequests == 0 && batteryRequests == 0)
            NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
            Settings.showPopoverArrow = true
            root.layoutSubtreeIfNeeded()
            check("[ARROW-OPTION] \(style.rawValue) 恢复箭头回到原始完整布局",
                  panel.showsArrow && material.showsArrow
                      && panel.frame == frameWithArrow
                      && panel.convertToScreen(panel.bodyFrame) == bodyWithArrow
                      && root.frame.height == viewportWithArrow
                      && controller.glassPanelForTest === panel,
                  "panelArrow=\(panel.showsArrow) materialArrow=\(material.showsArrow) "
                      + "samePanel=\(controller.glassPanelForTest === panel) "
                      + "frameBefore=\(frameWithArrow) frameAfter=\(panel.frame) "
                      + "bodyBefore=\(bodyWithArrow) bodyAfter=\(panel.convertToScreen(panel.bodyFrame)) "
                      + "viewportBefore=\(viewportWithArrow) viewportAfter=\(root.frame.height) "
                      + "material=\(material.frame) foreground=\(String(describing: foreground?.frame))")
        } else { check("[ARROW-OPTION] \(style.rawValue) 具备实际滚动内容和材质", false) }
        let openVisibilityCount = visibilityEvents.count
        let openObserverCount = controller.lifetimeObserverCountForTest
        controller.openForSettingsCommandTest(relativeTo: button)
        controller.openForSettingsCommandTest(relativeTo: button)
        let visiblePanels = NSApp.windows.filter { $0 is GlassPopoverPanel && $0.isVisible }
        check("\(style.rawValue) 重复打开复用当前面板且不留下空玻璃壳",
              controller.glassPanelForTest === panel && visiblePanels.count == 1
                  && visiblePanels.first === panel && originalRoot?.window === panel
                  && visibilityEvents.count == openVisibilityCount
                  && controller.lifetimeObserverCountForTest == openObserverCount)
        if let root = originalRoot, let a2 = hostA2(controller) {
            root.layoutSubtreeIfNeeded()
            let fields = hostDescendants(root).compactMap { $0 as? NSTextField }
            let fieldIDs = fields.map(ObjectIdentifier.init)
            let fieldValues = fields.map(\.stringValue)
            let fieldFrames = fields.map(\.frame)
            let panelFrame = panel.frame
            let contentFrame = root.frame
            let controlFrame = a2.frame
            let selectedMode = a2.selectedModeForTest
            let enabledModes = a2.enabledModesForTest
            for appearance: NSAppearance.Name in [.darkAqua, .aqua] {
                app.appearance = NSAppearance(named: appearance)
                let inherited = runApplication(until: {
                    panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance
                        && root.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance
                }, timeout: 1)
                root.layoutSubtreeIfNeeded()
                let currentFields = hostDescendants(root).compactMap { $0 as? NSTextField }
                check("\(style.rawValue) 跟随 \(appearance.rawValue) 且不重建玻璃宿主或生产内容",
                      inherited && panel.appearance == nil && root.appearance == nil
                          && controller.glassPanelForTest === panel && controller.contentViewForTest === root
                          && root.superview?.superview === panel.contentView && hostA2(controller) === a2
                          && material?.style == (style == .clear ? .clear : .regular))
                check("\(style.rawValue) 明暗切换保持全部展示文字、数值和布局且不写电源模式",
                      !fields.isEmpty && currentFields.map(ObjectIdentifier.init) == fieldIDs
                          && currentFields.map(\.stringValue) == fieldValues
                          && currentFields.map(\.frame) == fieldFrames && panel.frame == panelFrame
                          && root.frame == contentFrame && a2.frame == controlFrame
                          && a2.selectedModeForTest == selectedMode && a2.enabledModesForTest == enabledModes
                          && controller.cachedPercentForTest == headerSnapshots[0].percent
                          && modeRequests == 0 && batteryRequests == 0)
                checkInstalledHost("\(style.rawValue) 明暗切换后生产内容仍在当前窗口", glass: true)
            }
            for scheme in [Settings.ColorScheme.dark, .light, .system] {
                Settings.colorScheme = scheme
                let expected = scheme.appearance?.name ?? .aqua
                let applied = runApplication(until: {
                    root.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected
                }, timeout: 1)
                check("\(style.rawValue) 用户主题 \(scheme.rawValue) 即时生效并保留打开的面板",
                      applied && panel.appearance?.name == scheme.appearance?.name
                          && controller.glassPanelForTest === panel && controller.contentViewForTest === root
                          && root.frame == contentFrame && panel.frame == panelFrame
                          && fields.map(\.stringValue) == fieldValues && fields.map(\.frame) == fieldFrames
                          && modeRequests == 0 && batteryRequests == 0)
                checkInstalledHost("\(style.rawValue) 主题选择后内容仍完整", glass: true)
            }
        } else { check("\(style.rawValue) 明暗测试具备完整生产内容与 A2", false) }
        check("\(style.rawValue) 打开时安装局部和全局监听及生命周期观察",
              controller.isWatchingOutsideClicks && controller.hasLocalEventMonitorForTest
                  && controller.lifetimeObserverCountForTest > 0 && button.postsFrameChangedNotifications)
        check("\(style.rawValue) 面板内点击不关闭，其他本 App 窗口点击需要关闭",
              !controller.shouldDismissLocalClickForTest(window: panel, screenPoint: outside)
                  && controller.shouldDismissLocalClickForTest(window: otherWindow, screenPoint: outside))
        if let anchorWindow = button.window {
            let anchorFrame = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
            if let material, let screen = anchorWindow.screen {
                let tip = panel.convertToScreen(NSRect(origin: panel.arrowTip, size: .zero)).origin
                let expectedX = GlassPopoverShape.clampedArrowX(
                    anchorFrame.midX - panel.frame.minX - material.frame.minX, width: material.bounds.width)
                let bodyTop = panel.convertToScreen(panel.bodyFrame).maxY
                check("[I20-ARROW] \(style.rawValue) 箭头对齐真实状态项且位于正文上方",
                      abs(tip.x - (panel.frame.minX + material.frame.minX + expectedX)) < 0.5
                          && abs(tip.y - (min(anchorFrame.minY, screen.visibleFrame.maxY) - 4)) < 0.5
                          && abs(tip.y - bodyTop - PopoverPlacement.glassArrowHeight) < 0.5,
                      "tip=\(tip) anchor=\(anchorFrame) bodyTop=\(bodyTop)")
            } else { check("[I20-ARROW] 玻璃箭头具备真实材质与屏幕", false) }
            check("\(style.rawValue) 锚点鼠标按下留给状态按钮的单次 toggle",
                  !controller.shouldDismissLocalClickForTest(window: anchorWindow,
                      screenPoint: NSPoint(x: anchorFrame.midX, y: anchorFrame.midY)))
            // Native status items may report a remote proxy ID, which the
            // WindowServer API returns as 0. Preserve each closed baseline and
            // calibrate the API with a hit inside this actual panel's body.
            spin(0.35)
            let statusPicks = statusPickPoints.map {
                NSWindow.windowNumber(at: $0, belowWindowWithWindowNumber: 0)
            }
            let bodyFrame = panel.convertToScreen(panel.bodyFrame)
            let bodyPick = NSWindow.windowNumber(at: NSPoint(x: bodyFrame.midX, y: bodyFrame.midY),
                                                 belowWindowWithWindowNumber: 0)
            check("[I20-WINDOW-PICKS] \(style.rawValue) 透明光学边距保持状态窗口中央及四边的原始命中",
                  statusPicks.count == 5 && statusPicks == closedStatusPicks
                      && statusPicks.allSatisfy { $0 != panel.windowNumber }
                      && bodyPick == panel.windowNumber,
                  "statusProxy=\(anchorWindow.windowNumber) closed=\(closedStatusPicks) open=\(statusPicks) body=\(bodyPick) panel=\(panel.windowNumber)")
            let gridBounds = bodyFrame.insetBy(dx: 27, dy: 27)
            let bodyGridPicks = (0..<7).flatMap { row in (0..<5).map { column in
                let point = NSPoint(x: gridBounds.minX + gridBounds.width * CGFloat(column) / 4,
                                    y: gridBounds.minY + gridBounds.height * CGFloat(row) / 6)
                return NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
            } }
            check("[I20-BODY-GRID] \(style.rawValue) 透明正文包括空白的5×7网格全部保持面板命中",
                  gridBounds.width > 0 && gridBounds.height > 0 && bodyGridPicks.count == 35
                      && bodyGridPicks.allSatisfy { $0 == panel.windowNumber },
                  "hits=\(bodyGridPicks.filter { $0 == panel.windowNumber }.count)/\(bodyGridPicks.count) floor=1/255 panel=\(panel.windowNumber)")
            let statusFrame = anchorWindow.frame
            let edgePoints = [
                NSPoint(x: statusFrame.midX, y: statusFrame.maxY - 0.5),
                NSPoint(x: statusFrame.midX, y: statusFrame.minY + 0.5),
                NSPoint(x: statusFrame.minX + 1, y: statusFrame.midY),
                NSPoint(x: statusFrame.maxX - 1, y: statusFrame.midY),
            ]
            check("\(style.rawValue) 状态窗口四边命中区不先关闭再重开",
                  edgePoints.allSatisfy {
                      !controller.shouldDismissLocalClickForTest(window: anchorWindow, screenPoint: $0)
                  })
            check("\(style.rawValue) 无窗口事件按完整状态窗口区域识别锚点",
                  edgePoints.allSatisfy {
                      !controller.shouldDismissLocalClickForTest(window: nil, screenPoint: $0)
                  })
        } else { check("玻璃面板保持有效的状态项锚点", false) }

        let menu = NSMenu(title: "Host routing fixture")
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        check("\(style.rawValue) 原生菜单跟踪期间保留菜单窗口与无窗口事件",
              !controller.shouldDismissLocalClickForTest(window: menuWindow, screenPoint: outside)
                  && !controller.shouldDismissLocalClickForTest(window: nil, screenPoint: outside)
                  && controller.shouldDismissLocalClickForTest(window: otherWindow, screenPoint: outside))
        panel.cancelOperation(nil)
        check("\(style.rawValue) 菜单期间 Escape 留给菜单而不关闭面板", controller.isOpen)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        check("\(style.rawValue) 菜单结束后恢复普通外部点击分类",
              controller.shouldDismissLocalClickForTest(window: menuWindow, screenPoint: outside)
                  && controller.shouldDismissLocalClickForTest(window: nil, screenPoint: outside))

        if let a2 = hostA2(controller) {
            check("\(style.rawValue) 背景搭配可见的生产 A2", !a2.isHiddenOrHasHiddenAncestor)
            a2.update(selected: .auto, enabledModes: [.auto, .low])
            a2.beginDragForTest(startX: 10)
            panel.cancelOperation(nil)
            a2.endDragForTest(translationX: 90)
            check("\(style.rawValue) 首次 Escape 仅取消拖动并保留面板",
                  !a2.isDraggingForTest && controller.isOpen && controller.isShownForTest && modeRequests == 0)
            panel.cancelOperation(nil)
            check("\(style.rawValue) 第二次 Escape 关闭面板并撤除所有监听",
                  !controller.isOpen && !controller.isShownForTest && hostMonitorsAreRemoved(controller)
                      && button.postsFrameChangedNotifications == originalAnchorNotificationSetting)
        } else { check("\(style.rawValue) 找到生产 A2", false) }
        controller.handleOutsideClick()

        controller.openForSettingsCommandTest(relativeTo: button)
        controller.handleOutsideClick() // The global monitor's exact handler.
        check("\(style.rawValue) 全局外部点击处理器关闭且清理全部生命周期资源",
              !controller.isShownForTest && !controller.isOpen && hostMonitorsAreRemoved(controller))
        controller.openForSettingsCommandTest(relativeTo: button)
        controller.toggle(relativeTo: button)
        check("\(style.rawValue) 状态按钮单次 toggle 只关闭不意外重开",
              !controller.isShownForTest && !controller.isOpen && hostMonitorsAreRemoved(controller))
        if let anchorFrame = button.window?.frame {
            for y in [anchorFrame.midY, anchorFrame.minY + 0.5, anchorFrame.maxY - 0.5, anchorFrame.maxY] {
                controller.openForSettingsCommandTest(relativeTo: button)
                controller.handleGlobalMouseDown(screenPoint: NSPoint(x: anchorFrame.midX, y: y))
                check("\(style.rawValue) 全局监听先收到锚点按下仍保留单次按钮动作",
                      controller.isShownForTest && controller.isOpen)
                controller.toggle(relativeTo: button)
                check("\(style.rawValue) 同一次全局按下随后按钮动作只关闭一次",
                      !controller.isShownForTest && !controller.isOpen && hostMonitorsAreRemoved(controller))
            }
            controller.openForSettingsCommandTest(relativeTo: button)
            controller.handleGlobalMouseDown(screenPoint: NSPoint(x: anchorFrame.minX - 100,
                                                                  y: anchorFrame.minY - 100))
            check("\(style.rawValue) 全局非锚点按下仍关闭且清理监听",
                  !controller.isShownForTest && !controller.isOpen && hostMonitorsAreRemoved(controller))
            controller.openForSettingsCommandTest(relativeTo: button)
            let point = NSPoint(x: anchorFrame.midX, y: anchorFrame.maxY)
            controller.handleWorkspaceActivationForTest(screenPoint: point, pressedMouseButtons: 1)
            controller.toggle(relativeTo: button)
            check("[I19-WORKSPACE] \(style.rawValue) 激活通知先于同一次按钮动作只关闭一次",
                  !controller.isOpen && !controller.isShownForTest && hostMonitorsAreRemoved(controller))
            controller.openForSettingsCommandTest(relativeTo: button)
            controller.handleWorkspaceActivationForTest(screenPoint: point, pressedMouseButtons: 0)
            check("[I19-IDLE] \(style.rawValue) 指针停锚点不阻止真正切换应用关闭",
                  !controller.isOpen && !controller.isShownForTest && hostMonitorsAreRemoved(controller))
        }
        controller.openForSettingsCommandTest(relativeTo: button)
        controller.closeBypassingControllerForTest()
        check("\(style.rawValue) 宿主自行关闭仍执行完整清理",
              !controller.isShownForTest && !controller.isOpen && hostMonitorsAreRemoved(controller))
        Settings.showPopoverArrow = false
        controller.openForSettingsCommandTest(relativeTo: button)
        check("[ARROW-OPTION] \(style.rawValue) 保存关闭箭头后再次打开使用同一生产内容",
              controller.isOpen && controller.glassPanelForTest?.showsArrow == false
                  && controller.contentViewForTest === originalRoot)
        controller.toggle(relativeTo: button)
        check("[ARROW-OPTION] \(style.rawValue) 无箭头时再次点击状态项收起并清理监听",
              !controller.isOpen && !controller.isShownForTest && hostMonitorsAreRemoved(controller))
        controller.openForSettingsCommandTest(relativeTo: button)
        controller.glassPanelForTest?.cancelOperation(nil)
        check("[ARROW-OPTION] \(style.rawValue) 无箭头重开后Escape仍关闭并清理监听",
              !controller.isOpen && !controller.isShownForTest && hostMonitorsAreRemoved(controller))
        Settings.showPopoverArrow = true
    }

    Settings.liquidGlassStyle = .regular
    controller.openForSettingsCommandTest(relativeTo: button)
    if let a2 = hostA2(controller), let previousPanel = controller.glassPanelForTest {
        a2.update(selected: .auto, enabledModes: [.auto, .low])
        a2.beginDragForTest(startX: 10)
        let generation = a2.cancellationGenerationForTest
        Settings.liquidGlassStyle = .clear
        _ = runApplication(until: { controller.isShownForTest }, timeout: 1)
        a2.endDragForTest(translationX: 90)
        check("拖动中由 B 切换 C 撤销旧手势、替换宿主并复用同一 A2 内容",
              controller.glassPanelForTest !== previousPanel && !previousPanel.isVisible
                  && controller.contentViewForTest === originalRoot && hostA2(controller) === a2
                  && a2.cancellationGenerationForTest > generation && !a2.isDraggingForTest
                  && modeRequests == 0 && batteryRequests == 0)
        checkInstalledHost("B 转 C 后内容挂载在新玻璃宿主而非退休窗口", glass: true)
    } else { check("样式切换测试具备真实玻璃面板及 A2", false) }
    controller.handleOutsideClick()

    // Preserve Classic's rapid reopen separately; retired Classic callbacks
    // must never tear down a replacement panel or poison fresh close counts.
    Settings.liquidGlassEnabled = false
    controller.openForSettingsCommandTest(relativeTo: button)
    _ = runApplication(until: { controller.isShownForTest }, timeout: 1)
    check("关闭全局玻璃恢复 Classic 系统外观及原生 NSPopover",
          controller.glassPanelForTest == nil && controller.popoverAppearanceForTest == nil
              && controller.contentViewForTest === originalRoot && controller.hasLocalEventMonitorForTest
              && controller.lifetimeObserverCountForTest == 3)
    checkInstalledHost("关闭玻璃后实际 Classic 窗口内容非空", glass: false)
    let retiredClassic = controller.classicPopoverForTest
    let classicWindow = controller.contentWindowForTest
    let classicFrame = classicWindow?.frame
    let classicContentFrame = originalRoot?.frame
    let classicCounts = controller.classicLifecycleCountsForTest
    let classicVisibilityCount = visibilityEvents.count
    for showsArrow in [false, true] {
        Settings.showPopoverArrow = showsArrow
        check("[ARROW-OPTION] Classic忽略玻璃箭头选择 \(showsArrow)，保留原生窗口及几何",
              controller.isOpen && controller.classicPopoverForTest === retiredClassic
                  && controller.contentWindowForTest === classicWindow
                  && classicWindow?.frame == classicFrame && originalRoot?.frame == classicContentFrame
                  && controller.classicLifecycleCountsForTest.shows == classicCounts.shows
                  && controller.classicLifecycleCountsForTest.closes == classicCounts.closes
                  && visibilityEvents.count == classicVisibilityCount)
    }
    for scheme in [Settings.ColorScheme.dark, .light, .system] {
        Settings.colorScheme = scheme
        let expected = scheme.appearance?.name ?? .aqua
        let applied = runApplication(until: {
            originalRoot?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected
        }, timeout: 1)
        check("Classic 用户主题 \(scheme.rawValue) 即时生效并保留当前窗口",
              applied && controller.classicPopoverForTest === retiredClassic
                  && controller.contentWindowForTest === classicWindow
                  && controller.contentViewForTest === originalRoot
                  && controller.cachedPercentForTest == headerSnapshots[0].percent
                  && modeRequests == 0 && batteryRequests == 0)
        checkInstalledHost("Classic 主题选择后内容仍完整", glass: false)
    }
    controller.toggle(relativeTo: button)
    let classicWasFading = controller.isShownForTest
    Settings.liquidGlassEnabled = true
    controller.openForSettingsCommandTest(relativeTo: button)
    let eventCount = visibilityEvents.count
    controller.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: retiredClassic))
    spin(0.65)
    check("Classic 关闭中转玻璃后，退休宿主迟到回调不能关闭新面板",
          controller.glassPanelForTest != nil && controller.isOpen && controller.isShownForTest
              && visibilityEvents.count == eventCount && controller.contentViewForTest === originalRoot,
          "native-fade-observed=\(classicWasFading)")
    checkInstalledHost("退休 Classic 关闭回调后新玻璃窗口仍持有完整内容", glass: true)
    Settings.liquidGlassEnabled = false
    _ = runApplication(until: { controller.isShownForTest }, timeout: 1)
    check("玻璃转回 Classic 使用新的干净原生计数且保留内容",
          controller.glassPanelForTest == nil && controller.isOpen
              && controller.classicPopoverForTest !== retiredClassic
              && controller.classicPopoverForTest.behavior == .semitransient
              && controller.classicLifecycleCountsForTest.shows > controller.classicLifecycleCountsForTest.closes
              && controller.contentViewForTest === originalRoot)
    checkInstalledHost("玻璃转回 Classic 后内容确实属于新原生窗口", glass: false)
    controller.toggle(relativeTo: button)
    controller.openForSettingsCommandTest(relativeTo: button)
    spin(1.2)
    check("跨宿主后 Classic 仍支持快速关闭重开且不会被迟到 didClose 拆除",
          controller.isOpen && controller.isShownForTest && controller.isWatchingOutsideClicks
              && controller.classicLifecycleCountsForTest.shows > controller.classicLifecycleCountsForTest.closes)
    checkInstalledHost("跨宿主后 Classic 关闭重开没有丢失内容", glass: false)
    controller.handleOutsideClick()
    _ = runApplication(until: { !controller.isShownForTest }, timeout: 1.2)
    check("跨宿主及重复重开最终关闭后所有监听归零且没有模式写入",
          hostMonitorsAreRemoved(controller) && !controller.isOpen && modeRequests == 0 && batteryRequests == 0)

    for finalGlass in [false, true] {
        Settings.liquidGlassEnabled = finalGlass
        controller.openForSettingsCommandTest(relativeTo: button)
        _ = runApplication(until: { controller.isShownForTest }, timeout: 1)
        // No run-loop drain between these writes: both directions must honor
        // the latest choice, not a queued callback from the intermediate host.
        Settings.liquidGlassEnabled = !finalGlass
        Settings.liquidGlassEnabled = finalGlass
        controller.openForSettingsCommandTest(relativeTo: button)
        spin(0.65)
        checkInstalledHost("同 run loop 来回切换最终 glass=\(finalGlass) 宿主和内容一致", glass: finalGlass)

        let closingClassic = controller.classicPopoverForTest
        controller.toggle(relativeTo: button)
        Settings.liquidGlassEnabled = !finalGlass
        controller.openForSettingsCommandTest(relativeTo: button)
        Settings.liquidGlassEnabled = finalGlass
        controller.openForSettingsCommandTest(relativeTo: button)
        if controller.classicPopoverForTest !== closingClassic {
            controller.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: closingClassic))
        }
        spin(1.2)
        checkInstalledHost("关闭重开与来回切换交错最终 glass=\(finalGlass) 不出现空壳", glass: finalGlass)
        controller.handleOutsideClick()
        _ = runApplication(until: { !controller.isShownForTest }, timeout: 1.2)
        check("快速迁移最终 glass=\(finalGlass) 关闭后监听清空且没有系统写入",
              hostMonitorsAreRemoved(controller) && !controller.isOpen && modeRequests == 0 && batteryRequests == 0)
    }

    Settings.liquidGlassEnabled = true
    weak var releasedController: PopoverController?
    weak var releasedPanel: GlassPopoverPanel?
    weak var releasedRetiredPanel: GlassPopoverPanel?
    autoreleasepool {
        let retiring = PopoverController()
        releasedController = retiring
        retiring.openForSettingsCommandTest(relativeTo: button)
        releasedRetiredPanel = retiring.glassPanelForTest
        Settings.liquidGlassEnabled = false
        retiring.openForSettingsCommandTest(relativeTo: button)
        Settings.liquidGlassEnabled = true
        retiring.openForSettingsCommandTest(relativeTo: button)
        releasedPanel = retiring.glassPanelForTest
        check("释放测试先安装了真实玻璃面板监听", retiring.hasLocalEventMonitorForTest
              && retiring.lifetimeObserverCountForTest > 0)
    }
    check("打开状态释放 controller 不被监视器保留且面板不继续可见",
          releasedController == nil && releasedPanel?.isVisible != true
              && releasedRetiredPanel?.isVisible != true
              && button.postsFrameChangedNotifications == originalAnchorNotificationSetting)
}

// ---- 10. Settings 命令：一个窗口、同一入口、单一系统状态 ----
final class InteractionSettingsSection: SettingsSectionController {
    let identifier = "interaction"
    let title = "Interaction"
    let sidebarIcon: ModuleIconArtwork.SidebarIcon = .general
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 479, height: 228))
    private(set) var refreshCount = 0
    var onRefresh: (() -> Void)?

    func refresh() {
        refreshCount += 1
        onRefresh?()
    }
}

let interactionSection = InteractionSettingsSection()
let interactionSettings = SettingsWindowController(
    sections: [interactionSection],
    frameAutosaveName: nil
)
let settingsOwner = StatusItemController()
settingsOwner.configureSamplingRequestsForTest { _, _, _ in }
settingsOwner.configureSettingsWindowForTest(interactionSettings)
settingsOwner.wireSettingsPresentationForTest()

let previousMainMenu = NSApp.mainMenu
NSApp.mainMenu = nil
settingsOwner.installMainMenuForTest()
let appMenu = NSApp.mainMenu?.items.first?.submenu
let settingsMenuItem = appMenu?.items.first { $0.title == "Settings…" }
check("Settings 命令位于标准应用菜单",
      settingsMenuItem?.action == NSSelectorFromString("showSettings")
          && settingsMenuItem?.keyEquivalent == ","
          && settingsMenuItem?.keyEquivalentModifierMask == [.command])
check("应用菜单保留退出命令",
      appMenu?.items.contains { $0.title == "Quit Wattson" } == true)

let policyBeforeSettings = app.activationPolicy()
settingsOwner.openPopoverForSettingsCommandTest(relativeTo: button)
spin(0.35)
check("执行 Settings 前弹窗真实打开",
      settingsOwner.popoverIsOpenForTest
          && settingsOwner.popoverIsWatchingOutsideClicksForTest,
      "open=\(settingsOwner.popoverIsOpenForTest), watch=\(settingsOwner.popoverIsWatchingOutsideClicksForTest)")
settingsOwner.presentSettingsFromQuickMenuForTest()
check("Settings 回调前先清除弹窗意图和外部监听",
      !settingsOwner.popoverIsOpenForTest
          && !settingsOwner.popoverIsWatchingOutsideClicksForTest
          && interactionSettings.windowForTest?.isVisible == false)
let firstSettingsWindow = settingsOwner.settingsWindowForTest
let firstSettingsBecameKey = runApplication(
    until: { firstSettingsWindow?.isKeyWindow == true },
    timeout: 2.5
)
let firstSettingsKeyTitle = app.keyWindow?.title ?? "nil"
check("快捷菜单使 Settings 可见并成为键盘窗口",
      firstSettingsWindow?.isVisible == true
          && firstSettingsBecameKey,
      "visible=\(firstSettingsWindow?.isVisible == true), key=\(firstSettingsWindow?.isKeyWindow == true), active=\(app.isActive), keyTitle=\(firstSettingsKeyTitle), canKey=\(firstSettingsWindow?.canBecomeKey == true), same=\(firstSettingsWindow === interactionSettings.windowForTest)")

if let settingsMenuItem,
   let index = appMenu?.items.firstIndex(where: { $0 === settingsMenuItem }) {
    appMenu?.performActionForItem(at: index)
}
spin(0.05)
check("重复 Settings 命令复用同一窗口",
      firstSettingsWindow === settingsOwner.settingsWindowForTest
          && interactionSection.refreshCount >= 2)

firstSettingsWindow?.close()
settingsOwner.openPopoverForSettingsCommandTest(relativeTo: button)
spin(0.35)
settingsOwner.startDisplayClockForSettingsCommandTest()
check("Command-Comma 前弹窗和显示时钟都正在运行",
      settingsOwner.popoverIsOpenForTest
          && settingsOwner.popoverIsWatchingOutsideClicksForTest
          && settingsOwner.displayClockIsRunningForTest)

var commandPresentationState: (popoverOpen: Bool, outsideMonitor: Bool, displayClock: Bool)?
interactionSection.onRefresh = { [weak settingsOwner] in
    guard let settingsOwner else { return }
    commandPresentationState = (
        settingsOwner.popoverIsOpenForTest,
        settingsOwner.popoverIsWatchingOutsideClicksForTest,
        settingsOwner.displayClockIsRunningForTest
    )
}
let commandComma = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [.command],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    characters: ",",
    charactersIgnoringModifiers: ",",
    isARepeat: false,
    keyCode: 43
)
let commandHandled = commandComma.map {
    NSApp.mainMenu?.performKeyEquivalent(with: $0) ?? false
} ?? false
check("Command-Comma 在安排 Settings 窗口前同步停止弹窗和显示时钟",
      commandHandled
          && !settingsOwner.popoverIsOpenForTest
          && !settingsOwner.popoverIsWatchingOutsideClicksForTest
          && !settingsOwner.displayClockIsRunningForTest
          && firstSettingsWindow?.isVisible == false)
let reopenedSettingsBecameKey = runApplication(
    until: { firstSettingsWindow?.isKeyWindow == true },
    timeout: 2.5
)
let reopenedSettingsKeyTitle = app.keyWindow?.title ?? "nil"
check("Command-Comma 关闭后重开同一窗口",
      commandHandled
          && firstSettingsWindow === settingsOwner.settingsWindowForTest
          && firstSettingsWindow?.isVisible == true
          && reopenedSettingsBecameKey
          && commandPresentationState?.popoverOpen == false
          && commandPresentationState?.outsideMonitor == false
          && commandPresentationState?.displayClock == false,
      "handled=\(commandHandled), visible=\(firstSettingsWindow?.isVisible == true), key=\(firstSettingsWindow?.isKeyWindow == true), active=\(app.isActive), keyTitle=\(reopenedSettingsKeyTitle)")
interactionSection.onRefresh = nil
check("Settings 未改变 LSUIElement 的 accessory 激活策略",
      policyBeforeSettings == .accessory
          && app.activationPolicy() == policyBeforeSettings)

SystemBatteryIconController.configureForTest(initialHidden: true) { _, _ in
    fatalError("Settings command interaction must not contact an installed helper")
}
settingsOwner.beginSystemBatteryIconObservationForTest()
NotificationCenter.default.post(name: SystemBatteryIconController.didChange, object: nil)
check("状态项从共享系统电池图标缓存同步",
      settingsOwner.presentedSystemBatteryIconHiddenForTest == true)

weak var releasedStatusObserver: StatusItemController?
autoreleasepool {
    var observerOnlyOwner: StatusItemController? = StatusItemController()
    observerOnlyOwner?.beginSystemBatteryIconObservationForTest()
    releasedStatusObserver = observerOnlyOwner
    observerOnlyOwner = nil
}
check("系统电池图标观察者不阻止 StatusItem 释放",
      releasedStatusObserver == nil)

firstSettingsWindow?.close()
SystemBatteryIconController.resetTestConfiguration()
NSApp.mainMenu = previousMainMenu

// ---- 11. 真实控制器单采样时钟：重排 timer 不能吞掉打开事件 ----
// Intercept before the production coalescer/runtime so these checks exercise
// actual Timer replacement and deferred controller callbacks without IOKit or
// an installed helper. Reducer/history timing has separate deterministic tests.
weak var releasedSamplingOwner: StatusItemController?
autoreleasepool {
    let owner = StatusItemController()
    releasedSamplingOwner = owner
    var requests: [(history: Bool, fresh: Bool, supersedes: Bool)] = []
    owner.configureSamplingRequestsForTest { history, fresh, supersedes in
        requests.append((history, fresh, supersedes))
    }
    owner.setSamplingDisplayActiveForTest(true)
    let openingTimer = owner.samplingTimerForTest
    check("打开控制器创建有效的单采样 timer",
          openingTimer?.isValid == true
              && openingTimer?.tolerance == SamplingCadence.displayTolerance
              && owner.displayClockIsRunningForTest)

    // Force the periodic callback before DispatchQueue.main drains the opening
    // callback. It replaces the Timer, but not the identity of the opening.
    openingTimer?.fire()
    let periodicReplacement = owner.samplingTimerForTest
    check("周期回调使旧 timer 失效并安排唯一有效替代",
          openingTimer?.isValid == false
              && periodicReplacement?.isValid == true
              && periodicReplacement !== openingTimer)
    check("手动周期回调不读取硬件且不要求额外 fresh follow-up",
          requests.count == 1 && requests.first?.fresh == false
              && requests.first?.supersedes == false)
    var openingQueueDrained = false
    DispatchQueue.main.async { openingQueueDrained = true }
    _ = runApplication(until: { openingQueueDrained }, timeout: 1)
    check("timer 重建后真实打开回调仍请求一次 fresh follow-up",
          openingQueueDrained && requests.filter { $0.fresh }.count == 1
              && requests.allSatisfy { !$0.supersedes },
          "requests=\(requests)")

    let visibleTimer = owner.samplingTimerForTest
    owner.setSamplingDisplayActiveForTest(false)
    let hiddenTimer = owner.samplingTimerForTest
    check("关闭显示保留有效后台采样而不是停止全部采样",
          !owner.displayClockIsRunningForTest
              && visibleTimer?.isValid == false
              && hiddenTimer?.isValid == true
              && hiddenTimer !== visibleTimer
              && hiddenTimer?.tolerance == SamplingCadence.historyTolerance)
    requests.removeAll()
    hiddenTimer?.fire()
    check("关闭后的真实 timer 仍能请求采样并继续重排",
          requests.count == 1 && requests.first?.fresh == false
              && hiddenTimer?.isValid == false
              && owner.samplingTimerForTest?.isValid == true)

    // Neither opening callback has run when the visibility changes again.
    requests.removeAll()
    owner.setSamplingDisplayActiveForTest(true)
    let supersededOpeningTimer = owner.samplingTimerForTest
    owner.setSamplingDisplayActiveForTest(false)
    owner.setSamplingDisplayActiveForTest(true)
    let currentOpeningTimer = owner.samplingTimerForTest
    check("快速关闭重开只保留当前打开的有效 timer",
          supersededOpeningTimer?.isValid == false
              && currentOpeningTimer?.isValid == true
              && currentOpeningTimer !== supersededOpeningTimer)
    var reopeningQueueDrained = false
    DispatchQueue.main.async { reopeningQueueDrained = true }
    _ = runApplication(until: { reopeningQueueDrained }, timeout: 1)
    check("真实关闭重开拒绝旧打开回调且保留一次当前 fresh 请求",
          reopeningQueueDrained && requests.filter { $0.fresh }.count == 1
              && owner.samplingTimerForTest?.isValid == true,
          "requests=\(requests)")
    owner.setSamplingDisplayActiveForTest(false)
}
check("单采样 timer 和采集拦截器不会保留控制器", releasedSamplingOwner == nil)

// ---- 13. 短屏只缩小 viewport，仪表保持原尺寸，失效 anchor 不产生展示状态 ----
let viewportContent = PopoverContentViewController()
let naturalViewportHeight = viewportContent.preferredHeight
let shortViewportHeight = min(240, naturalViewportHeight / 2)
viewportContent.setViewportHeight(shortViewportHeight)
viewportContent.view.layoutSubtreeIfNeeded()
func firstScrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    return view.subviews.lazy.compactMap { firstScrollView(in: $0) }.first
}
if let scroll = firstScrollView(in: viewportContent.view), let document = scroll.documentView {
    check("短屏保持自然内容高度并提供原生滚动 viewport",
          abs(viewportContent.preferredHeight - naturalViewportHeight) < 0.5
              && document.frame.height >= naturalViewportHeight - 0.5
              && scroll.contentSize.height <= shortViewportHeight + 0.5
              && scroll.documentVisibleRect.height < document.frame.height)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: document.frame.height - scroll.contentSize.height))
    scroll.reflectScrolledClipView(scroll.contentView)
    check("短屏可滚到内容底部而不是裁掉 footer",
          scroll.documentVisibleRect.maxY >= document.frame.maxY - 0.5)
    viewportContent.setViewportHeight(naturalViewportHeight)
    viewportContent.view.layoutSubtreeIfNeeded()
    check("恢复足够高度后全量内容重新可见",
          scroll.documentVisibleRect.height >= document.frame.height - 0.5)
} else {
    check("短屏内容存在原生滚动容器", false)
}

let orphanedItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
if let orphanedButton = orphanedItem.button {
    NSStatusBar.system.removeStatusItem(orphanedItem)
    orphanedButton.removeFromSuperview()
    let anchorlessPopover = PopoverController()
    var invalidAnchorVisibilityEvents = 0
    anchorlessPopover.onVisibilityChange { _ in invalidAnchorVisibilityEvents += 1 }
    anchorlessPopover.toggle(relativeTo: orphanedButton)
    check("无 window 的失效状态项 anchor 不展示也不遗留监听",
          !anchorlessPopover.isOpen && !anchorlessPopover.isShownForTest
              && !anchorlessPopover.isWatchingOutsideClicks
              && invalidAnchorVisibilityEvents == 0)
} else {
    NSStatusBar.system.removeStatusItem(orphanedItem)
    check("状态项 anchor 回归具备测试 button", false)
}

// ---- 14. 续航具有独立分隔与留白，隐藏后真实宿主不留空白 ----
let runtimeRenderer = PopoverRuntimeView()
let runtimeSectionHeight = PopoverRuntimeView.preferredHeight
runtimeRenderer.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                               height: runtimeSectionHeight)
var runtimeSnapshots = headerSnapshots + [
    PowerSnapshot(percent: 8, batteryW: -10, systemW: 10),
    PowerSnapshot(percent: 41, batteryW: -10, systemW: 10, lowPowerMode: true),
]
for index in runtimeSnapshots.indices {
    switch runtimeSnapshots[index].state {
    case .charging: runtimeSnapshots[index].batteryTimeEstimate = .charging(42)
    case .pluggedIdle: runtimeSnapshots[index].batteryTimeEstimate = .full
    case .mixedSupply: runtimeSnapshots[index].batteryTimeEstimate = .notCharging
    case .onBattery:
        runtimeSnapshots[index].batteryTimeEstimate = .remaining(runtimeSnapshots[index].lowPowerMode ? 310 : runtimeSnapshots[index].percent < 20 ? 18 : 265)
    }
}
runtimeSnapshots.append(PowerSnapshot(percent: 41, batteryW: -10, systemW: 10,
                                      batteryTimeEstimate: .remaining(Int(Int32.max))))
runtimeSnapshots.append(PowerSnapshot(percent: 41, batteryW: -10, systemW: 10, batteryTimeEstimate: .remaining(nil)))
runtimeSnapshots.append(PowerSnapshot(percent: 41, plugged: true, adapterW: 40, batteryW: 20,
                                      systemW: 20, batteryTimeEstimate: .charging(nil)))
runtimeSnapshots.append(PowerSnapshot(percent: 41, batteryW: -10, systemW: 10))
check("独立续航行在全部供电状态和读取失败时实际布局不截断",
      runtimeSnapshots.allSatisfy { runtimeRenderer.layoutFitsForTest(snapshot: $0) }
          && runtimeRenderer.layoutFitsForTest(snapshot: runtimeSnapshots[2], degraded: true))
let runtimeSectionLayout = runtimeRenderer.sectionLayoutForTest
check("续航独立分区有细分割线，左侧时钟与右侧标题时间对齐",
      runtimeSectionHeight == 88 && runtimeSectionLayout.hasTopSeparator
          && runtimeRenderer.bounds.contains(runtimeSectionLayout.iconWellFrame)
          && runtimeSectionLayout.iconWellFrame.contains(runtimeSectionLayout.iconFrame)
          && runtimeSectionLayout.valueFrame.minX - runtimeSectionLayout.iconWellFrame.maxX >= 12
          && runtimeSectionLayout.titleFrame.minX == runtimeSectionLayout.valueFrame.minX
          && runtimeSectionLayout.titleFrame.maxY < runtimeSectionLayout.valueFrame.minY
          && runtimeSectionLayout.valueFontSize > runtimeSectionLayout.titleFontSize)
if #available(macOS 26.0, *), !screenLocked, let button = item.button {
    let previousModules = Settings.Module.allCases.map { ($0, Settings.isModuleVisible($0)) }
    let previousGlass = Settings.liquidGlassEnabled
    let previousStyle = Settings.liquidGlassStyle
    defer {
        for (module, visible) in previousModules { Settings.setModule(module, visible: visible) }
        Settings.liquidGlassEnabled = previousGlass
        Settings.liquidGlassStyle = previousStyle
    }
    // Keep natural content below the 1024×768 VM's viewport cap so its native
    // window exposes the full runtime height, not only the uncapped remainder.
    // previousModules restores both fixture changes when this scope exits.
    Settings.setModule(.flow, visible: false)
    Settings.setModule(.history, visible: false)
    Settings.setModule(.topProcesses, visible: false)
    func runtimeDescendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + runtimeDescendants($0) }
    }
    for (name, glass, style) in [("Classic", false, Settings.LiquidGlassStyle.regular),
                                ("Standard", true, .regular), ("Clear", true, .clear)] {
        Settings.liquidGlassEnabled = glass
        Settings.liquidGlassStyle = style
        Settings.setModule(.runtime, visible: true)
        let controller = PopoverController()
        controller.update(snapshot: runtimeSnapshots[2], history: [36.9], peak: 36.9, degraded: false)
        defer { controller.handleOutsideClick(); spin(0.8) }
        controller.openForSettingsCommandTest(relativeTo: button)
        spin(0.8)
        guard let root = controller.contentViewForTest, let window = root.window,
              let runtime = runtimeDescendants(root).compactMap({ $0 as? PopoverRuntimeView }).first,
              let footer = runtimeDescendants(root).compactMap({ $0 as? PopoverFooterView }).first else {
            check("\(name) 独立续航具有真实宿主和生产视图", false)
            continue
        }
        root.layoutSubtreeIfNeeded()
        func footerScreenY() -> CGFloat {
            footer.window?.convertPoint(toScreen: footer.convert(.zero, to: nil)).y ?? .nan
        }
        let footerY = footerScreenY()
        let height = window.frame.height
        Settings.setModule(.runtime, visible: false)
        spin(0.3)
        root.layoutSubtreeIfNeeded()
        let hiddenFooterY = footerScreenY()
        check("\(name) 关闭续航后真实仪表与宿主移除完整续航栏目高度",
              runtime.isHidden && abs(hiddenFooterY - footerY - runtimeSectionHeight) < 0.5
                  && abs(height - window.frame.height - runtimeSectionHeight) < 0.5,
              "footer=\(footerY)→\(hiddenFooterY); height=\(height)→\(window.frame.height)")
        controller.handleOutsideClick(); spin(0.8)
        controller.openForSettingsCommandTest(relativeTo: button); spin(0.8)
        check("\(name) 关闭重开后继续隐藏已取消勾选的续航",
              controller.isShownForTest && runtime.isHidden && !Settings.isModuleVisible(.runtime))
        Settings.setModule(.runtime, visible: true)
        spin(0.3)
        root.layoutSubtreeIfNeeded()
        check("\(name) 重新开启续航后仪表与真实宿主恢复原坐标",
              !runtime.isHidden && abs(footerScreenY() - footerY) < 0.5
                  && abs((root.window?.frame.height ?? 0) - height) < 0.5)
    }
}

// ---- 14a. Process Activity: keyboard focus follows identity across reranking ----
if !screenLocked {
    // Mock identities are valid, but the handler records requests only. This
    // fixture never contacts the helper or terminates a process.
    func focusProcess(_ pid: Int32, _ name: String, tokenVersion: UInt32 = 0) -> EnergyProcess {
        var audit = audit_token_t()
        audit.val.1 = geteuid()
        audit.val.5 = UInt32(bitPattern: pid)
        audit.val.7 = tokenVersion
        return EnergyProcess(pid: pid, name: name, energyImpact: 40,
                             cpuPercent: 40, idleWakeupsPerSecond: 0,
                             terminationIdentity: ProcessIdentity(
                                pid: pid, startedAt: UInt64(pid),
                                auditToken: withUnsafeBytes(of: &audit) { Data($0) }))
    }
    let a = focusProcess(41001, "Focus A")
    let b = focusProcess(41002, "Focus B")
    let c = focusProcess(41003, "Focus C")
    let window = NSWindow(contentRect: NSRect(x: 80, y: 100, width: 380, height: 270),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.makeFirstResponder(nil); window.close() }
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    check("进程键盘焦点回归具有真实 key window",
          runApplication(until: { window.isKeyWindow }, timeout: 1))
    func sendFocusKey(_ code: UInt16, _ characters: String) {
        window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil,
                                         characters: characters, charactersIgnoringModifiers: characters,
                                         isARepeat: false, keyCode: code)!)
    }
    func focusFixture() -> TopProcessesView {
        window.makeFirstResponder(nil)
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 270))
        let view = TopProcessesView()
        view.frame = NSRect(x: 20, y: 40, width: 328,
                           height: TopProcessesView.preferredHeight(count: 3))
        window.contentView!.addSubview(view)
        view.update(state: .ready([a, b, c]), count: 3)
        view.layoutSubtreeIfNeeded()
        _ = view.processRowsForTest[0].accessibilityPerformPress()
        return view
    }
    for compact in [false, true] {
        let view = focusFixture()
        let row = view.processRowsForTest[0]
        check("进程行接受真实键盘焦点 compact=\(compact)",
              window.makeFirstResponder(row) && window.firstResponder === row)
        view.update(state: .ready([b, a, c]), count: 3, compact: compact)
        view.layoutSubtreeIfNeeded()
        check("重排时选择和行焦点均跟随进程身份 compact=\(compact)",
              view.selectedProcessForTest?.terminationIdentity == a.terminationIdentity
                  && window.firstResponder === view.processRowsForTest[1])
        sendFocusKey(49, " ")
        check("真实 window 分发空格只取消原进程选择并保留焦点 compact=\(compact)",
              view.selectedProcessForTest == nil && window.firstResponder === view.processRowsForTest[1])
    }
    do {
        let view = focusFixture()
        _ = view.processRowsForTest[1].accessibilityPerformPress()
        _ = window.makeFirstResponder(view.processRowsForTest[0])
        view.update(state: .ready([b, a, c]), count: 3)
        check("选择 B 与焦点 A 分离时重排分别保留各自身份",
              view.selectedProcessForTest?.terminationIdentity == b.terminationIdentity
                  && window.firstResponder === view.processRowsForTest[1])
        sendFocusKey(125, "\u{F701}")
        check("真实 window 下箭头从 A 的新排名移到 C",
              view.selectedProcessForTest?.terminationIdentity == c.terminationIdentity
                  && window.firstResponder === view.processRowsForTest[2])
    }
    do {
        let view = focusFixture()
        let action = view.forceQuitButtonsForTest[0]
        if window.makeFirstResponder(action), window.firstResponder === action {
            var requested: [EnergyProcess] = []
            view.forceQuitHandler = { requested.append($0) }
            for (name, values, index) in [("后移", [b, a, c], 1), ("前移", [a, b, c], 0)] {
                view.update(state: .ready(values), count: 3)
                view.layoutSubtreeIfNeeded()
                check("\(name) 重排时原生强退按钮焦点跟随原进程",
                      view.selectedProcessForTest?.terminationIdentity == a.terminationIdentity
                          && window.firstResponder === view.forceQuitButtonsForTest[index])
                let previousRequests = requested.count
                (window.firstResponder as? NSButton)?.performClick(nil)
                check("\(name) 后焦点按钮仅请求原进程身份而不误操作新排名",
                      requested.count == previousRequests + 1
                          && requested.last?.terminationIdentity == a.terminationIdentity
                          && window.firstResponder === view.forceQuitButtonsForTest[index])
            }
        } else {
            log("PROCESS_ACTION_BUTTON_FOCUS_UNEXERCISED: AppKit rejected native button focus")
        }
    }
    for (name, state, count) in [("移除", TopProcessesState.ready([b, c]), 3),
                                ("掉出 Top N", .ready([b, a, c]), 1),
                                ("仅 audit token 更换", .ready([focusProcess(a.pid, a.name, tokenVersion: 1), b, c]), 3)] {
        let view = focusFixture()
        let rows = view.processRowsForTest
        let actions = view.forceQuitButtonsForTest
        _ = window.makeFirstResponder(rows[0])
        view.update(state: state, count: count)
        check("\(name) 清除选择并退离已换绑或隐藏的进程焦点",
              view.selectedProcessForTest == nil
                  && !rows.contains { $0 === window.firstResponder }
                  && !actions.contains { $0 === window.firstResponder })
    }
    do {
        let view = focusFixture()
        let text = NSTextField(string: "Unrelated editor")
        text.frame = NSRect(x: 20, y: 10, width: 280, height: 24)
        window.contentView!.addSubview(text)
        check("外部文本框可取得实际 field editor", window.makeFirstResponder(text)
              && window.firstResponder is NSTextView)
        let editor = window.firstResponder
        view.update(state: .ready([b, a, c]), count: 3)
        check("进程重排不抢占外部文本编辑焦点", window.firstResponder === editor)
        for (name, state, count) in [("缩小 Top N", TopProcessesState.ready([b, a, c]), 1),
                                    ("空列表", .ready([]), 1), ("失效", .unavailable, 3)] {
            view.update(state: state, count: count)
            check("进程列表\(name)不抢占外部文本编辑焦点", window.firstResponder === editor)
        }
    }
}

// ---- 14b. History: real hosted layers, bounded motion and lifecycle cancellation ----
var historyMotionChecksSkipped = false
if !screenLocked {
    let previousMotion = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"]
    let previousGlass = Settings.liquidGlassEnabled
    let previousModules = Settings.Module.allCases.map { ($0, Settings.isModuleVisible($0)) }
    defer {
        if let previousMotion { setenv("WATTSON_FORCE_REDUCE_MOTION", previousMotion, 1) }
        else { unsetenv("WATTSON_FORCE_REDUCE_MOTION") }
        for (module, visible) in previousModules { Settings.setModule(module, visible: visible) }
        Settings.liquidGlassEnabled = previousGlass
    }
    let skipHistoryMotion = initialReduceMotionOverride != "0" && initialReduceMotionOverride != "1"
        && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    if skipHistoryMotion { unsetenv("WATTSON_FORCE_REDUCE_MOTION") }
    else { setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1) }
    Settings.liquidGlassEnabled = false
    for module in Settings.Module.allCases { Settings.setModule(module, visible: module == .history) }

    func historyAnimations(_ layer: CALayer?) -> [(String, CAAnimation)] {
        guard let layer else { return [] }
        let own = (layer.animationKeys() ?? []).compactMap { key -> (String, CAAnimation)? in
            layer.animation(forKey: key).map { (key, $0) }
        }
        return own + (layer.sublayers ?? []).flatMap { historyAnimations($0) }
            + (layer.mask.map { historyAnimations($0) } ?? [])
    }
    func historyPathElements(_ path: CGPath) -> [(CGPathElementType, [CGPoint])] {
        var elements: [(CGPathElementType, [CGPoint])] = []
        path.applyWithBlock {
            let element = $0.pointee
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            elements.append((element.type, (0..<count).map { element.points[$0] }))
        }
        return elements
    }
    func alignedHistoryPathAnimation(_ animation: CAAnimation) -> Bool {
        guard let paths = historyStrokePaths(animation), let first = paths.first else { return false }
        let topology = historyPathElements(first).map { $0.0 }
        return !topology.isEmpty && paths.allSatisfy { path in
            let elements = historyPathElements(path)
            return elements.map { $0.0 } == topology
                && elements.flatMap { $0.1 }.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        }
    }
    func historyStrokePaths(_ animation: CAAnimation) -> [CGPath]? {
        guard let property = animation as? CAPropertyAnimation, property.keyPath == "path" else { return nil }
        let values: [Any]
        if let animation = animation as? CABasicAnimation,
           let from = animation.fromValue, let to = animation.toValue {
            values = [from, to]
        } else if let animation = animation as? CAKeyframeAnimation,
                  let frames = animation.values, frames.count == 9 {
            values = frames
        } else {
            return nil
        }
        var paths: [CGPath] = []
        for value in values {
            guard CFGetTypeID(value as CFTypeRef) == CGPath.typeID else { return nil }
            paths.append(value as! CGPath)
        }
        return paths
    }
    func validHistoryStroke(_ animation: CAAnimation, viewport: CATransform3D) -> Bool {
        guard let paths = historyStrokePaths(animation), let targetPath = paths.last else { return false }
        guard paths.count == 2 || paths.count == 9 else { return false }
        let target = historyPathElements(targetPath)
        guard !target.isEmpty else { return false }
        for (index, path) in paths.enumerated() {
            let elements = historyPathElements(path)
            guard elements.map({ $0.0 }) == target.map({ $0.0 }) else { return false }
            let progress = CGFloat(index) / CGFloat(paths.count - 1)
            let sx = viewport.m41 * (1 - progress)
            let sy = 1 + (viewport.m22 - 1) * (1 - progress)
            for (actual, final) in zip(elements, target) {
                guard actual.1.count == final.1.count,
                      actual.1.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return false }
                guard let a = actual.1.last, let b = final.1.last else { continue }
                let expectedY = HistoryView.chartHeight + (b.y - HistoryView.chartHeight) * sy
                guard abs(a.x - b.x - sx) < 0.01, abs(a.y - expectedY) < 0.01 else { return false }
            }
        }
        return true
    }
    func historyViewport(_ path: CGPath, target: CGPath) -> CATransform3D? {
        let shown = historyPathElements(path), final = historyPathElements(target)
        guard shown.map({ $0.0 }) == final.map({ $0.0 }),
              let first = shown.first?.1.last, let last = final.first?.1.last else { return nil }
        var transform = CATransform3DIdentity
        transform.m41 = first.x - last.x
        var largest: CGFloat = 0
        for (a, b) in zip(shown, final) {
            guard let p = a.1.last, let q = b.1.last else { continue }
            let height = HistoryView.chartHeight - q.y
            if height > largest {
                largest = height
                transform.m22 = (HistoryView.chartHeight - p.y) / height
            }
        }
        return largest > 0 && transform.m22.isFinite && transform.m22 > 0 ? transform : nil
    }
    func synchronizedHistoryPaths(_ stroke: CAAnimation?, _ fill: CAAnimation?) -> Bool {
        guard let stroke, let fill, alignedHistoryPathAnimation(stroke), alignedHistoryPathAnimation(fill),
              let a = historyStrokePaths(stroke), let b = historyStrokePaths(fill),
              abs(stroke.beginTime - fill.beginTime) < 0.000_001,
              stroke.duration == fill.duration, stroke.timingFunction == fill.timingFunction else { return false }
        return zip(a, b).allSatisfy { line, area in
            let p = historyPathElements(line).filter { $0.0 == .addCurveToPoint }.map { $0.1 }
            let q = historyPathElements(area).filter { $0.0 == .addCurveToPoint }.map { $0.1 }
            return !p.isEmpty && p == q
        }
    }
    func historyCubicMidpoint(_ path: CGPath, index: Int) -> CGPoint? {
        var current = CGPoint.zero
        var midpoints: [CGPoint] = []
        for (type, points) in historyPathElements(path) {
            if type == .addCurveToPoint {
                midpoints.append(CGPoint(x: (current.x + 3 * points[0].x + 3 * points[1].x + points[2].x) / 8,
                                         y: (current.y + 3 * points[0].y + 3 * points[1].y + points[2].y) / 8))
            }
            if let last = points.last { current = last }
        }
        return midpoints.indices.contains(index) ? midpoints[index] : nil
    }
    func historyDescendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + historyDescendants($0) }
    }
    let fixture = HistoryView()
    fixture.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                          height: HistoryView.preferredHeight)
    let container = NSView(frame: fixture.bounds)
    container.addSubview(fixture)
    let fixtureWindow = NSWindow(contentRect: fixture.bounds, styleMask: [.borderless],
                                 backing: .buffered, defer: false)
    fixtureWindow.isReleasedWhenClosed = false
    fixtureWindow.contentView = container
    fixtureWindow.orderFront(nil)
    fixture.layoutSubtreeIfNeeded()
    fixture.setPresentationActive(true)
    fixture.setAnimationsEnabled(true)
    defer { fixture.setPresentationActive(false); fixtureWindow.close() }
    var values = [40.0, 45.0]
    var times = [0.0, 2.0]
    func updateFixture(appending: Bool = true) {
        if appending { values.append(43); times.append(times.last! + 2) }
        fixture.update(samples: values, peak: 45, color: .systemBlue,
                       timing: HistoryChartTiming(sampledAt: times, referenceTime: times.last!))
        CATransaction.flush()
    }
    updateFixture(appending: false)
    check("History 首帧直接呈现而不伪造滚动", !fixture.hasChartAnimationForTest)

    // Explicit DEBUG overrides run the complete motion checks even on CI hosts
    // with Reduce Motion enabled. Without one, keep the real system policy.
    if skipHistoryMotion {
        updateFixture()
        check("History 遵守系统减少动态效果", !fixture.hasChartAnimationForTest)
        historyMotionChecksSkipped = true
        log("HISTORY_MOTION_CHECKS_SKIPPED: system Reduce Motion is enabled")
    } else {
        func settleHistoryFixture(_ context: String, view: HistoryView = fixture) -> Bool {
            let started = CACurrentMediaTime()
            let settled = runApplication(until: { !view.hasChartAnimationForTest }, timeout: 1)
            if !settled {
                let remaining = historyAnimations(view.layer).map {
                    "\($0.0):\($0.1.duration)s"
                }.joined(separator: ",")
                log("HISTORY_COMPLETION_TIMEOUT \(context) elapsed=\(CACurrentMediaTime() - started) remaining=\(remaining)")
                let now = CACurrentMediaTime()
                func logClocks(_ layer: CALayer?) {
                    guard let layer else { return }
                    for key in layer.animationKeys() ?? [] {
                        guard let animation = layer.animation(forKey: key) else { continue }
                        let shown = layer.presentation()
                        log("HISTORY_OWNER_CLOCK key=\(key) localNow=\(layer.convertTime(now, from: nil)) speed=\(layer.speed) offset=\(layer.timeOffset) begin=\(layer.beginTime) presentationNow=\(shown?.convertTime(now, from: nil) ?? -1) animationBegin=\(animation.beginTime) duration=\(animation.duration) animationSpeed=\(animation.speed) animationOffset=\(animation.timeOffset) removed=\(animation.isRemovedOnCompletion)")
                    }
                    for child in layer.sublayers ?? [] { logClocks(child) }
                    logClocks(layer.mask)
                }
                logClocks(view.layer)
            }
            return settled
        }
        updateFixture()
        let animations = historyAnimations(fixture.layer)
        let animationKeys = Set(animations.map { $0.0 })
        check("History 连续真实采样启动同步描边、填充与末端动画",
              Set(["history.fill", "history.head", "history.stroke"]).isSubset(of: animationKeys)
                  && animationKeys.isSubset(of: ["history.head", "history.stroke", "history.fill", "history.reveal",
                                                 "history.gradient.startPoint", "history.gradient.endPoint"])
                  && animations.count == animationKeys.count && fixture.hasChartAnimationForTest)
        check("History 动画限于 180 ms 且没有重复、自动反向或常驻填充",
              animations.count >= 3 && animations.allSatisfy {
                  abs($0.1.duration - 0.18) < 0.000_001
                      && $0.1.repeatCount == 0 && $0.1.repeatDuration == 0
                      && !$0.1.autoreverses && $0.1.isRemovedOnCompletion
              })
        var ordinaryViewport = CATransform3DIdentity
        ordinaryViewport.m41 = CGFloat(2 / HistoryChartTiming.window) * PopoverStyle.contentWidth
        let ordinaryStroke = animations.first { $0.0 == "history.stroke" }?.1
        check("History 平移描边保持路径拓扑及真实采样位置",
              (animations.first { $0.0 == "history.head" }?.1 as? CAKeyframeAnimation)?.keyPath
                  == "position"
                  && ordinaryStroke is CABasicAnimation
                  && ordinaryStroke.map { validHistoryStroke($0, viewport: ordinaryViewport) } == true
                  && synchronizedHistoryPaths(ordinaryStroke, animations.first { $0.0 == "history.fill" }?.1))
        check("History 短过渡完成后原生图层自行静止", settleHistoryFixture("ordinary-scroll"))

        let cancellations: [(String, () -> Void, () -> Void)] = [
            ("结束呈现", { fixture.setPresentationActive(false) }, { fixture.setPresentationActive(true) }),
            ("关闭动画策略", { fixture.setAnimationsEnabled(false) }, { fixture.setAnimationsEnabled(true) }),
            ("隐藏视图", { fixture.isHidden = true }, { fixture.isHidden = false }),
            ("脱离窗口", { fixture.removeFromSuperview() }, { container.addSubview(fixture) }),
        ]
        for (name, cancel, restore) in cancellations {
            updateFixture()
            check("History \(name)前确实有活动动画", fixture.hasChartAnimationForTest)
            cancel()
            check("History \(name)立即移除动画", !fixture.hasChartAnimationForTest)
            updateFixture()
            check("History \(name)期间新采样不重启动画", !fixture.hasChartAnimationForTest)
            restore()
            check("History 恢复\(name)状态不重播旧过渡", !fixture.hasChartAnimationForTest)
        }

        // Axis changes must move through real presentation layers, including
        // when another reading arrives before the previous transition finishes.
        func historyLayers(_ layer: CALayer?) -> [CALayer] {
            guard let layer else { return [] }
            return [layer] + (layer.sublayers ?? []).flatMap { historyLayers($0) }
                + (layer.mask.map { historyLayers($0) } ?? [])
        }
        func viewportAnimation() -> (CAShapeLayer, CAPropertyAnimation)? {
            for case let layer as CAShapeLayer in historyLayers(fixture.layer) {
                if let animation = layer.animation(forKey: "history.stroke") as? CAPropertyAnimation {
                    return (layer, animation)
                }
            }
            return nil
        }
        func animationStart(_ animation: CAPropertyAnimation) -> CATransform3D? {
            guard let paths = historyStrokePaths(animation), let first = paths.first, let last = paths.last else { return nil }
            return historyViewport(first, target: last)
        }
        func projectedSample(_ watts: Double, sampledAt: Double, reference: Double,
                             ceiling: Double, transform: CATransform3D) -> CGPoint {
            CGPoint(x: CGFloat(1 - (reference - sampledAt) / HistoryChartTiming.window)
                            * PopoverStyle.contentWidth + transform.m41,
                    y: HistoryView.chartHeight * (1 - CGFloat(watts / ceiling) * transform.m22))
        }
        var axisValues = values
        var axisTimes = times
        func updateAxis(appending watts: Double) {
            axisValues.append(watts)
            axisTimes.append(axisTimes.last! + 2)
            if axisValues.count > 60 {
                axisValues.removeFirst()
                axisTimes.removeFirst()
            }
            fixture.update(samples: axisValues, peak: axisValues.max() ?? 0, color: .systemBlue,
                           timing: .init(sampledAt: axisTimes, referenceTime: axisTimes.last!))
            CATransaction.flush()
        }
        updateAxis(appending: 180)
        let expansion = viewportAnimation()
        let expansionStart = expansion.flatMap { animationStart($0.1) }
        check("History 新峰值扩轴使用有界的原生路径动画",
              fixture.chartCeilingForTest == 250 && expansion?.1.keyPath == "path"
                  && abs((expansion?.1.duration ?? 0) - 0.35) < 0.000_001
                  && expansion?.1.repeatCount == 0 && expansion?.1.autoreverses == false
                  && expansion?.1.isRemovedOnCompletion == true
                  && abs((expansionStart?.m22 ?? 0) - 250.0 / 55) < 0.000_001
                  && (expansionStart?.m41 ?? 0) > 0)
        let expansionPaths = historyAnimations(fixture.layer).filter {
            ($0.1 as? CAPropertyAnimation)?.keyPath == "path"
        }
        let expansionStroke = expansionPaths.first { $0.0 == "history.stroke" }?.1
        check("History 扩轴描边保持路径拓扑及真实采样位置",
              expansionStroke is CAKeyframeAnimation && expansionStroke.flatMap { stroke in
                  expansionStart.map { validHistoryStroke(stroke, viewport: $0) }
              } == true
                  && synchronizedHistoryPaths(expansionStroke,
                      expansionPaths.first { $0.0 == "history.fill" }?.1))
        let strokeLayer = historyLayers(fixture.layer).compactMap { $0 as? CAShapeLayer }.first {
            $0.animation(forKey: "history.stroke") != nil
        }
        let headLayer = historyLayers(fixture.layer).first {
            abs($0.bounds.width - 5.2) < 0.000_001
                && abs($0.bounds.height - 5.2) < 0.000_001 && $0.cornerRadius == 2.6
        }
        spin(0.1)
        let midExpansion = strokeLayer?.presentation()?.path.flatMap { path in
            fixture.chartPathForTest.flatMap { historyViewport(path, target: $0) }
        }
        check("History 扩轴中间帧位于起始范围与目标范围之间",
              (midExpansion?.m22 ?? 0) > 1
                  && (midExpansion?.m22 ?? .infinity) < (expansionStart?.m22 ?? 0))
        check("History 变轴保持末端圆点尺寸固定",
              headLayer?.presentation()?.bounds.size == CGSize(width: 5.2, height: 5.2)
                  && headLayer?.presentation()?.transform.m11 == 1
                  && headLayer?.presentation()?.transform.m22 == 1)
        var constantStrokeWidth = false
        if let presented = strokeLayer?.presentation() {
            let origin = presented.convert(CGPoint.zero, to: nil)
            let unitX = presented.convert(CGPoint(x: 1, y: 0), to: nil)
            let unitY = presented.convert(CGPoint(x: 0, y: 1), to: nil)
            let sx = hypot(Double(unitX.x - origin.x), Double(unitX.y - origin.y))
            let sy = hypot(Double(unitY.x - origin.x), Double(unitY.y - origin.y))
            constantStrokeWidth = abs(presented.lineWidth - 1.6) < 0.000_001
                && abs(sx - 1) < 0.000_001 && abs(sy - 1) < 0.000_001
        }
        check("History 变轴时描边宽度保持 1.6 点", constantStrokeWidth)
        let retainedTimestamp = axisTimes.first!
        let oldReference = axisTimes.last!
        let oldCeiling = fixture.chartCeilingForTest
        let beforeStrokePath = strokeLayer?.presentation()?.path
        let beforeRetarget = beforeStrokePath.flatMap { path in
            fixture.chartPathForTest.flatMap { historyViewport(path, target: $0) }
        }
        updateAxis(appending: 300)
        let retarget = viewportAnimation()
        let retargetStart = retarget.flatMap { animationStart($0.1) }
        let retargetStroke = historyAnimations(fixture.layer).first { $0.0 == "history.stroke" }?.1
        if let beforeStrokePath,
           let oldAnchor = historyPathElements(beforeStrokePath).first?.1.first,
           let firstStroke = retargetStroke.flatMap({ historyStrokePaths($0) })?.first,
           let newAnchor = historyPathElements(firstStroke).first?.1.first {
            check("History 中断变轴直接接续实际描边中的保留采样点",
                  abs(oldAnchor.x - newAnchor.x) < 0.5 && abs(oldAnchor.y - newAnchor.y) < 0.5)
        } else {
            check("History 中断变轴直接接续实际描边中的保留采样点", false)
        }
        if let beforeRetarget, let retargetStart {
            let before = projectedSample(axisValues[0], sampledAt: retainedTimestamp,
                                         reference: oldReference, ceiling: oldCeiling,
                                         transform: beforeRetarget)
            let after = projectedSample(axisValues[0], sampledAt: retainedTimestamp,
                                        reference: axisTimes.last!, ceiling: fixture.chartCeilingForTest,
                                        transform: retargetStart)
            check("History 中断扩轴从可见坐标接续保留采样点",
                  fixture.chartCeilingForTest == 350
                      && abs(before.x - after.x) < 0.5 && abs(before.y - after.y) < 0.5
                      && abs(retargetStart.m22 - 350.0 / 250) > 0.5)
        } else {
            check("History 中断扩轴从可见坐标接续保留采样点", false)
        }
        if let (layer, _) = retarget, let clip = layer.superlayer {
            let shown = layer.presentation() ?? layer
            let baseline = shown.convert(CGPoint(x: 0, y: HistoryView.chartHeight), to: clip.presentation() ?? clip)
            check("History 扩缩范围始终以图表底边为原点",
                  abs(baseline.x) < 0.000_001 && abs(baseline.y - HistoryView.chartHeight) < 0.000_001
                      && CATransform3DIsIdentity(shown.transform))
        } else {
            check("History 扩缩范围始终以图表底边为原点", false)
        }
        check("History 中断后的扩轴完成并自动静止", settleHistoryFixture("retargeted-axis"))

        // Evict the two high readings through the same 60-slot series. Only
        // then advance the four real sample ticks required by scale hysteresis.
        for _ in 0..<60 { updateAxis(appending: 43) }
        spin(0.3)
        check("History 旧峰值离开窗口后仍保留缩轴迟滞",
              axisValues.allSatisfy { $0 == 43 } && fixture.chartCeilingForTest == 350)
        for tick in 1...4 {
            updateAxis(appending: 43)
            if tick < 4 {
                check("History 缩轴第\(tick)个两秒采样仍保持旧范围",
                      fixture.chartCeilingForTest == 350)
            }
        }
        let contraction = viewportAnimation()
        let contractionStart = contraction.flatMap { animationStart($0.1) }
        check("History 八秒迟滞结束后缩轴平滑展开低功率数据",
              fixture.chartCeilingForTest == 50
                  && abs((contractionStart?.m22 ?? 0) - 50.0 / 350) < 0.000_001)
        spin(0.1)
        let contractionScale = contraction?.0.presentation()?.path.flatMap { path in
            fixture.chartPathForTest.flatMap { historyViewport(path, target: $0)?.m22 }
        }
        check("History 缩轴中间帧连续接近最终范围",
              (contractionScale ?? 0) > (contractionStart?.m22 ?? 1)
                  && (contractionScale ?? .infinity) < 1)
        check("History 缩轴结束后原生图层自行静止", settleHistoryFixture("contracted-axis"))

        var cancellationPeak = 300.0
        for (name, cancel, restore) in cancellations {
            cancellationPeak *= 2
            updateAxis(appending: cancellationPeak)
            check("History \(name)前确实有活动变轴动画", viewportAnimation() != nil)
            cancel()
            check("History \(name)立即移除变轴与末端动画", !fixture.hasChartAnimationForTest)
            cancellationPeak *= 2
            updateAxis(appending: cancellationPeak)
            check("History \(name)期间新峰值不重启变轴", !fixture.hasChartAnimationForTest)
            restore()
            check("History 恢复\(name)状态不重播旧变轴", !fixture.hasChartAnimationForTest)
        }

        // Adding 150 W changes the terminal tangent of the retained 0→100 W
        // interval. Freeze only this fixture's layer clock to inspect its exact
        // first composited frame, rather than racing a running animation.
        fixture.update(samples: [], peak: 0, color: .systemBlue,
                       timing: .init(sampledAt: [], referenceTime: 0))
        fixture.update(samples: [0, 0, 100], peak: 100, color: .systemBlue,
                       timing: .init(sampledAt: [0, 2, 4], referenceTime: 4))
        CATransaction.flush()
        spin(0.02)
        let oldTailPath = fixture.chartPathForTest
        let oldTailCeiling = fixture.chartCeilingForTest
        if let timeline = fixture.layer {
            let pausedAt = timeline.convertTime(CACurrentMediaTime(), from: nil)
            PopoverStyle.setWithoutAnimation {
                timeline.speed = 0
                timeline.timeOffset = pausedAt
            }
            fixture.update(samples: [0, 0, 100, 150], peak: 150, color: .systemBlue,
                           timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 6))
            CATransaction.flush()
            spin(0.03)
            let tailLine = historyLayers(fixture.layer).compactMap { $0 as? CAShapeLayer }.first {
                $0.animation(forKey: "history.stroke") != nil
            }
            let targetTailPath = fixture.chartPathForTest
            let targetTailCeiling = fixture.chartCeilingForTest
            if let oldTailPath, let targetTailPath,
               let oldMidpoint = historyCubicMidpoint(oldTailPath, index: 1),
               let targetMidpoint = historyCubicMidpoint(targetTailPath, index: 1),
               let visiblePath = tailLine?.presentation()?.path,
               let visiblePoint = historyCubicMidpoint(visiblePath, index: 1) {
                check("History 新增采样首帧保留原区间的实际呈现中点",
                      abs(visiblePoint.x - oldMidpoint.x) < 0.01
                          && abs(visiblePoint.y - oldMidpoint.y) < 0.01)
                let oldRawMidpoint = (1 - oldMidpoint.y / HistoryView.chartHeight) * oldTailCeiling
                let newRawMidpoint = (1 - targetMidpoint.y / HistoryView.chartHeight) * targetTailCeiling
                check("History 末段回归夹具确实覆盖新增样本造成的切线变化",
                      abs(oldRawMidpoint - 31.25) < 0.000_001
                          && abs(newRawMidpoint - 125.0 / 3) < 0.000_001
                          && abs(oldRawMidpoint - newRawMidpoint) > 10)
            } else {
                check("History 新增采样首帧保留原区间的实际呈现中点", false)
                check("History 末段回归夹具确实覆盖新增样本造成的切线变化", false)
            }
        } else {
            check("History 新增采样首帧保留原区间的实际呈现中点", false)
        }
        // Clock surgery is only for the exact first-frame assertion above.
        // Exercise natural completion on a fresh production layer tree whose
        // time space has never been paused, without cancellation during the wait.
        fixture.setPresentationActive(false)
        fixture.removeFromSuperview()
        let completionFixture = HistoryView()
        completionFixture.frame = container.bounds
        container.addSubview(completionFixture)
        completionFixture.layoutSubtreeIfNeeded()
        completionFixture.setPresentationActive(true)
        completionFixture.setAnimationsEnabled(true)
        completionFixture.update(samples: [0, 0, 100], peak: 100, color: .systemBlue,
                                 timing: .init(sampledAt: [0, 2, 4], referenceTime: 4))
        CATransaction.flush()
        func historyPathsMatch(_ target: CGPath?, _ shown: CGPath?) -> Bool {
            guard let target, let shown else { return false }
            let a = historyPathElements(target), b = historyPathElements(shown)
            return a.count == b.count && zip(a, b).allSatisfy { target, shown in
                target.0 == shown.0 && target.1.count == shown.1.count
                    && zip(target.1, shown.1).allSatisfy {
                        abs($0.x - $1.x) < 0.01 && abs($0.y - $1.y) < 0.01
                    }
            }
        }
        let baselineReady = runApplication(until: {
            historyLayers(completionFixture.layer).compactMap { $0 as? CAShapeLayer }
                .contains { $0.path == completionFixture.chartPathForTest
                    && historyPathsMatch($0.path, $0.presentation()?.path) }
        }, timeout: 1)
        check("History 完成检查从未暂停且已呈现的静态曲线开始",
              baselineReady && !completionFixture.hasChartAnimationForTest
                  && completionFixture.layer?.speed == 1
                  && completionFixture.layer?.timeOffset == 0)
        completionFixture.update(samples: [0, 0, 100, 150], peak: 150, color: .systemBlue,
                                 timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 6))
        CATransaction.flush()
        let completionAnimations = historyAnimations(completionFixture.layer)
        check("History 末段完成检查确实启动有界描边、填充与末端动画",
              Set(["history.fill", "history.stroke", "history.head"])
                  .isSubset(of: Set(completionAnimations.map { $0.0 }))
                  && completionAnimations.allSatisfy {
                      $0.1.duration.isFinite && abs($0.1.duration - 0.35) < 0.000_001
                          && $0.1.repeatCount == 0 && $0.1.repeatDuration == 0
                          && !$0.1.autoreverses && $0.1.isRemovedOnCompletion
                  })
        let completionLayers = historyLayers(completionFixture.layer)
        let completionShapes = completionLayers.compactMap { $0 as? CAShapeLayer }.filter {
            $0.animation(forKey: "history.stroke") != nil || $0.animation(forKey: "history.fill") != nil
        }
        let completionHead = completionLayers.first { $0.animation(forKey: "history.head") != nil }
        let completionLine = completionShapes.first { $0.animation(forKey: "history.stroke") != nil }
        let targetTailPath = completionFixture.chartPathForTest
        let tailSettled = settleHistoryFixture("matched-tail-normal-clock", view: completionFixture)
        let pathsMatch = completionShapes.count == 2 && completionShapes.allSatisfy { shape in
            historyPathsMatch(shape.path, shape.presentation()?.path)
        }
        let headMatches: Bool
        if let completionHead, let shownHead = completionHead.presentation() {
            headMatches = abs(completionHead.position.x - shownHead.position.x) < 0.01
                && abs(completionHead.position.y - shownHead.position.y) < 0.01
        } else { headMatches = false }
        if let targetTailPath, let targetMidpoint = historyCubicMidpoint(targetTailPath, index: 1),
           let settledPath = completionLine?.presentation()?.path,
           let settledMidpoint = historyCubicMidpoint(settledPath, index: 1) {
            check("History 控制点过渡到达新曲线后自动静止",
                  abs(settledMidpoint.x - targetMidpoint.x) < 0.000_001
                      && abs(settledMidpoint.y - targetMidpoint.y) < 0.000_001
                      && tailSettled && pathsMatch && headMatches)
        } else {
            check("History 控制点过渡到达新曲线后自动静止", false)
        }
        completionFixture.setPresentationActive(false)
        completionFixture.removeFromSuperview()
        fixtureWindow.orderOut(nil)

        let controller = PopoverController()
        let snapshot = PowerSnapshot(percent: 50, plugged: true, adapterW: 45,
                                     batteryW: 5, systemW: 40)
        var hostedValues = [40.0, 45.0]
        var hostedTimes = [0.0, 2.0]
        func updateController(appending: Bool = true, degraded: Bool = false) {
            if appending { hostedValues.append(43); hostedTimes.append(hostedTimes.last! + 2) }
            controller.update(snapshot: snapshot, history: hostedValues, peak: 45, degraded: degraded,
                              historyTiming: HistoryChartTiming(sampledAt: hostedTimes,
                                                               referenceTime: hostedTimes.last!))
            CATransaction.flush()
        }
        updateController(appending: false)
        controller.openForSettingsCommandTest(relativeTo: button)
        spin(0.4)
        defer { controller.handleOutsideClick(); spin(0.4) }
        if let root = controller.contentViewForTest,
           let hosted = historyDescendants(root).compactMap({ $0 as? HistoryView }).first {
            root.layoutSubtreeIfNeeded()
            updateController()
            check("History 生产弹窗把动画策略传至实际栏目", hosted.hasChartAnimationForTest)
            Settings.setModule(.history, visible: false)
            check("History 关闭模块立即取消已有过渡", hosted.isHidden && !hosted.hasChartAnimationForTest)
            updateController()
            check("History 模块关闭后采样不会重启过渡", !hosted.hasChartAnimationForTest)
            Settings.setModule(.history, visible: true)
            let restoredWithoutReplay = !hosted.isHidden && !hosted.hasChartAnimationForTest
            // Let AppKit restore the viewport and commit the newest static path.
            // An immediate append could see the old, shorter presentation path.
            let restoreStarted = CACurrentMediaTime()
            var restoredBaselineCommitted = false
            let restoredHistoryReady = runApplication(until: {
                root.layoutSubtreeIfNeeded()
                CATransaction.flush()
                let model = hosted.chartPathForTest
                let stroke = historyLayers(hosted.layer).compactMap { $0 as? CAShapeLayer }
                    .first { $0.strokeColor != nil && $0.path == model }
                restoredBaselineCommitted = model != nil && stroke?.presentation()?.path == model
                return controller.isOpen && controller.isShownForTest
                    && hosted.window?.isVisible == true && !hosted.isHiddenOrHasHiddenAncestor
                    && !hosted.visibleRect.isEmpty && restoredBaselineCommitted
            }, timeout: 1)
            log("HISTORY_HOSTED_RESTORE_READY ready=\(restoredHistoryReady) baselineCommitted=\(restoredBaselineCommitted) elapsed=\(CACurrentMediaTime() - restoreStarted) visibleRect=\(hosted.visibleRect) bounds=\(hosted.bounds) windowVisible=\(hosted.window?.isVisible == true) hidden=\(hosted.isHiddenOrHasHiddenAncestor)")
            check("History 恢复模块直接呈现最新数据",
                  restoredWithoutReplay && restoredHistoryReady && !hosted.hasChartAnimationForTest)

            updateController()
            if !hosted.hasChartAnimationForTest {
                log("HISTORY_HOSTED_SAMPLE_NO_MOTION visibleRect=\(hosted.visibleRect) bounds=\(hosted.bounds) windowVisible=\(hosted.window?.isVisible == true) hidden=\(hosted.isHiddenOrHasHiddenAncestor) keys=\(historyAnimations(hosted.layer).map { $0.0 })")
            }
            check("History 失败前的有效采样确实启动过渡", hosted.hasChartAnimationForTest)
            updateController(appending: false, degraded: true)
            check("History 读取失败立即取消过渡", !hosted.hasChartAnimationForTest)
            updateController(degraded: true)
            check("History 过期数据不重启过渡", !hosted.hasChartAnimationForTest)
            updateController(appending: false)

            updateController()
            check("History 减少动态效果变化前确实启动过渡", hosted.hasChartAnimationForTest)
            setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: NSWorkspace.shared
            )
            spin(0.01)
            check("History 开启减少动态效果立即取消过渡", !hosted.hasChartAnimationForTest)
            updateController()
            check("History 减少动态效果期间采样保持静止", !hosted.hasChartAnimationForTest)
            setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: NSWorkspace.shared
            )
            spin(0.01)
            updateController()
            check("History 收起前确实有活动过渡", hosted.hasChartAnimationForTest)
            controller.handleOutsideClick()
            check("History 收起弹窗立即取消过渡", !hosted.hasChartAnimationForTest)
            updateController()
            check("History 弹窗关闭时新数据不会重启过渡", !hosted.hasChartAnimationForTest)
        } else {
            check("History 原生生命周期验证找到真实生产栏目", false)
        }
    }
}

NSStatusBar.system.removeStatusItem(item)
Settings.resetTestConfiguration()
settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
if !pass {
    log("\nSOME_CHECKS_FAILED")
    exit(1)
}
// 跑过的都过了，但跳过的不能算验过
log(screenLocked || historyMotionChecksSkipped ? "\nRUNNABLE_CHECKS_PASSED_SOME_SKIPPED" : "\nALL_INTERACTION_CHECKS_PASSED")
exit(screenLocked || historyMotionChecksSkipped ? 2 : 0)
