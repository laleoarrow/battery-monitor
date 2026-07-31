# Wattson 交接文档

写给接手的人（Codex 或其他）。目标是让你不必重读整段对话就能继续。

**分支：`wattson-menubar`**（10 次提交，基于 `main` 的 `5119a3a`）
**状态：78 个测试通过，全部源码类型检查通过，工作区干净**

---

## ⚠️ 先读这条

**spec 和 plan 不在 git 里。** `.gitignore` 第 6 行忽略了 `docs/superpowers/`，这是仓库主人有意为之。两份文档只存在于本地磁盘：

- 设计规格：`docs/superpowers/specs/2026-07-31-wattson-menubar-design.md`（437 行）
- 实现计划：`docs/superpowers/plans/2026-08-01-wattson-menubar-foundation.md`（10 个任务，含每步的完整代码）

**如果你是从远程克隆的，这两个文件你没有。** 先找仓库主人要，否则下面的"未完成"部分缺少必要上下文。

---

## 这个项目在做什么

把 `电池功率`（一个 macOS 桌面悬浮窗 + WidgetKit 小组件）重构成 **Wattson / 瓦特森**，产品重心迁到**菜单栏插件**。

理由：WidgetKit 小组件由系统调度刷新，做不到秒级实时；菜单栏可以。

菜单栏插件的三个行为：
- 图标形状与系统电池一致，按状态变色
- **左键**弹出 360pt 功率流监视器
- **右键**直接切换省电模式（不弹菜单）

---

## ✅ 已完成（Plan 1 的 9/10）

| 任务 | 产出 | 提交 |
|---|---|---|
| 1 有符号功率模型 | `Core/PowerSnapshot.swift` | `2a39431` |
| 2 IOKit 采样器 | `Core/BatterySampler.swift` | `4612ea8` |
| 3 历史环形缓冲 | `Core/PowerHistory.swift` | `1c4cc1c` |
| 4 特权助手 | `Helper/wattson-helper.swift` + plist | `683c5db` |
| 5 助手客户端 + 模式读写 | `Core/HelperClient.swift`、`Core/EnergyMode.swift` | `efff96c` |
| 6 菜单栏图标 | `MenuBar/BatteryIcon.swift` | `ff9b2fa` |
| 7 状态项 + 左右键路由 | `MenuBar/StatusItemController.swift`、`Popover/PopoverController.swift` | `c612bd7` |
| 9 视觉编码常量 | `Core/VisualEncoding.swift` | `df28d18` |
| 10 失败路径 | 改 `BatterySampler`、`StatusItemController`、`README.md` | `b39beb9` |
| 8（部分） | 悬浮窗接到 Core、入口点抽到 `main.swift` | `a55b475` |

### 已实机验证的事实

- 采样守恒误差 **0.000 W**（M3 Max，满电插电态）
- 视觉编码曲线在 5/20/52/80/100/140 W 六个点与 spec 参考表**完全吻合**，140W 仍封顶 3.40× / 18.0pt
- 图标 7 种状态组合的 template 标志全部正确，含「省电+低电量时黄色优先」和「有色态按下切回模板」
- 环形缓冲 75 次写入后正确保留最近 60 个（16→75）
- 助手未安装时 `HelperClient.send` 返回 nil，不崩溃
- 尺寸不变量会咬人：把 `thickSpan` 改成 16 → `40.0 != 36.0` 测试失败

---

## ❌ 未完成

### A. Task 8 剩余部分（先做这个）

计划文档里 Task 8 的完整代码都写好了，照抄即可。剩三件：

1. **重写 `scripts/install.sh`**
   - 改身份：`Wattson.app` / `com.leoarrow.wattson`
   - 迁移旧安装（注销 widget → `lsregister -u` → 删 app，顺序不可换）
   - 改成多文件编译：`Core/*.swift MenuBar/*.swift Popover/*.swift BatteryPowerWidget.swift main.swift`，加 `-framework IOKit`
   - 安装特权助手到 `/Library/LaunchDaemons/` 与 `/Library/PrivilegedHelperTools/`（一次 `sudo`）

2. **新建 `scripts/uninstall.sh`** — 计划里有完整脚本

3. **新建 `tests/test_install_migration_contract.py`** — 计划里有完整测试

**简化点**：仓库主人明确说过「老的版本 app 是可以完全删除 application 中的内容的 我不用这个现在」。所以**不需要迁移旧配置**，直接删 `~/Applications/电池功率.app`、`~/.battery_monitor.cfg`、`~/Library/Application Support/电池功率/` 即可。计划里那段幂等迁移逻辑可以砍掉。

新的配置路径已经在代码里改好了：`~/Library/Application Support/Wattson/config.json`。

### B. Plan 2：弹窗可视化（尚无计划文档）

`Popover/PopoverController.swift` 现在是**空骨架**——左键能弹出一个 360×200 的空白弹窗。spec 第「弹窗」节定义了全部内容：

- 数字头（总功率 + 状态 + 电量）
- 守恒式常驻显示行
- **模块 A** 桑基能量流（两种布局 × 四种状态、接缝相切、路径插值形变、粒子）
- **模块 B** 环形仪表（环心显示电量百分比）
- **模块 C** 双泳道
- **模块 D** 功率历史（2 分钟面积图）
- 指标网格 + 底部模式开关
- 四模块可单独开关，默认全开

Plan 1 已经把接口铺好了：`VisualEncoding` 全部常量与曲线、`PowerSnapshot.state` 四态、`PowerHistory.samples/.peak`、`PopoverController` 的显示时钟开关、`StatusItemController.isDegraded`。

### C. Logo

`design/icon/AppIcon.icns` 还是旧的。spec 只锁了方向（Wattson = Watt + Watson，字母 W 与电池/闪电合形），具体形态待定，需要出图给仓库主人评审。

---

## 🕳️ 执行中踩到的坑

这些是最值钱的部分。五个缺陷，三个来自计划本身，两个是"测试通过但功能是坏的"。

### 1. 顶层语句只能在 `main.swift` 里

单文件时代不存在这个约束。改成多文件编译后，`BatteryPowerWidget.swift` 底部的 `app.run()` 直接编译失败。入口点已抽到 `main.swift`。

**同样影响 smoke test**：任何带顶层语句的临时验证脚本都必须命名为 `/tmp/main.swift`。

### 2. `launch_activate_socket` 的第二个参数是非可选指针

Swift 导入后签名是 `UnsafeMutablePointer<UnsafeMutablePointer<Int32>>`，传 `&fds`（其中 `fds` 是可选）编译不过。解法是先分配一个占位指针，让它被覆写：

```swift
var fds = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
```

### 3. `NSStatusBarButton` 默认不是 layer-backed

右键的确认形变动画取 `button.layer` 会拿到 nil，动画**静默不播**——表现就是"右键点了没反应"，而这恰好是右键直接动作最怕的失败模式。必须先 `button.wantsLayer = true`。

### 4. `pressed` 标志曾是死代码

`BatteryIcon` 支持按下时切回模板渲染（有色图标不会被系统反色，否则会糊在选中高亮上看不清），契约测试也验证了那条分支存在——**但没有任何地方把标志置为 true**。

契约测试只能验证代码路径**存在**，验证不了它被**接上了**。补了 `test_press_state_is_actually_wired_not_just_declared` 才防住。**写这类测试时要专门问一句：这个分支会被触发吗。**

### 5. 悬浮窗改造用扩展而非改 call site

计划原本要求替换 15 处字段引用。但 spec 明确说桌面悬浮窗**原样保留不改动**，改 15 个地方既违背 spec 又风险大。

改成在 `BatteryPowerWidget.swift` 里给 Core 的 `PowerSnapshot` 加一个兼容扩展，补上 `charging` / `chargeW` / `dischargeW` / `totalW` / `heroColor` / `statusColor`。悬浮窗的绘制代码一行没动，Core 仍是唯一数据源。

---

## 📌 已定且不要重新讨论的决策

仓库主人在设计阶段逐条确认过，别再翻案：

| 决策 | 内容 |
|---|---|
| 提权方式 | launchd **按需唤醒**的 LaunchDaemon。平时不运行，右键才被拉起，5 秒空闲后退出。ad-hoc 签名用不了 `SMAppService` |
| 模式语义 | 全局两态 **省电 ↔ 自动**，`pmset -a`。已知代价：AC 上的高能模式会变成自动，仓库主人接受 |
| 右键行为 | 直接动作、不弹菜单。**这偏离 HIG**，是明确要求。补偿：形变确认 + 弹窗内可见开关 + tooltip |
| 饱和点 | 100 W。之上粗细与速度冻结，由粒子数量与亮度接管强度通道 |
| 高功率粒子配色 | **蓝白** `#dbeaff`，不是黄。黄已被菜单栏图标占用表示省电模式，同色会同时指代最省电与最费电 |
| 已排除的特效 | 管道外环境光晕、不规则电弧游丝、闪电字形。都试过，在 360pt 宽度里体量过大、盖过管道 |
| 宽度不可加 | 桑基图本应宽度可加，但 `t^0.65` 是凹函数所以不成立。**这是刻意接受的**，不要改成线性"修复"——线性会让 5–20 W 区间全糊在一起 |

---

## 🔧 怎么验证你的改动

```bash
# 全量契约测试
python3 -m unittest discover -s tests -v

# 全部源码类型检查
xcrun swiftc -typecheck Core/*.swift MenuBar/*.swift Popover/*.swift \
  BatteryPowerWidget.swift main.swift \
  -framework AppKit -framework CoreGraphics -framework IOKit -framework WidgetKit
```

Task 8 做完后还有一张手工验证矩阵，在计划文档末尾。其中两格特别容易出错：

- **助手缺失时右键**：手动 `sudo launchctl bootout system ...` 卸掉助手后右键，必须是「图标轻微形变 + 模式不变 + **不弹密码框**」
- **助手按需**：平时 `pgrep wattson-helper` 应**无输出**；右键后短暂出现；5 秒后消失

---

## 测试约定

沿用仓库既有风格：Python `unittest`，对 Swift / Shell 源码做**结构断言**（`assertIn` + 正则），不是单元测试。

```python
ROOT = pathlib.Path(__file__).resolve().parents[1]
```

这种测试的**固有盲区**见上文坑 #4：它能验证代码存在，验证不了代码被调用。涉及"某个标志/分支是否真的被触发"时，要专门写断言。
