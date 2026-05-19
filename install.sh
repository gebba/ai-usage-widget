#!/usr/bin/env bash
set -euo pipefail

APPLET_ID="io.github.gebba.ai-usage-widget"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_SRC="$ROOT_DIR/helper/codex_usage.py"
HELPER_DIR="$HOME/.local/lib/ai-usage-widget"
HELPER_DEST="$HELPER_DIR/codex_usage.py"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/ai-usage-widget-helper"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd python3
require_cmd kpackagetool6

if [[ ! -f "$HELPER_SRC" ]]; then
  echo "Helper not found: $HELPER_SRC" >&2
  exit 1
fi

install -d -m 755 "$HELPER_DIR" "$BIN_DIR"
install -m 755 "$HELPER_SRC" "$HELPER_DEST"
ln -sfn "$HELPER_DEST" "$BIN_LINK"

echo "Installed helper: $HELPER_DEST"
echo "Installed helper symlink: $BIN_LINK"

if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$APPLET_ID"; then
  kpackagetool6 --type Plasma/Applet --upgrade "$ROOT_DIR"
else
  kpackagetool6 --type Plasma/Applet --install "$ROOT_DIR"
fi

# Prime the cache. Do not fail the install if auth is missing/expired; the widget
# will show the helper's sanitized error state.
if "$HELPER_DEST" --print >/tmp/ai-usage-widget-install-state.json 2>/tmp/ai-usage-widget-install-error.log; then
  echo "Fetched initial usage cache."
else
  echo "Installed, but initial usage fetch failed. The widget will show the error state." >&2
  echo "Run for details: $HELPER_DEST --print" >&2
fi

cat <<EOF

Install complete.

Add or refresh the Plasma widget: AI Usage Widget

If an already-added widget still uses stale QML, restart Plasma Shell:
  systemctl --user restart plasma-plasmashell.service

The widget now runs the helper from:
  $HELPER_DEST

EOF
