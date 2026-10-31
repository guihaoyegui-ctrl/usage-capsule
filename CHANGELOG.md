# Changelog

## 0.10.1 preview — 2026-10-31

- Scope task-picker checkboxes to the displayed recovery mode and show each task's actual authorization mode. Browsing modes never changes consent.
- Explicitly checking another mode replaces the previous authorization; unchecking another mode cannot revoke it. In-flight handoffs prevent mode changes with an explanation.
- Preserve explicit reauthorization after account changes instead of retaining an old-account selection.
- Cancel captured handoff IDs without a deferred task-wide revocation, so rapid deselect/reselect cannot erase newly granted consent.

## 0.10.0 preview — 2026-10-31

- Add explicit per-task once or continuous quota recovery, with persistent revocation across distinct failures and app restarts.
- Atomically replace mode-aware authorizations across instances; protect confirmed terminal quota results from stale progress reads.
- Keep per-failed-turn deduplication, account, reserve and pause checks. Normal completion never starts another round; interrupted or ambiguous results need inspection.
- Correct spent/legacy checkbox states and document all features in four languages. Multiple natural reset cycles remain a manual field-verification item.

## 0.9.1 preview — 2026-10-30

- Show membership in the overview and explain the 60-second plan/usage check cadence, with account-event, manual, activation and wake refresh.
- Normalize quota windows by duration; display scoped five-hour infinity for the recognized Pro family when no finite five-hour window is returned, while retaining real weekly limits.
- Support backend-confirmed entry-plan windows without inventing missing quota. Require explicit ordinary-usage permission for automatic recovery; older endpoints without it remain display-only.
- Invalidate in-flight handoffs on account events and clear inference evidence after unsupported or failed snapshots. Pro weekly-only quota checks share the same reserve and final dispatch policy.
- Preserve memberships only as last-verified data after temporary failures; clear them when authentication expires.

## 0.9.0 preview — 2026-10-29

- Add one-shot authorization with legacy re-consent, task priorities, loaded-list search, global pause, and per-account quota reserves.
- Share consumed/revoked authorization identities under the handoff lock; prevent stale instances and preference snapshots from reviving cancelled or already-used consent.
- Hold subsequent handoffs until the exact continued round is confirmed complete with its final reply, or the owner explicitly inspects and releases the barrier.
- Add a three-tab manager, compact status summary, local result cards and opt-in system notifications. No extra model call is made to prepare a result card.
- Verify correlated completion using read-only history from the prior disposable live test. Natural quota exhaustion/reset and OS notification banner delivery remain manual verification items.

## 0.8.0 — 2026-10-28

- Add an opt-in task picker and native Codex queue handoff after a verified quota failure and recovery, with individual removal and queued-message cancellation.
- Bind selections to the account; require explicit quota errors and both quotas to be available, recheck the latest turn, and persist dispatch markers before submission.
- Persist locked handoff records before submission, reconcile uncertain outcomes without resending, and let Codex handle execution and approvals. Quota polling remains non-generative; continuations use quota.
- Add simulated-service coverage and document the preview's runtime and compatibility limits. A disposable task completed one real desktop model turn after simulated quota recovery; cancellation was separately verified in the real queue. No real quota reset or reset card was used.

## 0.7.2 — 2026-10-27

- Recover from an expired Codex login by rebuilding the local background connection and reading quotas again once.
- Hide stale percentages and show a sign-in message if renewal still fails, instead of leaving a misleading 99% on the capsule.
- Cover renewed, still-expired, and temporary-network-error cases with simulated-service tests.

## 0.7.1 — 2026-10-23

- Require a separate customer confirmation before every reset or pending-reset reconciliation, including accessibility activation.
- Default to Cancel; recheck account and card state after confirmation and reject stale consent.
- Add simulated-service regression tests and confirmation text in all four languages.

## 0.7.0 — 2026-10-19

- Package the native Usage Capsule as a self-contained Codex Skill with app source, glass assets, helper, and tests.
- Add English, Japanese, and Korean alongside Simplified Chinese, plus system-language selection and Settings switching.
- Preserve the polished glass, five-tier quota colors, animated overview, and full-frame drag target.
- Add reproducible local installation, sample previews, troubleshooting, privacy notes, and macOS validation workflow.
- Use a separate public bundle identity so this package can coexist with the original personal preview.
