# Selected-task Auto-resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the owner opt individual Codex conversations into one automatic continuation after a structured quota failure and quota recovery.

**Architecture:** A persisted ledger owns selection and at-most-once dispatch. The existing app-server connection lists and inspects tasks, then submits a guarded continuation to Codex’s native queue after a second safety read. Settings controls selection; the overview provides queue access.

**Tech Stack:** Swift 5, SwiftUI/AppKit, Codex app-server JSON-RPC, UserDefaults.

**Spec:** `docs/auto-resume-design.md`

## Global Constraints

- Selection defaults off and is scoped to the Codex account ID.
- Never consume a reset card or approve a task action automatically.
- Automatic submission requires structured quota failure, available quota, and an unchanged latest turn.
- Persist a handoff intent before `thread/queue/add`; never silently retry an uncertain result. The capsule must not run `turn/start` itself.

## Review Focus

- Account switch: no task from the previous account runs.
- Turn changes between first and second read: no continuation is sent.
- Crash or timeout after submission: the same turn is not submitted twice.
- No structured quota error: no automatic continuation.
- Weekly quota exhausted while five-hour quota is available: no continuation.

---

### Task 1: Queue policy and persistence

**Files:** Create `Sources/AutoResume.swift`; test in `Tests/AutoResumeTests.swift`.

- [ ] Write policy and persistence tests for the five review cases and reselecting.
- [ ] Run tests and observe expected failures.
- [ ] Implement `ResumeLedger`, `ResumeSelection`, and `resumeEligible`.
- [ ] Run tests and existing suite.

### Task 2: Read and dispatch via app-server

**Files:** Modify `Sources/Service.swift`; test in `Tests/AutoResumeTests.swift`.

- [ ] Write an integration test with a fake `CodexServing` for selection, quota refresh, the second read, and single dispatch.
- [ ] Run it and observe failure.
- [ ] Add recent thread loading, selected-thread inspection, guarded cold `thread/queue/add`, and native desktop wake-up.
- [ ] Run tests and the native build.

### Task 3: Owner controls and release

**Files:** Modify `Sources/App.swift`, `Sources/Views.swift`, translations, README files; verify with full tests and UI build.

- [ ] Add selection list in Settings and a small overview queue row without changing the compact capsule.
- [ ] Localize visible strings and explain the feature and limits in docs.
- [ ] Build and run full tests; inspect the result and publish the repository update.
