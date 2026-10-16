# Wattson 系统电池图标只读诊断包

用于排查“Hide System Battery Icon”不可用、勾选后无效等问题。适用于已安装的
Wattson 4.3.6，也可用于新版；不需要安装新版 Wattson 才能收集。

1. 解压官方支持包，保持 Wattson 正常运行。
2. 双击 **Collect-Wattson-SystemBatteryIcon.command**。终端会显示进度，通常十几秒内完成，
   不需要再点击应用或输入管理员密码。
3. 桌面出现 `Wattson-SystemBatteryIcon-日期-编号.zip`。先解压查看
   `environment.json` 和 `README.txt`，再把 ZIP 拖到对应 GitHub Issue 回复框手动提交。
4. 回复时补充：系统原生电池图标当时是否可见，隐藏选项是否能勾选，以及点击后的现象。

如果 macOS 阻止执行下载的脚本，请保留阻止提示并回复 Issue。不要关闭 Gatekeeper、
修改隐私权限或清除隔离标记来运行它。

## 收集范围

- macOS 版本、构建号及处理器架构；Wattson 版本、安装收据版本、签名验证结果；
  应用、辅助服务、LaunchDaemon 和 socket 是否存在，以及 Wattson 自身的运行位置类别。
  具体用户路径不会记录。
- 向现有固定 helper socket 发送 **health** 与 **getSystemBatteryIconHidden** 两个只读请求。
  每个请求从连接到接收共限时四秒；只记录耗时、固定状态、布尔返回值及已知错误枚举。
  未知错误文本和额外响应字段不会写进报告。
- 当前用户、当前主机范围的 `com.apple.controlcenter` 域中，仅 **Battery** 一个键的
  存在性、类型，以及数值类型时的单个数值。字符串、数组、字典等只记录类型，不保存内容。
  不读取或导出整个偏好域，不写入或同步偏好。

诊断包不会操作隐藏/显示开关、重启 Control Center、修改偏好或权限；不截图、不读取
剪贴板、不收集序列号、账户名、主机名、窗口标题、完整进程列表或系统日志，不自动上传。
macOS 自带的 Bash、JXA 和 Perl 即可运行，无需 Python、Xcode 或第三方依赖。
连接 helper 可能让 launchd 按既有配置启动辅助服务，但只执行上述两个 getter。

脚本与说明全部随支持包提供。临时文件和本次启动的子进程会在成功、失败、超时或可捕获
中断时清理；桌面的最终 ZIP 会保留。强制断电或 SIGKILL 无法由脚本捕获。
报告中的 `unavailable` 或 `timeout` 是诊断结果，不代表用户需要改设置或权限。
整个收集和打包过程共享 45 秒预算，各阶段另有限时；超时后停止本次子进程并清理
临时文件。文件清理另有独立预算，最终 ZIP 只在完整校验后保留。

在隔离测试虚拟机中，可选输出目录：

```sh
bash Collect-Wattson-SystemBatteryIcon.command --output /path/to/output
```

在源码仓库中构建支持包：

```sh
bash scripts/build_system_battery_support.sh
```

构建只保留 `dist/support/Wattson-SystemBatteryIcon-Support-v1.zip`、对应的
`.sha256` 和 `.metadata.json`。包内不包含编译后的应用，也不修改旧 Issue #19 支持包。
