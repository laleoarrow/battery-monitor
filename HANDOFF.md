# Wattson 项目状态

**分支：`wattson-menubar`**
**状态：149 个测试通过（其中 1 个会真的构建 .app 并驱动真实 AppKit 对象跑 32 项交互检查），应用与助手 `-O` 构建干净，已安装二进制为最新且签名有效**

菜单栏插件这一轮的代码工作已经完成，特权助手已部署且为最新版（`getMode` 返回 `supportsHigh:true`）。

---

## 装它

```bash
./scripts/install.sh
```

会请求一次 sudo，用于放置切换省电模式所需的特权助手。

助手已经装好之后，日常更新只跑应用即可，不需要密码：

```bash
./scripts/install.sh --app-only
```

应用装在 `~/Applications`，本来就不需要提权；只有助手需要。助手平时不运行，只在你右键点击时由 launchd 唤醒，执行完即退出。

安装脚本会先把旧的 `电池功率.app`、`~/.battery_monitor.cfg`、`~/Library/Application Support/电池功率/` 全部删除（你确认过不再需要），再装新的。

卸载：`./scripts/uninstall.sh`

---

## 测试

```bash
python3 -m unittest discover -s tests
```

大部分测试读源码文本——对几何和常数够用。交互路径不够用：点击与弹窗依赖 AppKit 自己的时序，读代码没能发现"按住超过 0.3 秒会切换两次"和"关闭动画中途点击被吞掉"这两个 bug。所以 `tests/interaction/` 会构建一个真正的 .app，驱动真实的 `NSStatusItem`、`NSPopover` 和 `ModeSliderView`：

```bash
./scripts/verify_interaction.sh
```

约 20 秒，需要图形会话，不需要 sudo，也不需要辅助功能权限（事件直接投递给视图，不经系统注入）。迭代快测时可用 `WATTSON_SKIP_INTERACTION=1` 跳过。

---

## 手工验证矩阵

装完后逐格确认。这是唯一还没走过的环节。

- [ ] 电源状态：充电 / 插电已满 / 电池供电 / **混合供电**（需 ≤30 W 充电器配高负载复现）
- [ ] 菜单栏外观：浅色 / 深色下与系统电池并排比对
- [ ] 图标颜色：省电黄 / 低电量 ≤20% 红 / 充电绿 / 常态模板
- [ ] **按下高亮**：有色状态下按住图标，确认切回模板且对比度足够
- [ ] **右键**：切换生效、图标变色、有形变确认、**不弹密码框**
- [ ] **助手按需**：`pgrep wattson-helper` 平时无输出；右键后短暂出现；5 秒后消失
- [ ] 左键：弹窗从菜单栏下方展开、浮于所有窗口之上、点击外部关闭
- [ ] 弹窗底部：自动 / Low Power / High Power 三档切换实际生效
- [ ] 系统电池图标：复选框隐藏后消失，取消后恢复，Control Center 只短暂重启
- [ ] 空转：弹窗关闭后采样仅每 2 秒一次
- [ ] 卸载：`./scripts/uninstall.sh` 后 app、helper、plist、socket 全部消失

最容易出错的是**右键不弹密码框**。验证助手缺失时的行为：

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.leoarrow.wattson.helper.plist
sudo rm -f /var/run/wattson-helper.sock
# 右键图标：应只有轻微形变，模式不变，绝不弹密码框
./scripts/install.sh   # 恢复
```

---

## 不装也能看弹窗

弹窗有独立的预览入口，不需要安装、不需要 sudo：

```bash
xcrun swiftc -D DEBUG Core/*.swift MenuBar/*.swift Popover/*.swift main.swift -framework AppKit -framework CoreGraphics -framework IOKit -o /tmp/wattson && /tmp/wattson --popover-preview --preview-state=charging
```

`--preview-state=` 可选 `charging` / `idle` / `battery` / `mixed` / `high`，
`--preview-appearance=` 可选 `light` / `dark`。

---

## 已完成

| 部分 | 内容 |
|---|---|
| 数据层 | 有符号功率模型（含混合供电）、IOKit 直读采样、60 槽历史环形缓冲 |
| 提权 | launchd 按需唤醒的 root 助手，固定操作白名单，UID 校验 |
| 菜单栏 | 系统级一致的电池图标、四色状态、按下切模板、左右键路由、三时钟 |
| 弹窗 | 紧凑数字头（守恒异常才告警）、桑基能量流、环形仪表、双泳道、功率历史、模块开关、分段模式控件 |
| 身份 | 改名 Wattson / 瓦特森，bundle ID、配置路径、安装/卸载脚本 |
| Logo | `design/icon/AppIcon.icns`，由 `design/icon/make_icon.swift` 生成，改参数重跑即可 |

### 关键设计常量

全部集中在 `Core/VisualEncoding.swift`：

```
t(W)  = min(1, (W / 100) ^ 0.65)
mult  = 1 + t(总输入) × 2.4          →  1.00× .. 3.40×
thick = 4 + t(该管道瓦数) × 14 pt    →  4 .. 18 pt
节点 36 pt；不变量 2 × 18 == 36
```

`2 × thickMax == nodeSize` 使两管合计在数学上不可能超过节点。改动任一常量，`test_size_invariant_contract.py` 会立刻失败。

---

## 剩下的（下一轮）

1. **geek 风格主窗口** —— 同时作为菜单栏项被系统隐藏时的兜底入口
2. **桌面悬浮窗去留** —— 菜单栏已提供实时能力后重新评估
3. **WidgetKit extension** —— 目前 bundle ID 和视觉都还是旧的，`install.sh` 暂时不装它

---

## 踩过的坑

按类型分。前三个是"代码看着对、画出来不对"，契约测试抓不到。

### 1. 从 bounds 派生的值在首次 layout 前算了

**踩了两次**（泳道宽度、管道遮罩）。`update()` 可能早于第一次 `layout()`，此时 `bounds` 是零：泳道全部塌成 0 宽，管道遮罩尺寸归零把整条管裁没。

修法有两种，都在用：能用常量的用常量（`LaneView.trackWidth`），必须用 bounds 的在 `layout()` 末尾重算一次（`PowerFlowView`）。
测试：`test_geometry_is_recomputed_once_bounds_are_real`

### 2. 视图没翻转，整个图垂直镜像

节点和管道坐标都按 y 向下写，装进普通 `NSView` 后 W 变 M、系统和电池上下颠倒。绘制类必须 `isFlipped = true`。
测试：`test_plot_is_flipped`

### 3. 只靠动画定位的图层，动画不跑时堆在原点

粒子的位置完全来自 `CAKeyframeAnimation`。动画关闭时它们全部叠在 (0,0)。现在每颗粒子先用 `PipeGeometry.point(at:)` 解析地坐到曲线上，动画只是接管。
测试：`test_particles_are_seated_on_the_curve_without_animation`

### 4. 契约测试验证不了"代码被调用"

`BatteryIcon` 支持按下切模板，测试也断言了那条分支存在——但没有任何地方把 `pressed` 置为 true，是死代码。

**写这类测试时要专门问一句：这个分支会被触发吗。**
测试：`test_press_state_is_actually_wired_not_just_declared`

### 5. 平台约束

- 顶层语句只能在名为 `main.swift` 的文件里。临时验证脚本一律写到 `/tmp/main.swift`
- `launch_activate_socket` 第二个参数是非可选指针，要先分配占位指针让它被覆写
- `NSStatusBarButton` 默认不是 layer-backed，取 `button.layer` 会得到 nil，确认动画静默不播
- AppKit 的 `NSGradient.draw(in:)` 会填满整个 clip 区域。画在最后会把前面的内容全盖掉

---

## 已定的决策，不要翻案

| 决策 | 内容 |
|---|---|
| 提权方式 | launchd 按需唤醒的 LaunchDaemon。ad-hoc 签名用不了 `SMAppService` |
| 开机启动 | 由 helper 管理固定的用户 LaunchAgent；agent 只执行一次 `/usr/bin/open`，关闭选项不会退出当前 Wattson |
| 模式语义 | 全局两态 省电 ↔ 自动，`pmset -a`。AC 上的高能模式会变成自动，已确认接受 |
| 右键行为 | 直接动作、不弹菜单。**偏离 HIG**，是明确要求。补偿：形变确认 + 弹窗内可见开关 + tooltip |
| 弹窗而非菜单 | HIG 的例外条款「unless too complex for a menu format」适用 |
| 弹窗外观 | 单一 `#1C1C20` 深色面 + 发丝线分段，**不是**四张带边框的卡片。卡片会叠四套边框和内边距 |
| 模块无标题 | 给环形图标注「环形仪表」不传递信息，只占高度 |
| 电量只显示一次 | 环心显电量，数字头显瓦数。两处都显是浪费最贵的视觉位置 |
| 饱和点 | 100 W。之上粗细与速度冻结，由粒子数量与亮度接管 |
| 高功率粒子配色 | 蓝白 `#DBEAFF`。黄已被菜单栏图标占用表示省电模式 |
| 已排除的特效 | 管道外光晕、电弧游丝、闪电字形。360pt 宽度里体量过大，盖过管道 |
| 宽度不可加 | 刻意接受。改成线性会让 5–20 W 区间全糊在一起 |
| 泳道归一 | 按两条中较大者归一，比例才精确。按固定上限归一会把 108 W 和 32 W 画得一样长 |

---

## 怎么验证改动

```bash
# 契约测试
python3 -m unittest discover -s tests -v

# 类型检查
xcrun swiftc -typecheck Core/*.swift MenuBar/*.swift Popover/*.swift \
  main.swift \
  -framework AppKit -framework CoreGraphics -framework IOKit
```

测试是 Python `unittest` 对源码做结构断言，不是单元测试。它的固有盲区见坑 4。

设计规格在 `docs/superpowers/specs/2026-07-31-wattson-menubar-design.md`，**不在 git 里**（`.gitignore` 忽略了 `docs/superpowers/`）。
