import AppKit
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
let forcedReduceMotion = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"] == "1"

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

if !screenLocked {
    app.finishLaunching()

    let p = PopoverController()
    let fullSnapshot = PowerSnapshot(
        percent: 100, plugged: true, adapterW: 52,
        batteryW: 0, systemW: 52
    )
    p.update(snapshot: fullSnapshot, history: [50, 52], peak: 52, degraded: false)
    check("关闭时只缓存最新数据而不渲染隐藏弹窗",
          p.contentRenderCountForTest == 0 && p.cachedPercentForTest == 100)
    check("初始未监听外部点击", !p.isWatchingOutsideClicks)
    p.toggle(relativeTo: button)
    check("展示前恰好渲染一次最新缓存数据", p.contentRenderCountForTest == 1)
    check("点击打开会安排一次平滑入场动画", p.entranceAnimationCountForTest == 1)
    spin(0.4)
    check("轻触图标弹窗打开", p.isShownForTest && p.isOpen)
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

    // ---- 3. 隐藏时必须停止动画：这是省电的全部意义 ----
    p.toggle(relativeTo: button); spin(0.8)
    let openAnims = p.runningAnimationCountForTest
    check(forcedReduceMotion ? "减少动态效果时打开不启动内容动画" : "打开时内容在动",
          forcedReduceMotion ? openAnims == 0 : openAnims > 0,
          "\(openAnims) 个动画")

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
    check(forcedReduceMotion ? "减少动态效果时中途重开仍保持静态" : "中途重开后动画已恢复",
          forcedReduceMotion ? reopenAnims == 0 : reopenAnims > 0,
          "\(reopenAnims) 个动画")
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
// Keep a composited window offscreen. Assertions below read the public frame
// of the real moving selection capsule, so geometry and label blending are
// verified from the same animation state.
win.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
win.alphaValue = 0.01
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
let expectsNativeGlass: Bool
if #available(macOS 26.0, *) {
    expectsNativeGlass = allowsNativeGlass
} else {
    expectsNativeGlass = false
}
if expectsNativeGlass {
    let selectorFill = slider.nativeSelectorFillAlphaForTest ?? 0
    check("原生材质使用无染色 Regular 底轨和中性无边框选中胶囊",
          slider.nativeTrackStyleForTest == 0
              && slider.nativeTrackHasTintForTest == false
              && selectorFill > 0
              && selectorFill <= 0.25
              && slider.nativeSelectorBorderWidthForTest == 0,
          "track=\(String(describing: slider.nativeTrackStyleForTest)) fill=\(selectorFill)")
} else {
    check("旧系统路径不向普通 NSView 发送 Liquid Glass 属性",
          slider.nativeTrackStyleForTest == nil)
    if ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] == "1" {
        check("旧系统减少透明度时 selector 使用不透明填充",
              (slider.fallbackSelectorOpacityForTest ?? 0) >= 0.999,
              "alpha \(slider.fallbackSelectorOpacityForTest ?? -1)")
    }
}

// 只有真正拖动才浮起并膨胀；按下和触控板轻微抖动都维持静止形态。
do {
    func ev(_ t: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: t,
                           location: NSPoint(x: x, y: ModeSliderView.preferredHeight / 2),
                           modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    slider.mouseDown(with: ev(.leftMouseDown, autoCentre))
    if expectsNativeGlass {
        check("单纯按下不改变中性选中胶囊",
              (slider.nativeSelectorFillAlphaForTest ?? 0) > 0
                  && slider.nativeSelectorBorderWidthForTest == 0)
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
        check("开始拖动后仍保持中性无边框选中胶囊",
              liftedFill > 0
                  && slider.nativeSelectorBorderWidthForTest == 0)
        slider.update(selected: .auto,
                      enabledModes: [.auto, .low, .high],
                      tint: .systemBlue)
        check("拖动中的 1 Hz 刷新不会压平浮起材质",
              abs((slider.nativeSelectorFillAlphaForTest ?? 0) - liftedFill) < 0.001,
              "刷新前 \(liftedFill)，刷新后 \(slider.nativeSelectorFillAlphaForTest ?? -1)")
    }
    if slider.reducesMotionForTest {
        check("减少动态效果时拖动不放大",
              abs(dragged.width - 1) < 0.01 && abs(dragged.height - 1) < 0.01)
    } else {
        check("开始拖动后才放大为浮起胶囊",
              dragged.width >= 1.12 && dragged.height >= 1.34,
              String(format: "%.2f × %.2f", dragged.width, dragged.height))
    }
    slider.mouseDragged(with: ev(.leftMouseDragged, (autoCentre + lowCentre) / 2))
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
        check("释放后选中胶囊回到中性静止材质",
              (slider.nativeSelectorFillAlphaForTest ?? 0) > 0
                  && slider.nativeSelectorBorderWidthForTest == 0)
    }
    spin(0.3)
}

let before = slider.highlightCallCountForTest
drag(from: autoCentre, to: slider.bounds.maxX - 4, steps: 60)
let relabels = slider.highlightCallCountForTest - before
check("拖到最右会选中 High Power", chosen.last == .high, "\(chosen)")
check("松手后吸附到 High 档位",
      abs(slider.knobCentreForTest - highCentre) < 0.5,
      String(format: "旋钮 %.1f vs 档位 %.1f", slider.knobCentreForTest, highCentre))
if slider.reducesMotionForTest {
    check("减少动态效果时释放直接吸附且不添加弹簧", !slider.settleIsAnimatingForTest)
} else {
    check("松手有吸附弹簧动画",
          slider.settleIsAnimatingForTest
              && slider.settleUsesSpringForTest
              && (slider.settleDurationForTest ?? 1) <= 0.24)
}
// 60 次拖动事件里只该跨过 1 个档位；每帧都重着色正是当初卡顿的原因
check("拖动 60 帧只重着色跨档的那几次", relabels <= 3, "\(relabels) 次")
spin(0.6)

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
              && !slider.settleUsesSpringForTest)
    spin(0.10)
    let visibleCentre = slider.glassViewCentreForTest
    let visibleScale = slider.knobPresentationScaleForTest
    check("点击后原生玻璃沿磁吸路径前进且不越过捕获范围",
          visibleCentre > lowCentre + 3 && visibleCentre <= highCentre + 4,
          String(format: "玻璃位置 %.1f，起点 %.1f，终点 %.1f",
                 visibleCentre, lowCentre, highCentre))
    check("点击磁吸全程不进入拖动放大态",
          visibleScale.width <= 1.001 && visibleScale.height <= 1.001,
          String(format: "%.3f × %.3f", visibleScale.width, visibleScale.height))
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
    check("动画中失败回滚从当前可见位置反向启动",
          centreBeforeRejection > autoCentre + 2
              && centreBeforeRejection < highCentre - 2
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

let ringView = RingGaugeView()
ringView.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                        height: RingGaugeView.preferredHeight)
ringView.layoutSubtreeIfNeeded()
ringView.update(snapshot: sharedMotionSnapshot)
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
                  systemW: 52, temperatureC: 31.8, cycleCount: 116),
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
    temperatureC: 31.8, cycleCount: 116
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

// ---- 10. Settings 命令：一个窗口、同一入口、单一系统状态 ----
final class InteractionSettingsSection: SettingsSectionController {
    let identifier = "interaction"
    let title = "Interaction"
    let symbolName = "gearshape"
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 479, height: 228))
    private(set) var refreshCount = 0
    var onRefresh: (() -> Void)?

    func refresh() {
        refreshCount += 1
        onRefresh?()
    }
}

let settingsSuiteName = "Wattson.SettingsCommandInteraction.\(UUID().uuidString)"
let settingsDefaults = UserDefaults(suiteName: settingsSuiteName)!
settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
Settings.configureForTest(defaults: settingsDefaults)

let interactionSection = InteractionSettingsSection()
let interactionSettings = SettingsWindowController(
    sections: [interactionSection],
    frameAutosaveName: nil
)
let settingsOwner = StatusItemController()
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
Settings.resetTestConfiguration()
settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
NSApp.mainMenu = previousMainMenu

NSStatusBar.system.removeStatusItem(item)
if !pass {
    log("\nSOME_CHECKS_FAILED")
    exit(1)
}
// 跑过的都过了，但跳过的不能算验过
log(screenLocked ? "\nRUNNABLE_CHECKS_PASSED_SOME_SKIPPED" : "\nALL_INTERACTION_CHECKS_PASSED")
exit(screenLocked ? 2 : 0)
