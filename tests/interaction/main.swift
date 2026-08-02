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

NSStatusBar.system.removeStatusItem(item)
log(pass ? "\nALL_INTERACTION_CHECKS_PASSED" : "\nSOME_CHECKS_FAILED")
