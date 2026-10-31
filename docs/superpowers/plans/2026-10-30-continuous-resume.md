# Continuous Resume Implementation Plan

> For agentic workers: use superpowers:executing-plans inline. User has already authorized autonomous implementation and GitHub synchronization.

**Goal:** Optional repeated quota recovery for explicitly selected tasks.
**Architecture:** Mode-aware shared authorization, durable deduplication per failed turn, terminal quota-failure barrier release, existing account/reserve checks.
**Tech Stack:** Swift / SwiftUI / AppKit; no dependencies.
**Spec:** ../specs/2026-10-30-continuous-resume-design.md

## Global Constraints
- Once remains default; no upgrading legacy consent; no real-task authorizations during tests.
- Never consume reset credits automatically; never loop on normal completion or manual interruption.
- Preserve the existing personal bundle ID and preferences, visuals, 60-second cadence and pending membership work.

## Review Focus
- Two recovery cycles with a process restart; stale instance cancellation and per-turn duplication.
- Confirmed quota failure versus interrupted/live or non-quota failure.
- Ordinary completion never produces another continuation.
- Checkbox and authorization list accurately represent spent and legacy consent.
- Account changes, denial, reserve floor and pause continue to block.

### Task 1: Mode-aware recovery
Files: Domain.swift, AutoResume.swift, HandoffLedger.swift, AutoResumeService.swift, Tests/ContinuousResumeTests.swift, test.sh.
- [x] Add real service/ledger tests for repeated recovery and negative paths; observe RED.
- [x] Persist optional mode (missing = once), allow multiple distinct failed turns only for active continuous authorization; confirm quota terminal barrier release.
- [x] Run the complete test.sh suite and inspect output.

### Task 2: Explicit UI and publication
Files: ResumeSettingsView.swift, ResumePresentation.swift, four localization packs, four READMEs, CHANGELOG.md, plugin.json and Info.plist.
- [x] Expose per-task mode, accurate check state, continuous monitoring labels and revoke controls.
- [x] Build both app variants, install personal with rollback backup and preferences unchanged; visually check without authorizing real tasks.
- [x] Independent review and one evidence-backed fix pass.
- [ ] Update existing GitHub PR with all pending changes and feature documentation, verify CI and publish main.

Evidence: continuous regression RED = five expected failures; review regression RED = three expected failures. Final test.sh --ui = 304 PASS, zero FAIL. Mode replacement now occurs in one lock transaction, rejects delayed older grants, and confirmed terminal quota failure is monotonic against stale progress. Native UI installation/publication checks pending.

Installed personal 0.10.0 build 14 with exact bundle ID preserved and backup; source mirror byte parity verified. Native AX check confirmed both mode options and accurate unchecked legacy/spent selections. During later inspection the owner interacted with the app; no task authorization was changed by the agent. Public build signed and verified. Review fixes are covered by RED-to-GREEN regressions; no re-review dispatched.
