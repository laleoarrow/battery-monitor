# Wattson 5.0.1

本次小版本加入 Process Activity 白名单，并合入经过实测的 Glass 弹窗打开优化。

- **进程白名单**：普通点击进程仍显示 **×**；**⌘ 点击**显示隐藏图标，再点击该图标即可按完整进程名称加入白名单，立即隐藏匹配项。规则会保存，删除规则即可恢复显示。
- **精确、通配符与正则规则**：在 **Settings → Modules → Process Activity → Whitelist…** 管理规则。Exact 按完整名称匹配；Wildcard 支持 `*` 和 `?`；两者均区分大小写。Regex 在名称中搜索，可用 `^`、`$` 限定完整名称；无效表达式不会保存。
- **减少 Glass 重复外观刷新**：在 macOS 26.6.1 的 ARM GUI 测试虚拟机中，App 为浅色、弹窗指定深色时，Regular / Clear Glass 预热后的弹窗同步打开调用中位数由约 **68–69 ms 降至 37–38 ms**。原有采样节奏、主题切换机制与其余功能保持不变。

白名单只影响列表显示，不会结束进程；它从现有前十名采样候选中过滤，再应用显示数量，因此隐藏较多时可能少于设定行数。进程采样需要完整 PKG / Homebrew 安装提供的 helper。Activity Score 仍表示 CPU 与空闲唤醒活动，**不是实测功耗或电池耗电比例**。

上述性能数字衡量特定测试条件下的同步打开工作，不代表冷启动、物理显示延迟、动画帧率或整机 CPU / 耗电改善。[查看测量方法、对照与原始记录](https://github.com/laleoarrow/battery-monitor/blob/v5.0.1/design/performance-measurements-20261020/README.md)。[白名单交互与六种供电状态验证](https://github.com/laleoarrow/battery-monitor/blob/v5.0.1/design/process-whitelist/README.md)记录了真实生产视图与原生输入检查。

## 设计预览

以下为本版沿用的已批准图标设计与原生离屏渲染，**不是运行中 App 的截图**。这些图展示图标与供电配色；白名单界面与性能测量见上方验证记录。

![Wattson 5.0.1 Modules 图标设计，深色在上、浅色在下](https://laleoarrow.github.io/battery-monitor/design/v5.0.1/previews/vector-preview.png)

![Wattson 5.0.1 Power 图标状态矩阵，含充电、充满、电池与混合供电](https://laleoarrow.github.io/battery-monitor/design/v5.0.1/previews/power-state-matrix.png)

[查看完整设计画廊](https://laleoarrow.github.io/battery-monitor/design/v5.0.1/) ·
[Modules SVG](https://laleoarrow.github.io/battery-monitor/design/v5.0.1/Wattson-v5.0.1-Modules-SVG.zip) ·
[Sidebar SVG](https://laleoarrow.github.io/battery-monitor/design/v5.0.1/Wattson-v5.0.1-Sidebar-SVG.zip) ·
[General SVG](https://laleoarrow.github.io/battery-monitor/design/v5.0.1/Wattson-v5.0.1-General-SVG.zip) ·
[Power SVG](https://laleoarrow.github.io/battery-monitor/design/v5.0.1/Wattson-v5.0.1-Power-SVG.zip)

## 安装

支持 Apple Silicon 和 Intel，最低 macOS 12。

- [完整 PKG](https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.1/Wattson-v5.0.1-macos-universal.pkg)：同步更新 App、helper 与安装记录，适合现有 PKG / Homebrew 用户。
- [只读 DMG](https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.1/Wattson-v5.0.1-macos-universal.dmg)：仅含 App 与 Applications 快捷方式，不安装 helper；不提供进程采样与需 helper 的控制功能。
- Homebrew：`brew install --cask laleoarrow/tap/wattson`；已有安装使用 `brew upgrade --cask wattson`。

Community 分发：App / helper 为 ad-hoc 签名；PKG / DMG 未签名、未公证。请核对发布来源与随附的 SHA256SUMS.txt，macOS 的信任检查仍适用；App-only 路径不绕过 Gatekeeper。

## 发布验证

冻结源码：`f2f225f5889ba1ec5cae41ee2d8fca4b80406ed6`。

- [Headless CI](https://github.com/laleoarrow/battery-monitor/actions/runs/39426129210)：728 项 Swift、631 项 Python（4 项预期跳过），以及网站构建、测试与导出通过。
- [候选包与五平台安装矩阵](https://github.com/laleoarrow/battery-monitor/actions/runs/39427444794)：同一组候选字节通过 macOS 14／15／26 Apple Silicon 与 15／26 Intel 的安装、升级、helper、DMG 和卸载验证。
- [macOS 27 兼容性检查](https://github.com/laleoarrow/battery-monitor/actions/runs/39427450627)：系统图标、Display 设置、完整测试、三组原生交互、20,000 次动画压力及双架构构建通过；这项软件检查不等同于 macOS 27 安装包矩阵。

性能数字来自已合入优化提交的受控对照测量，方法与适用范围见前文。
