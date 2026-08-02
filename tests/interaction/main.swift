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

if !screenLocked {
    app.finishLaunching()

    let p = PopoverController()
    check("初始未监听外部点击", !p.isWatchingOutsideClicks)
    p.toggle(relativeTo: button); spin(0.4)
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
    p.toggle(relativeTo: button); spin(0.2)      // 关，动画中途
    p.toggle(relativeTo: button); spin(1.2)      // 立刻再点想重开
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
    check("打开时内容在动", openAnims > 0, "\(openAnims) 个动画")
    p.handleOutsideClick(); spin(1.2)
    let closedAnims = p.runningAnimationCountForTest
    check("收起后动画已停", closedAnims == 0, "\(closedAnims) 个动画")

    // 中途重开之后动画必须恢复——迟到的 didClose 不能把它关掉
    p.toggle(relativeTo: button); spin(0.6)
    p.toggle(relativeTo: button); spin(0.2)
    p.toggle(relativeTo: button); spin(1.4)
    let reopenAnims = p.runningAnimationCountForTest
    check("中途重开后动画已恢复", reopenAnims > 0, "\(reopenAnims) 个动画")
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
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                                       height: ModeSliderView.preferredHeight),
                   styleMask: [.borderless], backing: .buffered, defer: false)
win.contentView = slider
slider.frame = win.contentView!.bounds
slider.update(selected: .auto, enabledModes: [.auto, .low, .high], tint: .systemBlue)
slider.layoutSubtreeIfNeeded()
spin(0.1)

var chosen: [EnergyMode] = []
slider.onSelect = { chosen.append($0); return true }

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
let before = slider.highlightCallCountForTest
drag(from: autoCentre, to: PopoverStyle.contentWidth - 4, steps: 60)
let relabels = slider.highlightCallCountForTest - before
check("拖到最右会选中 High Power", chosen.last == .high, "\(chosen)")
check("松手后吸附到 High 档位",
      abs(slider.knobCentreForTest - highCentre) < 0.5,
      String(format: "旋钮 %.1f vs 档位 %.1f", slider.knobCentreForTest, highCentre))
check("松手有吸附弹簧动画", slider.settleIsAnimatingForTest)
// 60 次拖动事件里只该跨过 1 个档位；每帧都重着色正是当初卡顿的原因
check("拖动 60 帧只重着色跨档的那几次", relabels <= 3, "\(relabels) 次")
spin(0.6)

let backBefore = slider.highlightCallCountForTest
drag(from: highCentre, to: lowCentre, steps: 60)
check("能一路拖回 Low Power", chosen.last == .low, "\(chosen)")
check("拖回后吸附到 Low 档位",
      abs(slider.knobCentreForTest - lowCentre) < 0.5)
check("回程同样不逐帧重着色", slider.highlightCallCountForTest - backBefore <= 3)

// 不支持 High Power 的机器上，拖过去必须停在最近的可用档位 Low
let limited = ModeSliderView(modes: [.auto, .low, .high])
let win2 = NSWindow(contentRect: win.contentRect(forFrameRect: win.frame), styleMask: [.borderless],
                    backing: .buffered, defer: false)
win2.contentView = limited
limited.frame = win2.contentView!.bounds
limited.update(selected: .auto, enabledModes: [.auto, .low], tint: .systemBlue)
limited.layoutSubtreeIfNeeded(); spin(0.1)
var limitedChosen: [EnergyMode] = []
limited.onSelect = { limitedChosen.append($0); return true }
do {
    func ev(_ t: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: t, location: NSPoint(x: x, y: ModeSliderView.preferredHeight / 2),
                           modifierFlags: [], timestamp: 0, windowNumber: win2.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    limited.mouseDown(with: ev(.leftMouseDown, limited.detentCentreForTest(0)))
    for i in 1...30 { limited.mouseDragged(with: ev(.leftMouseDragged, limited.detentCentreForTest(0) + CGFloat(i) * 6)) }
    limited.mouseUp(with: ev(.leftMouseUp, PopoverStyle.contentWidth - 4))
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
check("滑块接受 first mouse", slider.acceptsFirstMouse(for: nil))

// 此刻旋钮在 Low（上一段拖回去了）
chosen.removeAll()
tap(slider, in: win, atX: slider.detentCentreForTest(2))
check("点击 High Power 档位会切过去", chosen.last == .high, "\(chosen)")
check("点击后旋钮吸附到 High",
      abs(slider.knobCentreForTest - slider.detentCentreForTest(2)) < 0.5,
      String(format: "%.1f vs %.1f", slider.knobCentreForTest, slider.detentCentreForTest(2)))
spin(0.6)

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
tap(slider, in: win, atX: between)
check("点在两档之间选更近的一个", chosen.last == .high, "\(chosen)")
spin(0.6)

// 从 Auto 直接点禁用的 High 也必须没有反应；不能偷偷映射到相邻的 Low
limited.update(selected: .auto, enabledModes: [.auto, .low], tint: .systemBlue)
limitedChosen.removeAll()
tap(limited, in: win2, atX: limited.detentCentreForTest(2))
check("不支持 High 时点它无效",
      limitedChosen.isEmpty && limited.selectedIndexForTest == 0,
      "选中索引 \(limited.selectedIndexForTest) 回调 \(limitedChosen)")

// 系统拒绝切换时控件必须回到真实档位，不能只在视觉上假装成功
var rejected: [EnergyMode] = []
slider.onSelect = { rejected.append($0); return false }
tap(slider, in: win, atX: lowCentre)
check("切换失败后回弹到原档位",
      rejected == [.low]
          && slider.selectedIndexForTest == 2
          && abs(slider.knobCentreForTest - highCentre) < 0.5,
      "选中索引 \(slider.selectedIndexForTest) 回调 \(rejected)")

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
          && header.layoutFitsForTest(snapshot: headerSnapshots[3], degraded: true))

NSStatusBar.system.removeStatusItem(item)
if !pass {
    log("\nSOME_CHECKS_FAILED")
    exit(1)
}
// 跑过的都过了，但跳过的不能算验过
log(screenLocked ? "\nRUNNABLE_CHECKS_PASSED_SOME_SKIPPED" : "\nALL_INTERACTION_CHECKS_PASSED")
exit(screenLocked ? 2 : 0)
