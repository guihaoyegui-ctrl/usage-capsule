# Data flow and privacy

Usage Capsule is a local desktop app. It has no developer-operated backend, telemetry, advertising, or crash-upload service.

## Live mode

The app launches the user's installed Codex CLI as an app-server over local standard input/output. It initializes that connection and reads account rate limits and daily usage. The Codex CLI handles its existing authentication and communicates with OpenAI as needed. The widget itself does not ask for an API key or copy login credentials.

Automatic quota checks run once per minute using account-reading methods, without generating model responses. If the owner opts tasks into auto-resume, the app also reads those tasks and can submit a continuation after an observed quota exhaustion and recovery. That continuation is a model turn and consumes quota. Normal Codex conversations used to install or modify this project have their own model usage.

If the local Codex connection reports an expired login, the widget restarts that local child process and retries one read. It does not read or store the login token itself. If renewal fails, it clears the displayed quota figures and asks the user to sign in again.

Quota percentages, reset timestamps, daily totals, and reset-card counts are held in app memory for display. Local preferences store window placement, scale, language, the CLI path, and display options. A local pending-redemption ledger retains the account/card identity and idempotency key needed to reconcile an uncertain reset request. These values are not uploaded by this project. They should not be included in bug reports.

## Reset cards

A 0.8-second hold or accessibility activation only opens a confirmation dialog. A card can be consumed only after the customer explicitly chooses the confirmation button. Cancel, closing, and Escape submit nothing; Return defaults to Cancel. The app checks the account and card again after confirmation, and stops if the displayed state has changed. Reconciliation also needs fresh customer confirmation and explains that an unfinished original request may still consume a card. The request goes through the existing Codex CLI. Account checks and persistent idempotency prevent a retry from consuming a different card. Do not test this action on a real account just to verify installation.

## Selected-task auto-resume

Task selection is empty by default. Opening the picker reads local task titles and folders. The app stores selected task IDs, titles, account IDs, quota observations and failure markers in local preferences, and keeps a locked handoff ledger in its Application Support folder. It writes a continuation to Codex's native local queue and asks the desktop app to wake the conversation; it does not send the data to a developer backend. Continued tasks retain their normal Codex access and can modify files. The capsule does not approve requests on the owner's behalf. Deselecting stops monitoring and attempts to delete a queued message; work already taken by Codex must be stopped in the original conversation. See [auto-resume behavior](AUTO_RESUME.md).

## Preview and diagnostics

`--demo`, `--render-preview`, and `--render-motion` use sample data and do not query the account. Screenshots in this repository are examples.

The developer-only `--smoke` diagnostic does read live usage and writes a local report. It is not part of the installation helper. Do not run or publish that report without reviewing its contents.

`doctor` reports the platform, compiler, local CLI path, and installation destination. `status` reports only the app installed at the helper's configured path. These outputs can contain local filesystem paths; redact those before sharing publicly.
