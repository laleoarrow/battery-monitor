# Wattson 5.0.3 · 已批准设计画廊

本目录用于新版的设计展示，不包含 App 运行截图。新增满电立体双星轨 GIF、
静态首帧、Light / Dark 设计图，以及右侧 Flow 滚动条的浅深色设计预览。
时间来源光点、渐变时钟和既有图标继续保留；示例读数不代表实时电池数据。

## 满电立体双星轨

两颗小星点在不透明球体前后交错、错速慢转，连续尾迹逐渐收细。
球体、星点和尾迹共用当前主题配色；满电动效表达稳定的充电状态，
不表示预计时间来自某一来源，也不增加估算准确性的承诺。

批准依据是 `design/battery-time-indicator/full-charge/full-charge-preview.html`。
GIF 和三张静态图从 `design/release-v5.0.3/gallery/` 逐字节复制。
GIF 使用持续慢转的无缝设计循环：外轨 8 秒，内轨 32/3 秒；原生 App
使用 8 秒与 10.6 秒周期。约 0.63% 的设计预览时间适配只用于闭合 32 秒循环，
没有为 App 加入停顿或淡出；几何、前后遮挡与连续尾迹保持原设计。
它不是原生录屏或动画性能测量。

首页以 GIF 展示主要动效，并提供静态首帧链接。浏览器启用减少动态效果时，
`picture` 自动选择静态首帧。Light / Dark 配对图保留完整的状态与配色说明。

## Flow 滚动条

浅深色图由版本化 `scrollbar-preview.html` 渲染，保留
`design/scrollbar-styles/scrollbar-style-preview.html` 中已批准的右侧细窄渐变滑块。
早期设计中的“默认隐藏”文字及初始选项已同步为实际发布的 Flow 默认值；
旧设计文件和图片保持不变。App 默认使用 Flow；也可选择灰色 Simple，
或隐藏外观的 Hidden，切换时保留阅读位置。Hidden 不禁用滚轮或触控板。
这些图片是设计预览，不是运行中的原生窗口截图。

## 保留的来源提示、图标与 SVG 原稿

原有四种时间来源提示继续保留：系统值恒亮、备用估算缓慢呼吸、计算中的
单星轨与呼吸同步、不可用时红色脉动。计算中每圈 2.8 秒、圈后停歇 0.5 秒；
满电双星轨单独使用持续慢转。时间来源 SVG 设计图已重新生成 5.0.3 标题。

五张既有图标效果图逐字节保留自批准来源，使用固定场景的原生离屏绘制。
四个可重复生成的 ZIP 含 20 枚当前源码 SVG 原稿及说明：Modules 6 枚、
Sidebar 3 枚、General 5 枚、Power 6 枚。图标按原生 App 的外观与供电状态赋色；
SVG 内的蓝色是强调色占位，不是固定主题要求。

## 生成与校验

1. `python3 -B design/releases/v5.0.3/prepare-assets.py --svg-only` 生成时间来源 SVG。
2. `bash design/releases/v5.0.3/render-gallery.sh EXISTING_PLAYWRIGHT_PACKAGE_DIRECTORY --svg-only`
   渲染两个 SVG 和版本化滚动条设计。完整页面校验在第 4 步执行。
   它使用独立浏览器配置，临时目录和子进程由共享 cleanup owner 管理。
3. 生成满电 GIF 和静态图后，运行
   `python3 -B design/releases/v5.0.3/prepare-assets.py`，复制最终图稿、生成 ZIP、
   `manifest.json` 和覆盖本目录全部文件的 `SHA256SUMS.txt`。
4. 再运行不带 `--svg-only` 的 `render-gallery.sh`，检查页面的浅深色、窄宽布局、
   图片加载与减少动态效果。校验后再运行第 3 步，更新完整校验清单。

所有最终资源、原稿来源、字节数与 SHA-256 都在 manifest / checksum 清单中。
设计资源独立于四个受校验的安装发布文件，GIF 放入 Release 正文和推广邮件，
不改变安装文件的发布契约。

公开地址：<https://laleoarrow.github.io/battery-monitor/design/v5.0.3/>。
发布前此地址只是规划路径；正式流程必须完成匿名访问和精确字节校验。
