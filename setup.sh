#!/bin/sh
set -e

REPO_RAW="https://raw.githubusercontent.com/nninnis/claude-statusline/main"
SCRIPT_DEST="$HOME/.claude/statusline-command.sh"
SETTINGS="$HOME/.claude/settings.json"

echo "→ Downloading statusline-command.sh..."
curl -fsSL "${REPO_RAW}/statusline-command.sh" -o "$SCRIPT_DEST"
chmod +x "$SCRIPT_DEST"

echo "→ Updating ~/.claude/settings.json (statusLine only)..."
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

if command -v jq >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq --arg cmd "sh $SCRIPT_DEST" '.statusLine = {"enabled": true, "command": $cmd}' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
else
  echo "⚠ jq not found. Add this to ~/.claude/settings.json manually:"
  echo "  \"statusLine\": { \"enabled\": true, \"command\": \"sh $SCRIPT_DEST\" }"
fi

echo "✓ Done. Restart Claude Code to apply."
