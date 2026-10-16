Wattson 系统电池图标诊断报告 / System battery icon diagnostics

请先查看 environment.json，再决定是否把这个 ZIP 上传到公开 Issue。
报告不会自动发送。请补充：系统原生电池图标当时是否可见、隐藏选项是否能勾选、点击后的现象。

报告只有系统/应用版本与必要安装事实、现有 helper 的两个只读请求结果及耗时，以及当前用户
CurrentHost 的 com.apple.controlcenter Battery 单键存在性/类型/数值。非数值原文、未知错误文本、
序列号、账户名、主机名、个人路径、完整偏好域、截图和日志均不包含。

每个 socket 请求的总预算为四秒。timeout / unavailable 本身就是诊断信息，不能据此认定图标
已经隐藏或显示；存在安装文件也不代表 helper 一定正常。图标最终是否可见由你补充观察。

未修改设置或权限，未执行隐藏/显示开关，未重启 Control Center，未自动上传。
临时文件和本次启动的子进程会由收集脚本清理，最终 ZIP 留在输出目录供你审查。
