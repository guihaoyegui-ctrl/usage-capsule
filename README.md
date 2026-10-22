# Usage Capsule

[简体中文](README.zh-CN.md) · **English** · [日本語](README.ja.md) · [한국어](README.ko.md)

A tiny, native macOS window for your Codex five-hour and weekly quota. Polished dark glass, a warm metal rim, and five clear color levels—at a visible size of **184 × 60 pt**.

![Usage Capsule and its expanded overview, showing sample data](docs/preview-en.png)

## What it does

- Shows remaining five-hour and weekly quota, reset times, and a reset countdown.
- Opens an animated overview on hover; click to pin, × or Escape to close.
- Shows seven daily token cells; select a cell for the exact daily total.
- Uses pale gold → amber → orange → vermilion → coral as quota falls. The lamps stay readable around 50%.
- Supports dragging from the whole widget frame, a menu-bar recovery control, 100–150% scaling, and always-on-top mode.
- Includes Simplified Chinese, English, Japanese, and Korean, with automatic system-language selection.
- Displays eligible reset cards, with a deliberate 0.8-second hold to use one. Preview and demo modes cannot redeem cards.

## Requirements

**macOS 13 or later on Apple Silicon**, Xcode Command Line Tools, and a local signed-in Codex CLI for live usage. The native app is written in SwiftUI and AppKit, with no Electron or Node dependency.

This is a community project, not an official OpenAI product. Daily usage and reset-card support depend on the methods exposed by the installed Codex CLI and the current account. Unsupported or missing values appear as unavailable.

## Install with a Codex Skill

Ask Codex:

> Use $skill-installer to install skills/usage-capsule from https://github.com/guihaoyegui-ctrl/usage-capsule. Then use $usage-capsule to build, install, and start the desktop widget on my Mac.

The skill includes the full app source and glass assets. Installing the skill alone does not start a widget. A local macOS session is required; a cloud-only session cannot put a native window on your desktop.

## Build and install manually

Download this repository, open its folder in Terminal, then run:

```sh
zsh skills/usage-capsule/scripts/capsule.sh doctor
zsh skills/usage-capsule/scripts/capsule.sh install
zsh skills/usage-capsule/scripts/capsule.sh start
```

The app is built locally, ad-hoc signed, and installed at `~/Applications/Usage Capsule.app`. This preview is not Developer ID notarized. Do not disable Gatekeeper; build from the reviewed source. If the compiler is missing, install Apple's Command Line Tools with `xcode-select --install`.

Right-click the capsule or use its menu-bar icon for Settings, Refresh, Hide, and Quit. Choose a language in Settings or run:

```sh
zsh skills/usage-capsule/scripts/capsule.sh language en
```

Supported codes: `system`, `zh-Hans`, `en`, `ja`, `ko`. For an offline PNG with sample data, run `preview`. For an installed demo window, run `demo` while the installed app is stopped. `status` checks only this helper's installed process; it does not prove the account is connected.

## Data and privacy

Live refresh runs every 60 seconds using the local Codex app-server's account-reading methods. It creates no model generation turn. The app uses your existing local Codex login and has no analytics service or developer backend. See [data flow and privacy](docs/PRIVACY.md) and [troubleshooting](docs/TROUBLESHOOTING.md).

## Development

```sh
zsh skills/usage-capsule/assets/app/test.sh
zsh skills/usage-capsule/assets/app/test.sh --ui
```

The first command checks quota math, reset idempotency, interaction state, and all four translation packs. `--ui` also checks native hit coverage and requires a desktop session. Tests never redeem a reset card. See [validation scope](docs/VALIDATION.md) and [release notes](CHANGELOG.md).

Source lives inside [`skills/usage-capsule/assets/app`](skills/usage-capsule/assets/app), so the skill remains self-contained when installed separately. The root `plugin.json` also packages the skill in the portable Agent Plugins layout; publishing this repository does not list it in the official plugin directory.

## License

No open-source license has been selected for this preview yet.
