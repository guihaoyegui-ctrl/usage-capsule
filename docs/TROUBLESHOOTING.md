# Troubleshooting

## No compiler

Install Apple's Xcode Command Line Tools with `xcode-select --install`, finish the system prompt, and run `doctor` again. This release supports Apple Silicon and macOS 13+. Windows, Linux, and Intel Macs have not been validated as installation targets.

## Codex CLI is not found

Install Codex locally and sign in. The helper checks common Codex/ChatGPT app and package-manager locations, then `PATH`. For another installation, set `CODEX_CLI_PATH` to the absolute executable path before `start`. The app saves that validated executable path for later GUI launches. Do not put account tokens in this variable.

## The process is running, but usage is unavailable

Open the overview and inspect its error/sync status. Process status is independent of account connectivity. Refresh once after signing in. An older or different CLI can expose quota without daily usage or reset-card methods; those fields remain unavailable. The `日额` label means the five-hour window, not a midnight-to-midnight daily allowance.

## Permissions in an agent sandbox

The helper may need the normal permission mechanism for writing the install directory, inspecting its own process, and rendering a native preview. A denied `ps` command or aborted desktop render does not mean the app is broken. Ask the local environment for the required access; keep the sandbox and Gatekeeper enabled.

For a read-only downloaded skill, choose writable absolute paths:

```sh
export USAGE_CAPSULE_BUILD_DIR="$HOME/Library/Caches/UsageCapsule/build"
export USAGE_CAPSULE_INSTALL_DIR="$HOME/Applications"
```

Build output and Swift module cache then stay outside the skill directory. Both `install` and `start` must use the same installation directory.

## Moving, closing, or finding the window

Drag any point in the capsule frame at least four points; small pointer jitter remains a click. Click pins the overview. Close with its × or Escape; leaving and reentering the capsule restores hover preview. Use the menu-bar icon to show a hidden capsule or quit it. Closing the overview does not quit the app.

## A reset request is uncertain

Allow the app to reconcile the stored idempotency key. Do not remove the ledger or repeatedly try different cards. Account eligibility and the server's response determine whether a card can be used. Demo and preview modes never consume cards.

## Reporting an issue

Include macOS version, chip family, app version, CLI version, interface language, and a concise reproduction. Use sample-data screenshots where possible. Remove login data, account/card IDs, local paths, live quota reports, and other private information.
