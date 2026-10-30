# Membership-aware quota compatibility Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans. User approved automatic plan adaptation and requested implementation, so continue inline.

**Goal:** Show membership and refresh cadence, support Pro weekly-only quotas, retain Plus behavior and safely degrade Free/Go.
**Architecture:** Normalize windows by duration in one QuotaProfile. Reuse the same profile for display, reserve checks, recovery observations and final locked dispatch. Membership comes from the same successful quota snapshot, never stale account metadata from another request.
**Tech Stack:** Existing native SwiftUI/AppKit macOS 13+, Foundation Codable; no dependencies.
**Spec:** Approved user requests on 2026-10-30: automatic Plus/Pro compatibility, Pro scoped infinity, basic Free/Go compatibility, membership in overview, explain detection cadence.

## Global Constraints
- No model call for checking membership. Poll every 60 seconds; also refresh on supported account events, app activation/wake and manual action.
- Infinity means no five-hour cap only, never unlimited weekly use or unknown data. Explicit finite five-hour data takes precedence over plan policy.
- Unknown plans/missing data must not silently become unlimited; use duration to place a weekly-only primary slot correctly.
- Recheck fresh membership and account at dispatch. A backend ordinaryUsageAllowed=false always blocks automatic continuation.
- Free/Go with partial quota data may resume only with explicit backend usage permission and at least one known usable window; otherwise display-only.
- Preserve user selections, single-shot controls, original appearance and per-reset confirmation.

## Review Focus
- Weekly quota moves from secondary to primary after plan change.
- Pro variants, unknown plans and missing durations do not misclassify limits.
- Conflicting old/new plan snapshots during awaited preflight cannot dispatch with stale privileges.
- Failed login, downgrade, failed reads and backend-denied ordinary usage clear or label prior plan data.
- Unsupported Free/Go usage endpoints do not break quota/membership refresh.

### Task 1: Quota profile and recovery
**Files:** Domain.swift, AutoResume.swift, HandoffLedger.swift, test.sh, Tests/PlanCompatibilityTests.swift (new), ResetTransitionTests.swift.
- [ ] Add RED tests for Pro weekly-only, swapped slots, infinity boundaries, unknown/ambiguous data, backend denial and reserves.
- [ ] Implement duration-based windows and shared availability semantics; preserve dual-window legacy tests.
- [ ] Adapt conservative reset observations to verified Pro weekly-only without assuming missing means unlimited.
- [ ] Run test.sh, expect zero failures.

### Task 2: Refresh and scheduler integration
**Files:** Service.swift, AutoResumeService.swift, ResumePresentation.swift, Tests/RefreshRecoveryTests.swift, NativeQueueTests.swift.
- [ ] Add RED tests for upgrade/downgrade/account change, Pro resume without five-hour data, blocked backend and false reset on upgrade.
- [ ] Read plan from every quota response; check profile in fresh dispatch and locked reserve decision. Reset inference cannot cross a plan change.
- [ ] Refresh on supported account change events; coalesce refresh requests arriving during a refresh; bounded retries remain unchanged.
- [ ] Run full suite, expect PASS.

### Task 3: Membership UI, infinity and delivery
**Files:** Views.swift, ResumeSettingsView.swift, App.swift, Resources/*.lproj, metadata/docs.
- [ ] Keep compact 184×60 pt; use infinity without percentage or empty battery for a confirmed unmetered five-hour window.
- [ ] Add overview membership badge and readable 60-second polling explanation/last-confirmed time. Hide Pro five-hour countdown/reserve, show weekly normally.
- [ ] Translate four languages, verify full UI tests, native Plus/Pro previews and independent review; fix important findings with RED→GREEN tests.
- [ ] Back up/install signed personal preview retaining preferences. No real card or owner-task test execution.

## Evidence / decisions
- Continue on existing feature branch with clean committed 0.9.0 baseline; source snapshot saved locally.
- Official documentation fetched in previous turn confirms Pro currently has no five-hour cap; use recognized Pro family plus unambiguous response, not absence alone.

- Live read-only protocol check: current account returns planType=plus, ordinaryUsageAllowed=true, and durations [300,10080]; no model generation or card use.
- Task 1: QuotaProfile tests RED (missing API, then unknown permission incorrectly allowed) → GREEN. 28 domain cases cover Pro variants, swapped windows, missing and ambiguous data, entry tiers and backend permissions.
- Task 2: service regressions RED (upgrade mislabel, Pro resume blocked, backend denial ignored) → GREEN. Account event API RED → GREEN; coalesced follow-up is bounded to one extra read.
- Task 1/2 full test.sh --ui PASS with zero failures, including weekly-only reset and plan-change exclusion.
- Ruling: authoritative ordinaryUsageAllowed must be true for production automatic continuation, even for full Plus payloads. Older services without this field remain display-only; this follows the installed protocol's explicit null-is-unknown contract. The current live service provides the field.

- Independent review found two Important races: in-flight account event invalidation and stale inference across unsupported snapshots. Both reproduced with failing service tests and fixed in one pass.
- Also caught and fixed a notification race on account invalidation (RED→GREEN).
- Ruling: custom duration truncation was regraded Important because newly displayed 30/90-minute limits would show incorrect hours; exact duration display fixed with failing tests.
- Deferred minor: Free/Go weekly-only missed-reset inference stays conservative until real payload verification; directly observed failure/recovery remains supported and documented.
- Native 3× Plus/Pro sample render inspected; member badge, scoped infinity, countdown removal and unchanged compact dimensions verified.

Delivery: membership adaptation is included in the installed 0.10.0 build 14, with the continuous-recovery update. The full combined suite passed 304 checks including native interaction tests. Both personal/public app builds passed and personal source parity was verified. Real Plus read confirmed; other plan simulations are not live account validation. GitHub synchronization follows the combined feature publication.
