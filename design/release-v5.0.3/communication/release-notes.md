# Wattson 5.0.3

满电之后，细节仍在流动。

- **满电立体双星轨**：两颗微光星点在球体前后交错，错速慢转，连续尾迹自然收细。球体、星点与尾迹随当前主题配色调整；开启“减少动态效果”时保留静态双轨和状态说明。
- **三种滚动条样式**：默认 Flow 将渐变和微光留在右侧细窄滑块内，也可选择朴素的 Simple 或隐藏外观的 Hidden。切换样式保留阅读位置，滚轮与触控板操作不变。
- **完善模式滑块的尺寸适配**：修复尺寸变化时圆角未同步更新的问题，使滑块轮廓与当前高度保持一致。

满电双星轨表示电池已充满；原有系统值、备用估算、计算中和不可用提示继续保留。
预计时间仍优先读取 macOS，所有时间均为随工作负载与充电条件变化的动态估算。

## 满电动效

以下是新版的**动效设计预览**，展示前后遮挡、错速慢转与连续尾迹，不是 App 运行录屏。

![Wattson 5.0.3 满电立体双星轨动效设计预览](https://laleoarrow.github.io/battery-monitor/design/v5.0.3/previews/full-charge-orbit.gif)

[查看静态首帧](https://laleoarrow.github.io/battery-monitor/design/v5.0.3/previews/full-charge-orbit-poster.png) · [浏览 Light / Dark 设计画廊与 SVG 原稿](https://laleoarrow.github.io/battery-monitor/design/v5.0.3/)

## 下载与安装

支持 macOS 12 及以上，兼容 Apple Silicon 与 Intel。

- [完整 PKG](https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.3/Wattson-v5.0.3-macos-universal.pkg)：同步安装或升级 App 与辅助组件；已有 PKG / Homebrew 安装请继续使用此路线。
- [App 单独安装 DMG](https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.3/Wattson-v5.0.3-macos-universal.dmg)：仅含 App，不安装辅助组件，提供无需该组件的只读监测。
- Homebrew：`brew install --cask laleoarrow/tap/wattson`；已有安装使用 `brew upgrade --cask wattson`。

Community 分发：App / helper 为 ad-hoc 签名；PKG / DMG 未签名、未公证。macOS 的安全检查仍适用。[SHA256SUMS.txt](https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.3/SHA256SUMS.txt)

## English

Wattson 5.0.3 adds a 3D double-orbit indicator for a fully charged battery. Two small stars move continuously at different slow speeds, pass in front of and behind the opaque sphere, and leave tapered trails. The sphere, stars and trails follow the current palette. Reduce Motion preserves a static indicator and its state description.

The right-side scrollbar now offers Flow, Simple and Hidden styles, with Flow as the default. Changing styles preserves the reading position. This release also fixes the power-mode slider's corner radius failing to update after its size changes.

The GIF above is a design preview, not a recording of the running app. Existing battery-time source indicators and macOS-first estimates remain available. PKG includes the app and helper; DMG installs only the app for helper-free read-only monitoring. Community distribution: app/helper ad-hoc signed; PKG/DMG unsigned and not notarized.
