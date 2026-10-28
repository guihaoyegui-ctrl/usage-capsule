# Changelog

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
