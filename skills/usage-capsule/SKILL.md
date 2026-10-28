---
name: usage-capsule
description: Install, launch, configure, or troubleshoot the Usage Capsule desktop quota widget on an Apple Silicon Mac. Use for its five-hour/weekly quota display, languages, seven-day token view, and owner-selected task auto-resume.
---

# Usage Capsule

This skill includes the complete native macOS app source and glass assets. Installing this skill alone does not launch a desktop widget. Resolve all paths below from this skill directory.

## Install and start

1. Run `zsh scripts/capsule.sh doctor`. Requires macOS 13+, Apple Silicon, Xcode Command Line Tools, and a local Codex CLI for live data. If the compiler is absent, explain `xcode-select --install`; if Codex is absent, help the user install/sign in. A web or cloud-only environment cannot display this native widget on the user's desktop.
2. On a request to install, run `zsh scripts/capsule.sh install`. It builds locally and installs `~/Applications/Usage Capsule.app`. Use the environment's normal filesystem permission mechanism when that directory is protected.
3. On a request to start, run `zsh scripts/capsule.sh start`, then `status`. Report the installed path and process status; verify the visible widget with available desktop tools before claiming visual success. Process startup alone does not prove account connectivity.

Use `preview` for a safe generated PNG or `demo` for an installed demo window. These use sample data and do not read account usage. Live startup uses the user's existing local Codex login. Do not collect, copy, print, or upload authentication files.

In a restricted agent sandbox, process inspection (`status`, `install`, `stop`) and native rendering may require the environment's normal local process/desktop permission mechanism. Request only that access; do not disable the sandbox. For a read-only skill directory, set `USAGE_CAPSULE_BUILD_DIR` to a writable absolute directory. Use `USAGE_CAPSULE_INSTALL_DIR` for an alternate installation directory.

## Controls and configuration

- Drag anywhere in the widget's rectangular frame, including the rim and margins. Hover to preview; click to pin. Close the overview with × or Escape. The menu-bar item can recover a hidden widget; right-click offers settings, hide, refresh, and quit.
- Language: select System, 简体中文, English, 日本語, or 한국어 in Settings, or run `language system|zh-Hans|en|ja|ko`. The helper restarts only its own installed app when needed.
- The compact labels show the five-hour window and weekly quota. The seven date cells show daily token consumption. Missing daily data is unavailable, not zero; an older CLI may support quota but lack daily usage.
- Quota checks run every 60 seconds and read `account/rateLimits/read` and `account/usage/read` without model generation. Opt-in task continuations do start model turns and consume quota. The installation conversation itself also has its normal model usage.
- Auto-resume is opt-in per task from the overview, menu, or Settings. Let the owner select tasks; installation and diagnosis do not authorize selecting tasks or starting a live continuation. The app detects structured quota failures and observed exhaustion or a narrowly verified reset transition, waits for both quota windows, then submits to Codex's native queue for desktop execution. It preserves account scope and durable dispatch markers and skips ambiguous interruptions. Deselecting stops monitoring and attempts to remove a still-queued message; work already started must be stopped in the original Codex conversation. Keep the app running; long missed intervals are not inferred. Do not claim a real quota-reset continuation has been tested from a simulated-service test alone.
- If the local Codex login expires, the app rebuilds its background connection and retries one read. Persistent authorization failure clears stale quota figures and offers sign-in; do not present an old percentage as live usage.
- A 0.8-second hold or an accessibility action only opens the reset confirmation dialog. Only the customer's explicit confirmation can submit a request. Cancel, closing, and Escape submit nothing. Do not confirm the dialog on the customer's behalf. **Never redeem a card during installation, diagnostics, preview, or tests.** Do not automate consumption or bypass the account/idempotency checks.

For diagnosis, use `doctor`, `status`, and the overview's refresh/error text. Use `stop` only when asked to stop or update this installed app. Do not kill other Codex processes or disable Gatekeeper. The source is in `assets/app`; run `zsh assets/app/test.sh` for logic/localization checks and add `--ui` for native hit coverage when a GUI session is available.
