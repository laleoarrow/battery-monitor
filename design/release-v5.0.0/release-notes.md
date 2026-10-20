# Wattson 5.0.0

本次更新重新整理 Display 设置，加入 macOS 27 图标样式，并让电池健康与充电状态优先采用 macOS 的系统读数。

- **更清楚的 Display 页面**：Wattson、macOS 26、macOS 27 三种样式使用原生单选控件，百分比由一个小型 Off/On 控件统一设置。七种电源状态共用表头，预览间距加宽，保留原有字号与图标大小。
- **macOS 27 样式**：百分比可显示在电池内部，并提供辅助功能标签；较早系统保留矢量回退。原有 Wattson、macOS 26 样式及已保存的设置继续可用。
- **电池健康采用系统 Maximum Capacity**：官方读数暂不可用时显示 `—`，不再用原始满充容量与设计容量的比值代替。读取在后台进行并缓存结果。
- **充电状态更一致**：电量与充电状态优先使用系统电源报告；预计时间不可用时仍保留实际充电状态，100% 电量也不再单独被当作充满的依据。

Display 的生产渲染、原生交互和构建已在 macOS 26 与 macOS 27 验证。Activity Score 仍表示 CPU 与空闲唤醒活动，**不是实测功耗或电池耗电比例**。

## 设计预览

以下为本版沿用的已批准图标设计与原生离屏渲染，**不是运行中 App 的截图**；每张图均包含深浅色对照。

![Wattson 5.0.0 Modules 图标设计，深色在上、浅色在下](https://laleoarrow.github.io/battery-monitor/design/v5.0.0/previews/vector-preview.png)

![Wattson 5.0.0 Power 图标状态矩阵，含充电、充满、电池与混合供电](https://laleoarrow.github.io/battery-monitor/design/v5.0.0/previews/power-state-matrix.png)

[查看完整设计画廊](https://laleoarrow.github.io/battery-monitor/design/v5.0.0/) ·
[Modules SVG](https://laleoarrow.github.io/battery-monitor/design/v5.0.0/Wattson-v5.0.0-Modules-SVG.zip) ·
[Sidebar SVG](https://laleoarrow.github.io/battery-monitor/design/v5.0.0/Wattson-v5.0.0-Sidebar-SVG.zip) ·
[General SVG](https://laleoarrow.github.io/battery-monitor/design/v5.0.0/Wattson-v5.0.0-General-SVG.zip) ·
[Power SVG](https://laleoarrow.github.io/battery-monitor/design/v5.0.0/Wattson-v5.0.0-Power-SVG.zip)

## 安装

支持 Apple Silicon 和 Intel，最低 macOS 12。

- [完整 PKG](https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.0/Wattson-v5.0.0-macos-universal.pkg)：同步更新 App、helper 与安装记录，适合现有 PKG / Homebrew 用户。
- [只读 DMG](https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.0/Wattson-v5.0.0-macos-universal.dmg)：仅含 App，不安装 helper；不提供进程采样与需 helper 的控制功能。
- Homebrew：`brew install --cask laleoarrow/tap/wattson`；已有安装使用 `brew upgrade --cask wattson`。

Community 分发：App / helper 为 ad-hoc 签名；PKG / DMG 未签名、未公证。请核对发布来源与随附的 SHA256SUMS.txt，macOS 的信任检查仍适用。
