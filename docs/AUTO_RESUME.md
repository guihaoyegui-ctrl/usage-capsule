# 自动续跑 / Selected-task auto-resume

## 使用方法

1. 从概览、右键菜单或设置进入 **自动续跑**。
2. 勾选允许自动继续的任务；默认没有选中任何任务。
3. 保持胶囊运行。当胶囊读到明确的额度错误及额度耗尽，或能根据相邻两次刷新可靠识别刚发生的重置时，将任务加入等待队列。五小时和周额度都重新可用后，会把一次继续指令交给 Codex 的原任务队列。
4. 点击打开按钮可查看原对话；点击 × 或“全部取消”会取消监测，并尝试移除尚在队列中的指令。如果 Codex 已经开始执行，请在原对话中停止。

胶囊逐个提交续跑指令，并等待上一条队列记录得到确认。额度检查不调用模型；**实际续跑会调用模型并消耗额度**。自动续跑不会使用重置卡，也不会替你批准操作；任务由 Codex 按原有权限和审批设置执行。

这是预览功能，需要支持任务读取和原生队列的本机 Codex CLI 与桌面应用。当前只接受 Codex 返回的明确额度错误，不根据聊天文本猜测中断原因。两种额度都必须可读取且有余量。电脑休眠或胶囊退出时不会主动检查；只在可核实的相邻刷新或已保存的等待记录中恢复。登录失效或账号改变时暂停原账号的续跑。

提交超时不代表未入队，因此胶囊会核对 Codex 队列与对话记录；无法确认时标记“提交结果待核实”，不重复发送，也暂停其他自动交接。请打开原对话核实。原生队列是实验接口，目标任务正被其他客户端操作时可能延迟处理；建议在操作该任务前取消其自动续跑选择。

## English

Open **Auto-resume** from the overview, context menu, or Settings. Select individual conversations; none are selected by default. Selection is bound to the current account. Deselect a conversation or choose **Deselect all** to stop monitoring and remove a continuation still in the queue. Stop work that has already started in its original Codex conversation.

The capsule requires a structured quota failure (`usageLimitExceeded` or `rateLimitExceeded`) plus observed exhaustion, or a conservatively verified reset transition between nearby polls. Both five-hour and weekly quotas must be known and available. It checks the latest turn again and submits a continuation to the native Codex queue, asking Codex to inspect completed work. The desktop app owns execution; the capsule does not start an independent model turn. A pending handoff is reconciled before another is submitted.

Quota polling does not use model tokens. **A continuation is a model turn and uses quota.** The feature does not consume reset cards or approve tools. Codex handles execution and any approval requests using the task's existing settings.

This preview depends on the installed Codex CLI and desktop app supporting the native thread queue. It cannot check while the Mac sleeps or the capsule is closed, and it does not infer a missed exhaustion from available quota alone. Recorded waiting and dispatch states survive relaunch. An uncertain submission is never retried automatically: inspect the original conversation. The native queue is experimental; other clients operating the same task can delay processing.

Validation covers simulated quota transitions, account mismatch, changed turns, cancellation, duplicate prevention, uncertain submission, and cross-process ledger locking. An isolated offline test confirmed that a cold app-server queue entry is visible to a second app-server; repeated client IDs do not deduplicate submissions. On 2026-10-28, two disposable local Codex tasks were used to test the actual widget service: simulated quota exhaustion and recovery successfully handed one task to the real desktop queue, woke Codex, produced the expected short model response, and reconciled the result. A second queued task was cancelled before a model turn. The test conversations were archived. No real quota exhaustion/reset or reset-card consumption was performed.
