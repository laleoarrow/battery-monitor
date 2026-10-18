# Wattson 4.3.22

- 🔥 **Process Activity** 支持选择进程并点击 **×**，经原生确认后强制退出；选择跟随进程身份，排序变化不会误选其他进程。仅允许结束当前用户的进程，强制退出可能丢失未保存内容。
- 🔥 选中后的操作按钮统一为 **38 × 16 pt**；活跃度条跟随 App 图表配色，充电时绿色、接电或混合供电时蓝色、电池供电时中性色。按钮、玻璃着色与指针光效采用完整进度条的最深端点色。
- 🔥 悬停提示精简为进程名称／PID 与四舍五入后的 Score、CPU、Wakeups；详细说明保留在信息按钮中。默认显示 **Top 3**，保留 **Compact view**，重新打开时可复用十秒内的有效读数。
- 🔥 **Ring Gauge** 可从 14 项指标中选择最多 4 项，并按选择顺序显示；选择第 5 项时替换最早一项。电池与适配器电压／电流分别标注，缺失数据保留为 `—`。

Activity Score 表示进程活跃度，**不是实测瓦数或电池耗电占比**。进程采样与强制退出需要完整 PKG／Homebrew 安装提供的新版 helper；系统或其他用户的进程不可强制退出。

## 设计预览与 SVG 原稿

[4.3.22 明暗设计图集](https://laleoarrow.github.io/battery-monitor/design/v4.3.22/) · [GitHub 图集与原稿](https://github.com/laleoarrow/battery-monitor/tree/v4.3.22/design/releases/v4.3.22)

图集包含当前版本 Process Activity 的 Light／Dark 离屏预览，以及沿用的已批准图标与完整六种供电状态矩阵。示例使用固定数据；离屏图不展示实时采样、窗口玻璃合成或光效动画。运行时窗口截图仅用于内部验证。

| Process Activity · Light | Process Activity · Dark |
| --- | --- |
| ![Light 离屏预览，充电配色与选中后的统一操作按钮](https://raw.githubusercontent.com/laleoarrow/battery-monitor/v4.3.22/design/releases/v4.3.22/previews/process-compact-light.png) | ![Dark 离屏预览，充电配色与选中后的统一操作按钮](https://raw.githubusercontent.com/laleoarrow/battery-monitor/v4.3.22/design/releases/v4.3.22/previews/process-compact-dark.png) |

![六个 Modules 图标离屏设计预览，Dark 在上、Light 在下](https://raw.githubusercontent.com/laleoarrow/battery-monitor/v4.3.22/design/releases/v4.3.22/previews/vector-preview.png)

![Power 图标完整状态矩阵离屏设计预览，Dark 与 Light](https://raw.githubusercontent.com/laleoarrow/battery-monitor/v4.3.22/design/releases/v4.3.22/previews/power-state-matrix.png)

可编辑 SVG 原稿：[Modules · 6 个](https://github.com/laleoarrow/battery-monitor/releases/download/v4.3.22/Wattson-v4.3.22-Modules-SVG.zip) · [Sidebar · 3 个](https://github.com/laleoarrow/battery-monitor/releases/download/v4.3.22/Wattson-v4.3.22-Sidebar-SVG.zip) · [General · 5 个](https://github.com/laleoarrow/battery-monitor/releases/download/v4.3.22/Wattson-v4.3.22-General-SVG.zip) · [Power · 5 个](https://github.com/laleoarrow/battery-monitor/releases/download/v4.3.22/Wattson-v4.3.22-Power-SVG.zip)。设计附件独立于四个安装发布文件，图集中另附来源与校验值。

## 安装

支持 Apple Silicon 和 Intel，最低 macOS 12。

- **[PKG](https://github.com/laleoarrow/battery-monitor/releases/download/v4.3.22/Wattson-v4.3.22-macos-universal.pkg)**：包含 App 与 helper，适合完整安装。已有 PKG／Homebrew 安装须通过新版 PKG／Homebrew 同步更新 App、helper 与安装记录。
- **[DMG](https://github.com/laleoarrow/battery-monitor/releases/download/v4.3.22/Wattson-v4.3.22-macos-universal.dmg)**：仅含 App 与 Applications 快捷方式，用于无 helper 的只读电池监测；不会安装 helper、启用进程采样或提供需 helper 的控制。
- **Homebrew**：`brew install --cask laleoarrow/tap/wattson`；已有安装可运行 `brew upgrade --cask wattson`。

**Community 分发**：App 与 helper 为 ad-hoc 签名；PKG／DMG 未签名、未公证。请核对来源及随附的 SHA256SUMS.txt，macOS 的信任提示仍适用；App-only 路径不绕过 Gatekeeper。
