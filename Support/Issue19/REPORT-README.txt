Wattson issue #19 diagnostics / 诊断报告

Review environment.json and popup-events.json before sharing this ZIP publicly.
请先检查两个 JSON 文件，再决定是否把 ZIP 附到公开 Issue。

environment.json records fixed system/install facts, typed allowlisted Wattson
preferences, accessibility display flags and display geometry. Personal paths,
names, serial numbers, window titles and screenshots are excluded.

popup-events.json contains only recognized fields from Wattson's popup-events
log category during this collection. Wattson 4.3.3 emits no popup click trace.
Accepted events must belong to a Wattson process identifier recorded at the start.
For 4.3.3, collection skips the 60-second wait and packages environment facts only.
Missing events do not prove successful or failed click delivery. --collect-only
skips interaction recording entirely.

Please add which click failed and whether Classic or Liquid Glass was selected.
请在 Issue 回复中说明第几次点击失败，以及当时选择 Classic 还是 Liquid Glass。

No password or permission change was requested, no setting was changed, and
nothing was uploaded. Temporary files and raw event logs have been removed.
