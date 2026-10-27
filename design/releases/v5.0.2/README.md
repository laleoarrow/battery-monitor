# Wattson 5.0.2 · 已批准设计画廊

本目录用于公开版本的设计展示，不包含 App 运行截图。新的 Light / Dark
图展示已批准的「文字旁」时间来源光点与渐变时钟，使用示例数值；既有五张
图标效果图是固定场景的原生离屏绘制，逐字节保留自批准来源。

## 时间来源与渐变时钟

- 系统数据：主题色恒亮。
- 备用估算：缓慢呼吸。
- 计算中：立即绕行 2.8 秒，与同一次亮暗呼吸同步；圈末一起收暗，停歇 0.5 秒。
- 无法计算：状态光点柔和红色脉动，时钟保持仪表主题色。

批准依据：`design/battery-time-indicator/planet-source-preview.html` 的文字旁方案。
本目录 `motion-preview.html` 以独立 HTML / SVG 重现其设计；支持 Light / Dark、
银灰 / 充电绿 / 接电蓝，以及减少动态效果。它不演示原生动画的运行性能。

`previews/time-source-light.svg` 与 `time-source-dark.svg` 是由
`prepare-assets.py --svg-only` 生成的静态设计放大图。时钟几何取自当前
`design/popover/power-icons-vector/clock.svg`，光点展示固定的动效相位。
相应 PNG 由浏览器按 1200 × 1040 渲染这些 SVG；它们是设计图，不是截图录制的
App 界面、实时电池读数、材质验证或测量准确率证明。

## 保留的图标与原稿

五张既有预览保留来源路径及哈希。Settings 效果图均为 Dark 在上、Light 在下，
侧栏另含强调选中行。Power 状态矩阵覆盖充电、接电已满、电池、混合供电、
低电量、低电量模式；旧 Power 效果图展示五枚图标，新增时钟在时间来源设计图中。

四个可重复生成的 ZIP 包含 20 枚当前版本 SVG 原稿与各自说明文件：
Modules 6 枚、Sidebar 3 枚、General 5 枚、Power 6 枚（含渐变时钟）。
所有原稿从发布源码逐字节复制。状态光点由原生代码绘制，不列为新增 SVG 图标原稿。

`python3 -B design/releases/v5.0.2/prepare-assets.py` 更新最终复制、ZIP、manifest
及完整校验清单；运行前应先生成并渲染 Light / Dark 设计 SVG。该脚本只读源码、
写本目录最终展示资产，不创建 App、临时工作区、系统偏好或注册项。
PNG 的 `sourceSha256` 指向源 SVG；PNG 自己的 `sha256` 与 `bytes` 单独校验。
旧预览为直接复制，源 PNG 与目标 PNG 的哈希相同。

## 公开路径

[画廊](https://laleoarrow.github.io/battery-monitor/design/v5.0.2/) ·
[Light 预览](https://laleoarrow.github.io/battery-monitor/design/v5.0.2/previews/time-source-light.png) ·
[Dark 预览](https://laleoarrow.github.io/battery-monitor/design/v5.0.2/previews/time-source-dark.png)

发布前，这些地址仅为规划路径；正式发布流程须无认证验证可访问性。
Pages exporter 将本目录输出为 `docs/design/v5.0.2/`，同时导出已存在的合法版本
画廊，保留旧版本链接。设计资源独立于四个受校验的安装发布资产，不改变发版门禁。
