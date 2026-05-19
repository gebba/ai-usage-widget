# Changelog

## 0.1.0 - 2026-05-19

Initial public release.

### Added

- KDE Plasma 6 widget for displaying ChatGPT/Codex usage balance.
- Local helper that reads Codex CLI auth from `~/.codex/auth.json`.
- Fallback support for Pi Codex auth from `~/.pi/agent/auth.json`.
- Sanitized local cache files under `~/.local/state/ai-usage-widget/`.
- Manual install/uninstall scripts.
- Widget configuration page with:
  - auto-refresh toggle
  - Codex Spark visibility toggle
  - manual refresh action
  - source/helper debug info
- Auto-refresh every 10 minutes while the widget is loaded.
- Remaining-usage cards with color thresholds and reset-time labels.
- GPL-3.0-or-later license.

### Notes

- Uses ChatGPT/Codex's internal `https://chatgpt.com/backend-api/wham/usage` endpoint.
- This is not an official public OpenAI API integration and may break if the endpoint changes.
