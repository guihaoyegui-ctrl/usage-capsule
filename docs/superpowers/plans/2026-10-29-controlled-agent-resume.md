# Controlled agent resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement task-by-task. Steps use checkbox syntax.

**Goal:** Ship the approved controlled-resume first two stages as a local preview.
**Architecture:** Extend the existing locked handoff ledger for tracking and shared pause; retain native queue delivery, never start an independent turn. Account-bound one-shot selections, correlated history, local result cards and opt-in notifications.
**Tech Stack:** Swift 5 mode, SwiftUI/AppKit, macOS 13+, existing Codex app-server protocol, Foundation/UserNotifications; no new dependency.
**Spec:** docs/superpowers/specs/2026-10-29-controlled-agent-resume-design.md

## Global Constraints
- No default task selection, no automatic reset cards, no tool approvals.
- Unknown delivery blocks dispatch; client IDs correlate but do not deduplicate.
- Keep 184 × 60 pt capsule, glass assets and reveal animation.
- No historical pre-selection failure recovery. One confirmed handoff consumes one authorization.
- State must be supported by evidence, turn completion is not project completion.
- Do not expand existing authorizations: legacy selections await explicit one-shot renewal.
- Existing dirty baseline contains the previous preview; preserve it and work on feature/controlled-agent-resume.

## Review Focus
- Pause/cancel/account change during any awaited check must block subsequent delivery.
- Other clients can change latest turns; only correlate our client ID to the same actual turn.
- Queue removal without history evidence must never imply completion or allow replay.
- Cross-instance pause, clear, release and tracking updates must preserve the lock and tombstones.
- Notifications denied, missing final responses and app relaunch must not affect delivery correctness.

### Task 1: Durable policy and tracking
**Files:** Sources/AutoResume.swift, Sources/HandoffLedger.swift, Tests/AutoResumeTests.swift, Tests/HandoffLedgerTests.swift.
**Interfaces:** ResumeLedger.move(threadID:offset:), one-shot authorization via selection authorizationVersion/consumed handoff; HandoffLedger.setPaused(_:), hasDispatchBlocker, releaseAfterInspection(clientMessageID:), updateProgress(clientMessageID:turnID:status:excerpt:).
- [x] Write failing tests for single-shot exhaustion, ordering, legacy consent, shared pause and running handoff blocking.
- [x] Run test.sh and observe RED.
- [x] Implement policy and locked companion controls, backward-compatible optional record fields.
- [x] Run test.sh; expected zero failures; record task evidence.

### Task 2: Reliable orchestration
**Files:** Sources/AutoResumeService.swift, Sources/ResumePresentation.swift (new), Sources/Service.swift, Tests/NativeQueueTests.swift.
**Interfaces:** QuotaStore.setResumePaused(_:), moveResumeTask(_:offset:), renewResumeAuthorization(_:), releaseResumeHandoff(_:); structured ResumeTaskStage; correlated turn/history progress.
- [x] Add failing behavioral tests for pause during await, renewal, serial dispatch, final-response correlation, account changes, missing state and quota thresholds.
- [x] Run test.sh to observe RED.
- [x] Implement rechecks and correlated progress; unknown terminal state keeps serial barrier. Confirmed completed final response frees barrier; interrupted/failed work needs owner action.
- [x] Run test.sh; expected all previous and new cases PASS.

### Task 3: Native UI and localized controls
**Files:** Sources/ResumeSettingsView.swift, Sources/Views.swift, Sources/App.swift, Resources/*.lproj/Localizable.strings.
**Interfaces:** Presenter exposes labels/counts; UI calls Task 2 methods. Search is explicitly limited to loaded items. Status dot cannot steal drag input.
- [x] Build management sections, one-shot consent/renewal, ordering, pause, retention thresholds and result cards.
- [x] Add four-language translations; resource checker and test.sh --ui expected PASS.
- [x] Render native demo at 3× and inspect actual UI, retain existing compact geometry.

### Task 4: Optional notifications and local results
**Files:** Sources/ResumeNotifications.swift (new), Sources/HandoffLedger.swift, Sources/App.swift, Tests/NativeQueueTests.swift.
**Interfaces:** ResumeNotifying protocol with authorize and deliver; injected disabled test sink, production system implementation. Persist per-record notification claim under ledger lock.
- [x] Add RED tests for repeat polling/relaunch notification deduplication, account filters, denied authorization and no model calls.
- [x] Implement explicit opt-in and actionable native notifications, immutable plain text excerpts.
- [x] test.sh --ui and build.sh expected PASS; build signature verifies.

### Task 5: Review, documentation and personal install
**Files:** docs/AUTO_RESUME.md, docs/VALIDATION.md, CHANGELOG.md, app metadata and personal source mirror.
- [x] Run fresh independent code review; fix important findings with failing regression tests first.
- [x] Run full tests and native build/signature verification, document actual tested limits.
- [x] Back up personal app and source, preserve bundle ID/preferences, install verified build and open management panel.
- [x] Read-only live account check; no owner task continuation or reset card. Real quota reset remains preview limitation.

## Decisions and evidence ledger
- Ruling: user approved the design and explicitly requested continuing implementation; execute inline without another method-selection question.
- Ruling: continue in the existing checkout on a new local feature branch, retaining dirty prior preview and a source backup; no new worktree discards prior uncommitted work.
- Pre-flight: Task 1 policy/tracking fields feed Task 2 scheduler and Task 3 UI; Task 4 notification claiming shares Task 1 lock; no conflicting signatures.

- Task 1: policy RED (second quota failure was eligible) → GREEN; test.sh zero failures. Shared controls, priority, legacy consent and notification claims tested.
- Task 2: orchestration RED (5 failures: historical failure, reserve, correlation, final result, paused wake) → GREEN; test.sh --ui zero failures.
- Task 3/4: native manager and notification module compile; four-language resource checks pass. Native render and independent review in progress.

- Final review: independent gpt-6-astra reviewer found shared authorization, wake revalidation, and stale-running presentation issues. All enter one fix pass.
- Final: fixed shared one-shot/cancellation with durable authorization UUID and consumed/revoked state in the locked begin decision; added cross-instance tests.
- Final: fixed cancellation/account wake race with immediate selection/account/current-record checks; regression failed before fix.
- Final: fixed stale-running display with confirmed/unconfirmed tracking result; regression failed before fix.
- Final: fixed preference snapshot overwrites and foreign-bundle implicit cancellation; both behavioral regressions RED→GREEN.
- Final: Ruling: OS notification banner delivery is an opt-in manual integration check, not covered by automated tests; denial and failure retain local results. Real natural quota reset remains unverified and preview status is retained.
- Final: Ruling: interrupted status from an independent reader is unconfirmed, never proof execution stopped; serial progression needs matching completed turn plus final reply or explicit owner inspection.
- Task 1–4: test.sh --ui PASS, all suites report zero failures after review fixes. No reset-card consumption or owner task generation in these tests.

- Read-only live verification: actual_completed_round_correlated=true on archived disposable task; no new generation, queue mutation, or card use.
- Native hosting-view preview inspected: all management sections fit; controls render correctly with native dark appearance.

- Task 5: complete — 2026-10-30 local 0.9.0 build 12 installed with original bundle ID. Full test.sh --ui: 241 PASS checks, zero failures; personal/public source parity, signature, and Skill metadata verified.
- Native installed UI: authorized/selection/history tabs, no-match search, rules disclosure and system close button verified. Existing selections and notification-off state preserved; no task was selected, renewed, released, or cancelled by the agent.
- Integration: retain local feature/controlled-agent-resume branch and preview status; no merge to main or public release is part of this turn. No minor review findings were deferred.
