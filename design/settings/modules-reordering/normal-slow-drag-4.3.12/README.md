# Modules 正常慢拖原生验收

Classic、Standard、Clear 三种外观的正常慢拖放置与窗外释放取消，六项均通过。实际控制器、客体 stage 和独立探针退出码均为 0。测试使用一次性 ARM macOS 26.6.1 图形虚拟机；本轮没有操作本机鼠标键盘，也没有修改生产代码或重新安装本机 App。

测试源为 `5d5c896b7a1531ce4f9783fa467ff8c8eb62b82e`（4.3.12）。[范围比较](control/source-applicability-4.3.13.json)确认本机 4.3.13 源 `8529889597961de756fa57397b1d1149d6d1b536` 的 Modules 实现、相关窗口控制器和既有模块 artwork 与测试源相同。这个比较仅扩展该交互实现的适用范围，不表示本轮完整执行了 4.3.13 的所有路径。

最终清理已闭环：[21 个测试偏好域、64 条自有路径及其他资源的联合审计](vm-owner/r8-residual-audit/final-owned-residual-audit.json)在立即检查和 95.062259 秒静默观察后均无残留。测试 VM、磁盘、临时 Tart／dylib、四个拥有者进程、原始及派生凭据均已清理，原有两个 TestLab VM 仍停止。本机 4.3.13 的二进制、Info、收据、签名和 PID 与基线一致，原 Tart 哈希不变。拥有者外层命令的[实际工具回执](control/root-owner-completion.json)为退出 0；[完整最终结论](outcome.json)与[关闭证明](vm-owner/r8-residual-audit/closure.json)分别保留。最初的 [v8 原始快照](control/v8-actual-outcome.json)仍保留当时的 `ownerActualExit: null` 和 `finalResidualAuditPending: true`，没有用最终结果改写。

## 六项实际结果

每项投递 61 条左键按住消息，最后释放。原生会话计时来自真实 AppKit 源回调，按住投递计时来自输入工具；取消时的返回动画可能延长原生会话，两者没有合并成同一指标。完整精度见 [六项事实](control/v8-six-case-facts.json)。

| 用例 | 投递按住（秒） | 原生会话（秒） | 写入／通知 | 原始评估 | 最终窗口 |
| --- | ---: | ---: | ---: | --- | --- |
| Classic 慢拖放置 | 2.308666 | 1.976103 | 1／1 | [通过](normal-slow-drag-v8/cases/classic-slow-drop/evaluation.json) | [PNG](normal-slow-drag-v8/cases/classic-slow-drop/window.png) |
| Classic 窗外释放 | 2.311089 | 2.620964 | 0／0 | [通过](normal-slow-drag-v8/cases/classic-slow-outside/evaluation.json) | [PNG](normal-slow-drag-v8/cases/classic-slow-outside/window.png) |
| Standard 慢拖放置 | 2.309191 | 1.986069 | 1／1 | [通过](normal-slow-drag-v8/cases/standard-slow-drop/evaluation.json) | [PNG](normal-slow-drag-v8/cases/standard-slow-drop/window.png) |
| Standard 窗外释放 | 2.310962 | 2.643245 | 0／0 | [通过](normal-slow-drag-v8/cases/standard-slow-outside/evaluation.json) | [PNG](normal-slow-drag-v8/cases/standard-slow-outside/window.png) |
| Clear 慢拖放置 | 2.308445 | 1.985428 | 1／1 | [通过](normal-slow-drag-v8/cases/clear-slow-drop/evaluation.json) | [PNG](normal-slow-drag-v8/cases/clear-slow-drop/window.png) |
| Clear 窗外释放 | 2.303929 | 2.572824 | 0／0 | [通过](normal-slow-drag-v8/cases/clear-slow-outside/evaluation.json) | [PNG](normal-slow-drag-v8/cases/clear-slow-outside/window.png) |

每个用例的 `before-state.json`、独立 `lease.json`、`input.json`、`input-timing-check.json`、`state.json`、`history.jsonl` 与 `evaluation.json`均保留原始字节。六项各有 25 个检查通过，包括单一会话与源行的真实 `willBegin.enter/return`、`endedAt.enter/return` 序列、原始 IMP 各转发一次、无合成回调、开始时左键按住、会话超过一秒、结束后释放、透明度恢复、拖拽状态清空、行／窗口／滚动容器身份与模块可见性保持，以及鼠标操作不留下键盘焦点提示。两个生产 DEBUG 预检闭包均为 nil。

合法放置的最终序列为 `ring,lanes,history,runtime,flow`，仅写入和通知一次；窗外释放保留 `flow,ring,lanes,history,runtime`，不写入也不通知。拖拽预览观察到 0.25 的源行透明度，结束后全部恢复为 1。目标在可见末行内部，距可见底边 12 点，输入前须通过实际 hit-test 祖先关系确认命中同一个生产列表。输入在同一 VNC 连接内先完成两个只移动的客体原生指针读回校准，再允许按下。

这是经授权客体输入触发的真实 WindowServer／AppKit 原生交互验收，不包含人工鼠标体感、FPS 测量或 History 曲线流畅度评估。

## 早期尝试与边界

| 尝试 | 原始结果与保留范围 |
| --- | --- |
| CGEvent 预检 | [无投递权限、零输入](driver/results/preflight.json)，未将权限拒绝算作产品失败。 |
| v2／v3 | v2 路径白名单失败且零输入；v3 客体 VNC 已发送序列但未得到原生完成回调。分别保留在 `control/v2-controller-failure/`、`control/v3-guest-vnc-no-delivery/`；stage 退出 0 不算交互通过。 |
| 早期实验 VNC | 监听字段解析问题和实际通配地址监听均在认证／输入前拒绝。[原始通配地址拒绝](vm-owner/session.vQVHVI/vnc-bind-rejection.json)与[该次关闭证明](vm-owner/session.vQVHVI/wide-bind-closure.json)保留，未为输入放宽门禁。 |
| v4 | 标准 framebuffer 初始化成功后客体指针仍未移动，在产品 App 启动前取消；[原始状态](control/v4-cancelled-before-app/status.json)及[只移动校准](control/guest-calibration-1x-view3.json)保留。 |
| v5 | [真实 2.608321 秒会话失败](control/v5-failed-edge/actual-outcome.json)，operation 0、零写入；控制器 1、stage 0。[headless AppKit 证明](builddiag/nsbox-drop-target.stdout.json)直接复现旧终点 `stack.minY+3` 在 NSBox 内容命中区域之外。预览到末位后在按住期间恢复原序；目的端 `draggingExited` 没有直接观测，属于[受限推断](builddiag/v5-classic-drop-diagnosis.json)。原失败未改写。 |
| v6 | [Classic 内部放置通过](control/v6-first-pass-reset-timeout/actual-outcome.json)，随后第二项 reset 未在 15 秒内读到，第二项零输入；控制器 1、stage 0。[IPC 诊断](ipc-diag/report.json)实际退出 0，八秒内客体 Foundation 读到宿主替换前旧值，客体侧原子替换可见。执行源 `host-run-executed.py` 与之后加固、未重跑的 `host-run.py` 分开保留。 |
| v7 | [两个 Classic 用例通过](control/v7-classic-pass-window-not-ready/actual-outcome.json)；Standard 冻结状态暂缺 `cgWindow`，输入工具在连接与输入前返回 78。[同一窗口 0.231052 秒后恢复元数据](builddiag/v7-standard-cgwindow-transient.json)，未证明 Glass 窗口始终缺少元数据。控制器 1、stage 0。 |
| v8 | 同一冻结 v3 夹具，控制器改用客体原子发布命令及 SHA 读回，并等待重建窗口元数据就绪。六项均通过，未修改生产代码。 |

[v6 夹具推导与原生几何检查](control-v6-prep/provenance.json)保留 v2→v3 精确差异。观察器、运行器和评估器没有随目标几何更改。评估器的 28 项纯数据／变异检查属于工具验证，不计入六项产品用例。临时 Tart 复制件的早期崩溃、双 entitlement 复制件退出 137 和后续实际 socket 检查均保留于冻结后端证据，未折算为产品通过。

## 输入与重放范围

[源码映射](source-map.json)和[原始复制清单](copied-source-manifest.json)记录每份输入的来源、字节数及 SHA-256；`SHA256SUMS`覆盖本目录交付文件。所有凭据、含真实私密 VNC URL 的日志、Tart／app／dylib 二进制和编译缓存均不包含。

源码包是 347,288 字节、58 个普通文件的[精确构建输入子集](fixture/compact-inputs/README.md)，SHA-256 为 `d200e4a40f75672dffab6ec56e10569cf1bf078d22d385e0fdc15673d852a736`。它保留 52 个递归 Swift 文件、VERSION、两个 lifecycle helper 和三个生产 logo 的原字节。它不是完整 `8aa52b90…` 归档；原完整归档 115,241,614 字节仍是调用方输入，没有重复加入。记录中的精确 stage 仍要求该完整归档及其原哈希；单独重放编译可在核对子集映射后使用相关成员，不可把子集冒充原归档。

运行前后生产哈希比较与编译范围都是 47 个顶层 Swift 文件；另外五个 `Core/Diagnostics` 文件包含在子集身份校验中，未被该顶层运行时 helper 编译或重新哈希。[运行前](normal-slow-drag-v8/source-production-before.json)与[运行后](normal-slow-drag-v8/source-production-after.json)比较无修改。

关键重放输入包括冻结 v6 基础工具、v3 几何夹具、原始 stage、评估器、控制器、guest lease 探针、输入工具完整 import 链与共享 lifecycle helper。后端源码和原生检查使用 `loopback-vz/nat-final-freeze.tar.gz`（SHA-256 `3bfe92c68d15545a90bfc3a8aefba56cd018df845181859fe044686124a34f1e`），没有复制其展开树。控制器和拥有者路径记录的是本次历史环境，不能在本机或仍在使用的 VM 上直接执行；新重放需要重新拥有的一次性 ARM GUI VM、Swift／Clang 工具链及该次生成和清理的凭据。

最终拥有者证据使用[精简冻结归档](vm-owner/closure-r8-evidence-c341310fc1337d89d7dbed6d2cb8528a9c85afac11749af06561622809f3b1fc.tar.gz)，SHA-256 为 `c341310fc1337d89d7dbed6d2cb8528a9c85afac11749af06561622809f3b1fc`，34,709 字节、59 个普通文件；内含 wrapper／guard、监听证明与 trace、审计源和原始结果、stop／delete／退出及本机基线核对。未重复展开这 59 份文件。归档内图像清单使用本次原始 live 路径，本目录通过[字节一致的路径映射](capture-gallery.json)指向各 case PNG，避免重复存图。
