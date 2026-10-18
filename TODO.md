# TODO

- [x] **Process Activity：支持可变配色。**

  活动条的样式颜色不能固定为蓝色，需要能与 App 整体配色协调；保留每条内部从浅到深的同色系横向渐变和固定 0–100 刻度。

  已接入与 Power History、功率条相同的主图表配色，随供电状态、浅深外观和高对比刷新；见 [配色与验证](design/process-activity-palette/README.md)。

- [x] **Process Activity：点选进程后可强制结束。**

  点选进程后，在右侧分数位置显示小型玻璃胶囊“×”；名称和条形不移动。点击“×”确认后可强制结束对应进程，兼容简洁和详细显示模式。

  已实现原生确认、完整进程身份核验和同用户降权执行；验证记录见 [实现与验证](design/process-force-quit/README.md)。
