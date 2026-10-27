# Wattson 5.0.2

剩余时间，一眼看清依据。

- **续航来源光点**：主题色恒亮表示 macOS 提供的预计时间；缓慢呼吸表示来自电池控制器或 Wattson 的本地估算；倾斜星轨表示计算中；红色呼吸表示估算暂不可用，监测会继续。
- **同步的计算动效**：星点沿倾斜轨道绕行，拖出细微尾迹；一圈对应一次呼吸，停歇后再继续。开启“减少动态效果”时显示静态指示，来源说明仍可查看。
- **同一套视觉语言**：新的渐变时钟与现有图标一致，光点和时钟随供电状态及浅深色主题调整。

时间读数优先采用 macOS 提供的估算，系统暂未返回有效时间时使用后备来源。所有时间均为动态预测，会随工作负载与充电条件更新。

## 设计预览

以下为 5.0.2 的设计示意，用于展示浅深色配色和状态细节，**不是运行中 App 的截图**。

![Wattson 5.0.2 浅色设计预览：续航来源光点与渐变时钟](https://laleoarrow.github.io/battery-monitor/design/v5.0.2/previews/time-source-light.png)

![Wattson 5.0.2 深色设计预览：续航来源光点与渐变时钟](https://laleoarrow.github.io/battery-monitor/design/v5.0.2/previews/time-source-dark.png)

[浏览完整设计画廊](https://laleoarrow.github.io/battery-monitor/design/v5.0.2/)

## 下载与安装

支持 macOS 12 及以上，兼容 Apple Silicon 与 Intel。

- [完整 PKG](https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.2/Wattson-v5.0.2-macos-universal.pkg)：同步安装或升级 App 与辅助组件；适合现有 PKG 用户。
- [只读 DMG](https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.2/Wattson-v5.0.2-macos-universal.dmg)：仅含 App，不安装辅助组件；提供无需辅助组件的只读监测，不含依赖该组件的进程采样及控制功能。
- Homebrew：`brew install --cask laleoarrow/tap/wattson`；已有安装使用 `brew upgrade --cask wattson`。

Community 分发：App / helper 为 ad-hoc 签名；PKG / DMG 未签名、未公证。macOS 的安全检查仍适用。[SHA256SUMS.txt](https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.2/SHA256SUMS.txt)

## English

Wattson 5.0.2 adds a small indicator beside the battery-time reading: steady light for a macOS time estimate, slow breathing for an estimate from the battery controller or Wattson, an orbiting spark while calculating, and a red pulse when an estimate is unavailable. The calculating animation pairs one orbit with one breath and a brief pause. Reduce Motion preserves a static indicator and its source description.

A new gradient clock follows the existing icon family and power-state palette in Light and Dark appearances. Battery-time estimates prioritize macOS. All times are dynamic predictions that update with workload and charging conditions.

PKG includes the app and helper; DMG installs only the app for helper-free read-only monitoring. Existing PKG / Homebrew installations should continue through PKG / Homebrew. Community distribution: app/helper ad-hoc signed; PKG/DMG unsigned and not notarized.
