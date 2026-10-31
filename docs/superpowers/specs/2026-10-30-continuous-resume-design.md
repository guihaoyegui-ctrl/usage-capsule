# Optional continuous quota recovery

User explicitly requests an unlimited resume option and autonomous implementation. Extend the existing native Swift app in place on its feature branch, preserving the pending membership changes. Existing authorizations remain unchanged.

Modes: once (default) and continuous (explicit per task). Continuous means repeated recovery from later quota failures, never a loop after ordinary completion, manual stop, approval request, or other errors. No model work or reset-credit consumption is used for monitoring. A user can pause all monitoring, revoke a task, or change mode by explicitly renewing consent. Selecting a mode does not grant consent until the task authorization action. Old selections are retained but never appear actively checked.

Keep one persistent authorization for continuous mode; each failed turn still has one durable handoff and stable client UUID. The shared locked ledger enforces mode and revocation across instances. Only confirmed terminal quota failures (correlated turn, structured quota error, valid completedAt) may release a continuous handoff barrier; interrupted or ambiguous states still need inspection. Continue requiring observed quota exhaustion or verified reset, backend permission, same verified account, reserves, empty native queue, and unchanged latest turn.

Approaches: automatically renewing one-shot UUIDs was rejected because stale instances and cancellation could resurrect consent. A persistent mode-aware authorization uses existing locked authority and never upgrades old consent. Normal completion leaves monitoring armed for a later quota failure; it does not assert whole-project completion or invent new work.

UI: per-task mode selector and explicit authorize button, badges for once/continuous, clear ongoing monitoring status and cancellation, checkbox indicates effective authorization or an in-flight authorized handoff only. Do not enable continuous mode on Gary’s existing projects during installation or testing.
