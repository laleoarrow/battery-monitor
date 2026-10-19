# Wattson 4.3.23

本次为性能与稳定性维护更新，保留现有界面、功能、配色、设置和 Activity Score 计算方式。

- 减少 Process Activity 操作按钮的重复图像刷新。
- 进程排名刷新时保留当前进程的键盘焦点，避免焦点跳到另一行或打断其他输入控件。
- 修复 helper 在空闲截止时间已到、采样任务尚未结束时可能出现的无等待轮询，保留原有采样节奏与退出策略。
- 更新 Xcode 27 工具链兼容处理及测试清理逻辑。

源代码已通过 macOS 27.0.1 / Xcode 27 的 Swift、Python、三种原生 AppKit 交互策略、动画压力测试与 Universal 构建验证。该兼容验证不等同于所有 macOS 27 场景均无缺陷，也不代表测得整机性能或能耗提升。

Activity Score 表示 CPU 与空闲唤醒活动，**不是实测功耗或电池耗电比例**。当前界面可参考沿用的 [4.3.22 设计预览](https://laleoarrow.github.io/battery-monitor/design/v4.3.22/)。

## 安装

支持 Apple Silicon 和 Intel，最低 macOS 12。

- [完整 PKG](https://github.com/laleoarrow/battery-monitor/releases/download/v4.3.23/Wattson-v4.3.23-macos-universal.pkg)：同步更新 App、helper 与安装记录，适合现有 PKG / Homebrew 用户。
- [只读 DMG](https://github.com/laleoarrow/battery-monitor/releases/download/v4.3.23/Wattson-v4.3.23-macos-universal.dmg)：仅含 App，不安装 helper；不提供进程采样与需 helper 的控制功能。
- Homebrew：`brew install --cask laleoarrow/tap/wattson`，已有安装可用 `brew upgrade --cask wattson`。

Community 分发：App / helper 为 ad-hoc 签名；PKG / DMG 未签名、未公证。请核对发布来源与随附 SHA256SUMS.txt，macOS 的信任检查仍适用。

## 验证记录

- [冻结发布源码](https://github.com/laleoarrow/battery-monitor/commit/23185f299ce61b8e373ebf5115b461ad2aa01226)
- [发布提交 Headless CI](https://github.com/laleoarrow/battery-monitor/actions/runs/39218951312)：Swift 664 项、Python 613 项（4 项按配置跳过）及网站检查通过。
- [候选安装包与五平台安装验证](https://github.com/laleoarrow/battery-monitor/actions/runs/39220053878)
- [macOS 27 兼容验证](https://github.com/laleoarrow/battery-monitor/actions/runs/39198225803)：运行时代码与本版相同，版本与文档后续更新。
