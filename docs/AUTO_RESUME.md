# 自动续跑 / Selected-task auto-resume

## 0.10.1：模式勾选修复

选择任务页的勾选只反映当前模式；切换查看不会修改已有授权。另一个模式已授权的任务会显示其实际模式，再明确勾选将替换原授权，同一任务只有一种有效模式。正在排队或执行时不能直接切换，请先取消排队或核实。快速取消再勾选不会被较晚执行的旧取消操作误撤销。

Picker checkboxes are mode-specific. Browsing does not alter consent; explicitly checking another mode replaces the existing grant. An unrelated mode's unchecked state cannot cancel a task. Pending/running handoffs block mode changes. Rapid reselection preserves the new consent.

## 0.10.0：单次与持续续跑

每个项目可明确授权「仅续跑一次」（默认）或「持续续跑（不限次数）」。在选择任务页先选模式再勾选，或在已授权任务页的「续跑模式」菜单内明确授权。旧选择不会自动升级，安装与诊断也不会替用户授权。持续授权在重启后保留，直到取消；总暂停与额度保留值对两种模式都有效。

持续模式只接续授权之后新发生的、可核实的额度中断。每个失败回合有唯一持久化记录，跨实例也不会重复发送。已接续回合再次以结构化额度错误明确结束，并有完成时间时，可放行其串行屏障；恢复后接续下一次中断。正常完成保持监测，不自动开新一轮；等待输入、手动中断、一般错误和不确定结果仍需用户处理。取消授权会尝试撤回尚未执行的指令，已运行任务需在原对话停止。不会自动使用重置卡。

Continuous mode is explicit per task, survives restart and recovers later verified quota interruptions until revoked. Once remains default. Normal completion never initiates a new round; owner input, manual interruption, unrelated failures and uncertain delivery need inspection. Only a correlated terminal quota failure with a valid completion timestamp frees the continuous serial barrier. Shared atomic mode replacement, revocation, pause, account and reserve checks still apply.

## 0.9.1：会员与额度适配

概览显示本次用量接口返回的会员等级。每 60 秒检查一次，也会在手动刷新、收到账号更新通知、胶囊重新激活或电脑唤醒时补查；服务端尚未更新的订阅状态无法提前获知，休眠或退出时不轮询。这些检查不调用模型。

额度按窗口时长归位，不依赖 primary/secondary 的排列顺序。Pro / Pro Lite / Pro Max 对应的 Pro 家族在未返回有限五小时窗口时，日额栏显示 ∞，仅代表没有五小时上限；周额仍按实际数据显示，日额倒计时及保留控制隐藏。实际返回的有限五小时窗口始终优先。该政策依据 [OpenAI 官方说明](https://learn.chatgpt.com/docs/pricing)，后续以真实账号返回数据为准。

自动续跑要求同一账号的新鲜接口明确返回 ordinaryUsageAllowed=true，并且所有已识别的适用窗口高于保留值；false 或缺失不能视为恢复。Pro 缺少五小时字段不会再阻塞续跑，但缺少周额度仍等待核实。Free/Go 有可用接口时基础兼容；部分窗口需要明确的后台许可。旧服务缺少许可字段时可以显示用量，自动续跑保持等待核实。Free/Go 仅有周窗口的遗漏重置推断暂不启用，需要直接观察到中断/恢复。

收到账号事件后，旧判断立即失效，补查确认前不派发、不唤醒，也不发送旧账号的结果通知。升级/降级不会被当作自然额度重置；不支持或无法确认的中间窗口会清除旧的推断证据。临时读取失败标记“上次确认”，登录过期清除原会员与额度。

### Membership compatibility in 0.9.1

The overview displays plan type from the same quota snapshot, checked every 60 seconds and on supported account events, manual refresh, activation or Mac wake. Backend propagation can take longer; no polling occurs during sleep/exit and no model call is used. Pro-family scoped infinity means no five-hour cap, not unlimited weekly usage; explicit finite five-hour data wins. All production continuations now require affirmative ordinaryUsageAllowed from the backend. Missing permission makes older endpoints display-only. Free/Go basic support remains dependent on actual returned capabilities and is simulated, not verified with live Free/Go accounts. A weekly-only entry-plan missed-reset inference remains deferred; direct observed recovery still works.

## 0.9.0 预览版：可控续跑

- 在三个页签中管理已授权任务、搜索已加载任务、查看续跑记录。标题悬浮可看完整内容，箭头调整优先级。
- 新选择默认仅恢复一次；旧版选择需要在“续跑模式”中明确确认，选择之前的历史中断不会触发。实际继续任务会消耗额度。
- 总暂停阻止新交接和胶囊主动唤醒，不撤回已经进入 Codex 的指令，也不会停止正在运行的任务。取消排队与在原对话停止是不同操作。
- 下一项只在上一项的对应回合及最终回复确认结束后自动放行。无法确认时显示待核实；请先打开原对话检查，再明确选择放行下一项。放行不会停止上一项，两项可能同时消耗额度。
- 可分别设置五小时和周额度保留值。达到或低于任一保留值时不再派发；它不是正在运行任务的硬消耗上限。
- 授权的使用、撤销和总暂停在多个新版胶囊间共享。旧版胶囊不理解新控制规则，请更新或退出旧版后使用。每次刷新会重新合并本地选择，避免旧实例覆盖新选择。
- 本轮结束和明确失败可选择系统通知；首次由用户打开开关才请求权限。拒绝通知仍可查看本地结果。结果卡提取原回复片段，不额外调用模型。无法可靠识别具体审批时，只提供原对话入口，不猜测审批状态。
- 仍是预览版：已通过模拟额度变化、真实队列交接/取消和真实历史关联检查；真实账号自然额度重置周期、系统横幅通知交付仍需用户实测。电脑休眠和胶囊退出期间不监测。

## Controlled resume in 0.9.0 preview

New selections authorize one future recovery, not immediate work or historical failures. Legacy selections require explicit renewal. Use priority controls, loaded-list search, global pause and separate five-hour/weekly reserves in the manager. Shared durable consent records prevent another updated instance from reusing or reviving revoked consent. Quit or update older capsules that do not understand these controls.

A queue acceptance is not evidence of execution. Further handoffs wait for the exact continued round to complete with its final response; unconfirmed progress requires inspection. Explicitly allowing the next item does not stop the previous task. Stop running work in its original Codex conversation. Optional notifications and plain-text result excerpts do not make additional model calls. OS banner delivery and a natural quota reset remain manual checks; this stays a preview.

## 基础机制与使用方法

1. 从概览、右键菜单或设置进入 **自动续跑**。
2. 勾选允许自动继续的任务；默认没有选中任何任务。
3. 保持胶囊运行。当胶囊读到明确的额度错误及额度耗尽，或能根据相邻两次刷新可靠识别刚发生的重置时，将任务加入等待队列。适用的真实额度窗口恢复且后台允许继续后，会把一次继续指令交给 Codex 的原任务队列。
4. 点击打开按钮可查看原对话；点击 × 或“全部取消”会取消监测，并尝试移除尚在队列中的指令。如果 Codex 已经开始执行，请在原对话中停止。

胶囊逐个提交续跑指令，并等待上一项对应回合可靠结束或由用户核实后明确放行。额度检查不调用模型；**实际续跑会调用模型并消耗额度**。自动续跑不会使用重置卡，也不会替你批准操作；任务由 Codex 按原有权限和审批设置执行。

这是预览功能，需要支持任务读取和原生队列的本机 Codex CLI 与桌面应用。当前只接受 Codex 返回的明确额度错误，不根据聊天文本猜测中断原因。适用的真实额度窗口都必须可确认且有余量；Pro 等会员按上面的适配规则处理。电脑休眠或胶囊退出时不会主动检查；只在可核实的相邻刷新或已保存的等待记录中恢复。登录失效或账号改变时暂停原账号的续跑。

提交超时不代表未入队，因此胶囊会核对 Codex 队列与对话记录；无法确认时标记“提交结果待核实”，不重复发送，也暂停其他自动交接。请打开原对话核实。原生队列是实验接口，目标任务正被其他客户端操作时可能延迟处理；建议在操作该任务前取消其自动续跑选择。

## English

Open **Auto-resume** from the overview, context menu, or Settings. Select individual conversations; none are selected by default. Selection is bound to the current account. Deselect a conversation or choose **Deselect all** to stop monitoring and remove a continuation still in the queue. Stop work that has already started in its original Codex conversation.

The capsule requires a structured quota failure (`usageLimitExceeded` or `rateLimitExceeded`) plus observed exhaustion, or a conservatively verified reset transition between nearby polls. All applicable quota windows must be known and available under the membership rules above. It checks the latest turn again and submits a continuation to the native Codex queue, asking Codex to inspect completed work. The desktop app owns execution; the capsule does not start an independent model turn. A pending handoff is reconciled before another is submitted; 0.9.0 additionally holds the serial barrier until the continued round is confirmed complete or explicitly released after owner inspection.

Quota polling does not use model tokens. **A continuation is a model turn and uses quota.** The feature does not consume reset cards or approve tools. Codex handles execution and any approval requests using the task's existing settings.

This preview depends on the installed Codex CLI and desktop app supporting the native thread queue. It cannot check while the Mac sleeps or the capsule is closed, and it does not infer a missed exhaustion from available quota alone. Recorded waiting and dispatch states survive relaunch. An uncertain submission is never retried automatically: inspect the original conversation. The native queue is experimental; other clients operating the same task can delay processing.

Validation covers simulated quota transitions, account mismatch, changed turns, cancellation, duplicate prevention, uncertain submission, and cross-process ledger locking. An isolated offline test confirmed that a cold app-server queue entry is visible to a second app-server; repeated client IDs do not deduplicate submissions. On 2026-10-28, two disposable local Codex tasks were used to test the actual widget service: simulated quota exhaustion and recovery successfully handed one task to the real desktop queue, woke Codex, produced the expected short model response, and reconciled the result. A second queued task was cancelled before a model turn. The test conversations were archived. No real quota exhaustion/reset or reset-card consumption was performed.
