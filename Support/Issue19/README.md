# Wattson issue #19 support collector

Unzip the official support download and double-click
**Collect-Wattson-Issue19.command**. Leave Wattson running. **Wattson 4.3.3 has
no popup event trace, so its environment report is packaged immediately without
a 60-second wait.** If a newer or development build is running, the collector
asks you to click the menu-bar icon four times during a 60-second interval:
**open → close → open → close**. Continue if a click does not work. A ZIP appears
on your Desktop; unzip and review it, then drag it into your reply on issue #19.

下载并解压官方支持包，双击 **Collect-Wattson-Issue19.command**。保持 Wattson
运行。**4.3.3 没有点击事件记录，脚本会直接生成环境包，无需等待 60 秒。**
若运行的是新版或开发版，按终端提示在 60 秒内点击图标四次：**打开 → 关闭 →
打开 → 关闭**，某次无响应也请继续。桌面会生成 ZIP；先解压检查内容，再拖到
Issue #19 回复框。请说明失败发生在第几次点击，以及 Classic 是否也同样失败。

The source scripts are included. This uses only tools bundled with macOS 12 or
later; it needs no Xcode, Python, administrator password, or support-app install.
It never enables permissions, uses UI scripting or System Events, records your
screen, changes Wattson preferences, reads the clipboard, or uploads anything.
If macOS blocks a downloaded script, do not disable Gatekeeper or clear quarantine;
review the source and report the blocked message on the issue.

The report contains the actual system ProductVersion and BuildVersion, Mac model
and architecture, fixed Wattson installation/version/signature facts, only
Wattson process identifiers and location categories, typed allowlisted settings,
accessibility display flags, and display geometry/scaling. It has no serial
numbers, account/host names, personal paths, display names, window titles, full
process list or complete system logs. The only log subscription is Wattson's
`popup-events` category. On a build capable of emitting traces, capture lasts 60
seconds and is capped at 256 KiB; only
strictly recognized event fields from the Wattson process identifiers recorded
at collection start enter the report. Native local temporary storage supports
the bounded log pipe even when the selected output is on an external/shared disk.
Raw logs and temporary files
are removed on success, failure and catchable interruption. **Wattson 4.3.3 has
no popup click trace**; its report explicitly marks that missing evidence.

For an isolated test VM, skip the interaction interval and select the destination:

```sh
bash Collect-Wattson-Issue19.command --collect-only --output /path/to/output
```

This mode does not exercise or validate the popup. Build the source-only support
download with `bash scripts/build_issue19_support.sh` from the repository root.
