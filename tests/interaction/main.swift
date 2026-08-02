import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func log(_ s: String) { print(s); fflush(stdout) }
var pass = true
func check(_ n: String, _ ok: Bool, _ d: String = "") {
    if !ok { pass = false }
    log("\(ok ? "✅" : "❌") \(n)\(d.isEmpty ? "" : "  — \(d)")")
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

// ---- 2. 真实 NSStatusItem + NSPopover ----
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
item.button?.image = NSImage(systemSymbolName: "battery.100", accessibilityDescription: nil)
guard let button = item.button else { log("no button"); exit(1) }
app.finishLaunching()
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
func spin(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

let p = PopoverController()
check("初始未监听外部点击", !p.isWatchingOutsideClicks)
p.toggle(relativeTo: button); spin(0.4)
check("轻触图标弹窗打开", p.isShownForTest && p.isOpen)
check("打开后开始监听外部点击", p.isWatchingOutsideClicks)
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

// ---- 4. 模式滑块：拖得到 High Power，松手吸附，拖动中不做多余重绘 ----
let slider = ModeSliderView(modes: [.low, .auto, .high])
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                                       height: ModeSliderView.preferredHeight),
                   styleMask: [.borderless], backing: .buffered, defer: false)
win.contentView = slider
slider.frame = win.contentView!.bounds
slider.update(selected: .auto, enabledModes: [.low, .auto, .high], tint: .systemBlue)
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

let autoCentre = slider.detentCentreForTest(1)
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
drag(from: highCentre, to: 4, steps: 60)
check("能一路拖回 Low Power", chosen.last == .low, "\(chosen)")
check("拖回后吸附到 Low 档位",
      abs(slider.knobCentreForTest - slider.detentCentreForTest(0)) < 0.5)
check("回程同样不逐帧重着色", slider.highlightCallCountForTest - backBefore <= 3)

// 不支持 High Power 的机器上，拖过去必须停在 Auto
let limited = ModeSliderView(modes: [.low, .auto, .high])
let win2 = NSWindow(contentRect: win.contentRect(forFrameRect: win.frame), styleMask: [.borderless],
                    backing: .buffered, defer: false)
win2.contentView = limited
limited.frame = win2.contentView!.bounds
limited.update(selected: .auto, enabledModes: [.low, .auto], tint: .systemBlue)
limited.layoutSubtreeIfNeeded(); spin(0.1)
var limitedChosen: [EnergyMode] = []
limited.onSelect = { limitedChosen.append($0); return true }
do {
    func ev(_ t: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: t, location: NSPoint(x: x, y: ModeSliderView.preferredHeight / 2),
                           modifierFlags: [], timestamp: 0, windowNumber: win2.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    limited.mouseDown(with: ev(.leftMouseDown, limited.detentCentreForTest(1)))
    for i in 1...30 { limited.mouseDragged(with: ev(.leftMouseDragged, limited.detentCentreForTest(1) + CGFloat(i) * 6)) }
    limited.mouseUp(with: ev(.leftMouseUp, PopoverStyle.contentWidth - 4))
}
check("不支持 High 时拖过去停在 Auto",
      limitedChosen.isEmpty && limited.selectedIndexForTest == 1,
      "选中索引 \(limited.selectedIndexForTest) 回调 \(limitedChosen)")

NSStatusBar.system.removeStatusItem(item)
log(pass ? "\nALL_INTERACTION_CHECKS_PASSED" : "\nSOME_CHECKS_FAILED")
