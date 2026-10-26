# 测试偏好残留根因与修复（2026-10-26）

这次修复针对之前清理出的 180 个空 `Wattson.SwiftTests.*.plist`。
旧代码把“隔离目录已清空”当成了偏好清理成功，实际漏掉了真实用户目录里的文件。

## 已复现的根因

1. Python 的 `tests/local_runtime.py` 为子进程设置 `CFFIXED_USER_HOME`。
2. 该变量会改变 Swift Foundation 的 `homeDirectoryForCurrentUser`，但本机
   macOS 26.5.2 的 UserDefaults/cfprefsd 仍把这些 suite 写进真实用户的
   `~/Library/Preferences`。
3. 原 `removePersistentTestDomain` 用 Foundation home 拼接删除路径，并将
   `CFFIXED_USER_HOME` 继续传给 `defaults`。空 plist 留在真实目录，清理却无报错。
4. 外层只知道自己创建的 `Wattson.TestRuntime.*` 等域，不知道 Swift 单测各自
   生成的 UUID 域；之前的退出后审计也只检查外层域。换环境重跑成功，没有证明
   失败的前一次运行已清理。

已从旧版实际 helper 编译独立 Foundation 程序复现：普通环境退出后真实文件不存在；
注入 `CFFIXED_USER_HOME` 后退出，真实文件仍存在，helper 没有报告错误。
原始结果保存在 `dist/preferences-root-cause-20261026.noindex/reproduction-before.json`。

## 180 个文件的历史来源

归档内 180 个文件全部解析为空字典，SHA-256 与清理清单一致。

| 批次（北京时间） | 数量 | 可验证的历史关联 |
| --- | ---: | --- |
| 10 月 18 日 21:26 | 84 | 时间全部落在 662 项 Swift 测试运行内；唯一失败是偏好清理自测。同期记录明确说明取消 `CFFIXED_USER_HOME` 后重跑通过。 |
| 10 月 20 日 18:13–18:14 | 90 | 同期性能复查记录明确说明 Python 包装器注入该变量，触发环境测试失败，随后换标准环境重跑通过。 |
| 10 月 20 日 15:52 | 6 | 属于三组设置测试；未保留可对应到这六个 UUID 的原始命令及环境，不能声称逐项来源已完全证明。 |

历史证据：`design/release-v4.3.22/headless/{swift-test.log,gate-results.json,swift-ci-parity-identity.json,cleanup-verification.json}`
及 `design/performance-hardening-20261020/README.md`。完整时间线和归档核对结果在
`dist/preferences-root-cause-20261026.noindex/historical-trace.{md,json}`。

## 修复后的生命周期

- Swift helper 通过 POSIX 账号信息获取真实偏好目录；清理子进程移除
  `CFFIXED_USER_HOME`，即使同步、命令启动、命令返回或超时失败，也尝试删除本域文件并报告错误。
- 每个 Swift 测试域在首次写入前登记到本次运行的 manifest。缺少有效 manifest
  时正常退出并提示正确入口，偏好写入不会开始。
- `scripts/test_swift.sh` 先拥有测试进程和 manifest，再启动 Swift；进程组结束后
  清理本次登记的准确域。成功、失败、超时及 HUP/INT/TERM 均走同一个收尾流程。
- CI 和当前开发说明统一使用该入口；清理失败使命令失败，已有测试失败码保留。
  收尾输出 `registered` / `remaining` 数量。
- 旧 renderer benchmark 也改用拥有编译目录、进程和偏好域的入口；其 helper 的
  同类路径错误一并修正。该 benchmark 不是这 180 个 SwiftTests 文件的来源证据。

清理不扫描并删除其他运行的域，不依赖下次运行补救，不触碰正式安装及用户偏好。
范围是正常退出、子进程异常和可捕获中断；操作系统无法让被 SIGKILL 的最外层
清理进程或断电中的机器执行退出处理。

## 验证

- 全量 Swift：728 项通过。从原来注入隔离环境的 Python 包装器启动，实际登记
  183 个域；外层退出后 `registered=183 remaining=0`，真实目录复查为空。
- Python 全量：647 项，643 项通过，4 项需要真实桌面交互的检查按默认配置跳过；
  耗时 301.686 秒。新增 renderer 的 5 项检查另行运行并通过。
- 真实 Foundation 回归：普通/隔离环境、跨进程重开、命令失败/无法启动/超时、
  缺失及非法 manifest、正式域拒绝、旧性能 helper 路径检查均通过。
- 外层生命周期回归：故意不执行 teardown，验证成功、失败、超时、HUP/INT/TERM；
  并行运行和预存配置受到保护，非法或不可读 manifest 会使清理失败。
- Renderer 入口的 5 项回归通过；当前生产源码实际 `--compile-only` 编译通过，
  未启动 GUI。首次真实编译暴露旧命令漏带 MenuBar 源码，修正后通过；失败和成功
  两次编译的临时目录均自动清空。
- 全部退出后的机器复查：测试偏好 0 个，8 个相关 scratch 根目录的子项均为 0，
  无 Wattson 测试挂载；应用目录、LaunchServices 和 Spotlight 只找到正式
  `/Applications/Wattson.app`。正式应用及 helper 文件哈希、PKG 收据和进程均未改变。
- 全部 shell 入口语法、两个修改的 CI 工作流（actionlint）和 diff 检查通过。

完整日志和最终机器复查结果保存在
`dist/preferences-root-cause-20261026.noindex/`。不需要重新安装或更改产品版本。
