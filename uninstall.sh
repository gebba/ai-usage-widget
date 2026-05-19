#!/usr/bin/env bash
set -euo pipefail

APPLET_ID="io.github.gebba.ai-usage-widget"
HELPER_DIR="$HOME/.local/lib/ai-usage-widget"
HELPER_DEST="$HELPER_DIR/codex_usage.py"
BIN_LINK="$HOME/.local/bin/ai-usage-widget-helper"
CACHE_DIR="$HOME/.local/state/ai-usage-widget"
KEEP_CACHE=0

if [[ "${1:-}" == "--keep-cache" ]]; then
  KEEP_CACHE=1
fi

if command -v kpackagetool6 >/dev/null 2>&1; then
  if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$APPLET_ID"; then
    kpackagetool6 --type Plasma/Applet --remove "$APPLET_ID"
  else
    echo "Plasma widget is not installed: $APPLET_ID"
  fi
else
  echo "kpackagetool6 not found; skipping Plasma widget removal" >&2
fi

rm -f "$BIN_LINK" "$HELPER_DEST"
rmdir "$HELPER_DIR" 2>/dev/null || true

if [[ "$KEEP_CACHE" -eq 0 ]]; then
  rm -rf "$CACHE_DIR"
else
  echo "Keeping cache: $CACHE_DIR"
fi

cat <<EOF

Uninstall complete.

If Plasma still shows the widget, restart Plasma Shell:
  systemctl --user restart plasma-plasmashell.service

EOF
