这是 History 更新准备开销的精简证据包。[测量结果](RESULTS.md)、[四轮 ABBA 完整分布](abba-comparison.json)及[显式路径构造计数](construction-comparison.json)保留原始内容。

基线提交为 `27b069e704f9fd5827bcb71b5d13dde2aa7712e9`，优化提交为 `9325876f70dc7e6fb722fda90f70ecde38a32c46`。对应的两个 `source-freeze-*.json` 保留源码归档哈希及两个 History 生产文件的 SHA-256。为控制体积，完整源码归档未复制；本仓库的这两个提交保留源码。`bundle-verification.json` 记录整理时的当前提交，并核对工作区、该提交和优化组的两个生产文件哈希一致。

四次运行按 A1、B1、B2、A2 顺序执行，均使用 [tools-freeze.json](tools-freeze.json) 中 SHA-256 为 `14594df9432d13526db941c68c7b784e68899e7a9fdbf12bf356e1023d1fc567` 的工具归档。每个场景每次运行排除 8 次预热，保留 64 个测量轮次，每版本合并 128 个轮次。no-op 每轮包含 512 个相关调用；比较轮中位数，不把这些调用当作独立重复实验。四轮各自的分布保留在 ABBA 报告中，轮间波动明显，扩轴中位数上升 6.8%，因此没有全面提速或统计显著性结论。

测量是实际可见 AppKit HistoryView 的主线程 `update` 调用墙钟耗时，包含调度和两次读钟开销；不是 CPU 时间、产品 FPS、GPU/WindowServer 成本、内存字节或能耗。计数构建只用于显式路径构造次数，注入 diff 和原始/派生哈希完整保留，计数构建的耗时不参与 ABBA 比较。

只有实际 `viewport.scaleY == 1` 时，描边采用相同拓扑的两个端点路径及 CABasicAnimation；其他 Y 缩放保留 33 个描边 keyframe。真实安装的动画负载来自各轮原始记录。最终合并版本的模块交互、原生画廊和 PKG 验证属于另外的验收范围。

六个 `results-*.tar.gz` 是原始内容寻址结果归档，每个包含 `results/benchmark.json`、provenance、输入/二进制哈希、摘要和环境/运行日志；两个 counts 归档另外包含完整 instrumentation 注入说明。`result-*.json` 保留归档 SHA-256 和退出状态，`dispatch-*.json` 保留运行时源码/工具清单和 transport bootstrap 哈希。原始记录未再展开复制；可在自己的临时目录解包对应归档。RESULTS.md 中的 `evidence/` 指原工作目录的展开副本。

未复制、也未使用 `future-tools-signal-fixed/`。本次实际工具归档保持不变；已知的未来信号状态记录修正不追溯替换本次六个成功运行的工具或记录。六份原始 result manifest 均为退出 0，ABBA 报告另记录实际 CLI 完成状态；本次使用的运行没有收到信号。

[handoff-audit.json](handoff-audit.json) 是运行前 VM 槽位受占用时的交接快照，其中 `timingRunsExecuted: 0` 和 pendingReason 是当时状态，不能作为最后清理结果或“未执行测量”的当前结论。最终 VM/安装清理由上层交付记录说明。

[SHA256SUMS.txt](SHA256SUMS.txt) 覆盖此目录除清单自身外的全部文件。整理只校验和复制已有证据，没有重新运行测试或基准。
