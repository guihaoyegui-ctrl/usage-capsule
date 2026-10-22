# Validation scope — 0.7.0

Validated locally on an Apple Silicon Mac with Swift 6.4. The project targets macOS 13+; it has not been tested on every supported OS release.

- Logic: quota conversion and clamping, five palette levels and their boundaries, missing versus zero daily data, seven-day ordering, reset outcomes, persistent idempotency and account-switch protection.
- Interaction: click/drag/hover state transitions, dismissal, popup anchor placement, and native hit coverage across the 200 × 76 pt and 292 × 106 pt window frames, including the rim and transparent margins.
- Localization: all 84 keys present in each of four languages, matching format arguments, language resolution and fallback; rendered native sample-data previews reviewed for English, Chinese, Japanese, and Korean.
- Distribution: Skill metadata validator, native build, ad-hoc code-signature verification, and isolated source installation with paths containing spaces. Offline rendering uses sample data only.

Native hit coverage is a component check. Automated physical desktop dragging is not claimed as tested: the available automation tool cannot perform the native drag action. Live-account connectivity and reset redemption are not part of distribution tests. No card is consumed during tests.

The GitHub Actions workflow runs logic/localization checks, builds the app, and verifies the bundle. Its presence is not a claim that remote CI has passed; inspect the actual run for the published commit.
