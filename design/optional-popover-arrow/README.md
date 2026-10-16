# Optional popover arrow — development preview

General → Appearance 中新增 **Show Popover Arrow**，默认开启。关闭后，Standard Glass / Clear Glass 去掉顶部三角，主体向上回收 **12 pt**；短屏可视内容高度增加 12 pt。Classic 原生弹窗保持原有行为。

这些是独占 ARM 虚拟机中的开发源码实拍，实际运行提交为 `36fa16fe9fc6cae3263cfb7c20cd8df74b8469dc`。源码 VERSION 仍为 4.3.8，图片并非已发布或本机安装的 4.3.8。后续提交 `d1372e02d23e39890de2fcc9340502a2e0bcc54e` 只修改 Python 源码合同测试；136 个运行时与 GUI 输入 Git blob 完全一致，但该后续提交没有再次运行 GUI。

macOS 26.6.1 (25G76)，ARM，默认 1024 × 768 逻辑分辨率、2× 像素倍率。截图来自生产渲染器和固定电源数据，背景为测试专用中性背景。短屏使用原生滚动到顶部或底部分别截取；原始 PNG 逐字节复制，没有拼接、缩放或调整显示器。不能用这组 macOS 26 固定样例代替 Cody 的 macOS 27 真机确认。

| 实拍内容 | 图片 |
| --- | --- |
| Standard 深色，充电，箭头开启 | [Top](charging-regular-dark-arrow-on-top.png) |
| Standard 深色，充电，箭头关闭 | [Top](charging-regular-dark-arrow-off-top.png) |
| Clear 浅色，充电，箭头开启 | [Top](charging-clear-light-arrow-on-top.png) |
| Clear 浅色，充电，箭头关闭 | [Top](charging-clear-light-arrow-off-top.png) |
| Standard 深色，电池供电，箭头关闭，续航与底部胶囊 | [Bottom](on-battery-regular-dark-arrow-off-bottom.png) |
| Clear 浅色，电池供电，箭头关闭，续航与底部胶囊 | [Bottom](on-battery-clear-light-arrow-off-bottom.png) |
| 设置浅色，完整开关行 | [Settings](settings-light-arrow-off.png) |
| 设置深色，完整开关行 | [Settings](settings-dark-arrow-off.png) |

验证通过：365 项真实 AppKit 交互断言、20,000 次动画压力循环、原生 Settings 合同（127.700 秒）。私有证据保留全部 100 张截图：六种电源状态 × Standard/Clear × 浅色/深色 × 箭头开/关 × 顶部/底部 = 96 张，加 4 张 Settings。48 组箭头几何配对、3,360 个主体命中点及 480 次菜单栏锚点检查均通过。

首轮 `f223bbe` 和日志增强轮 `54f57cd` 各有 2 个恢复宽度断言失败；原记录保留。独立 VM 探针确认 NSPanel 初始化会将半点横坐标向外取整，导致首次打开宽度多 1 pt。生产代码在创建材质和内容前恢复请求的精确 frame 后，原有严格恢复断言全部通过，没有放宽比较。

本轮所有测试偏好域（10 个）、临时目录、进程、注册与挂载均完成清理；即时 8 项和系统 CLOCK_MONOTONIC 实测 111.853 秒后的延迟 8 项审计均通过。独占 `Wattson-PopoverArrow-20261016` 虚拟机已删除，用户其他虚拟机及其状态保留。没有在本机运行 GUI 测试、安装软件或修改系统隐私/网络设置。

完整私有证据在仓库 `.build/popover-arrow-review.noindex/final-gui-evidence.json`；源绑定记录在同目录 `runtime-input-equivalence-36fa-to-d137.json`。本目录 `manifest.json` 记录每张原图的来源、尺寸、SHA-256 和验证摘要；`SHA256SUMS.txt` 可校验本目录交付文件。

最终无界面验证：冻结 `d1372e0` 的 Python 全集共 599 项，4 项预期跳过，其余通过；suite 与生命周期 wrapper 均 exit 0。SwiftPM 474 项零失败，实际执行源码为 `36fa16f`，124 个 Swift/Package/fixture 输入与 `d1372e0` 逐字节一致。即时与系统 CLOCK_MONOTONIC 实测 170.782 秒延迟清理通过，本机公开 4.3.8 的完整 App、helper、receipt、签名和原运行进程保持一致。证据：`.build/popover-arrow-headless-review.noindex/attempt-d1372e02d23e.noindex/result.json`。

早期两轮 Python 全集中，既有诊断包测试曾未到达注入的 ditto 阻塞阶段；两次单项复查与最终完整套件均通过。原失败记录保留，间歇原因尚未确定，未修改该无关测试或生产超时预算。本轮结论仅绑定上述冻结源码；同一工作区后续 History/版本升级修改不在本次验证范围内。
