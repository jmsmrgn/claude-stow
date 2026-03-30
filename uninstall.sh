#!/usr/bin/env bash
# uninstall.sh — removes all files installed by setup.sh
# The vault directory is NOT removed automatically — it contains your data.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$HOME/.claude/settings.json"
INJECT_CMD="$SCRIPT_DIR/hooks/inject-context.sh"
CHECKPOINT_CMD="$SCRIPT_DIR/hooks/session-checkpoint.sh"

# ---------------------------------------------------------------------------
# Remove hooks from settings.json
# ---------------------------------------------------------------------------

if [ -f "$SETTINGS_FILE" ] && jq empty "$SETTINGS_FILE" > /dev/null 2>&1; then
  cp "$SETTINGS_FILE" "${SETTINGS_FILE}.bak"

  CLEANED=$(jq \
    --arg inject "$INJECT_CMD" \
    --arg checkpoint "$CHECKPOINT_CMD" \
    '
      # Remove inject-context from SessionStart
      if .hooks.SessionStart then
        .hooks.SessionStart |= map(
          .hooks |= map(select(.command != $inject))
          | select(.hooks | length > 0)
        )
        | if (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end
      else . end
      |
      # Remove session-checkpoint from Stop
      if .hooks.Stop then
        .hooks.Stop |= map(
          .hooks |= map(select(.command != $checkpoint))
          | select(.hooks | length > 0)
        )
        | if (.hooks.Stop | length) == 0 then del(.hooks.Stop) else . end
      else . end
      |
      # Clean up empty hooks object
      if .hooks == {} then del(.hooks) else . end
    ' \
    "$SETTINGS_FILE")

  printf '%s\n' "$CLEANED" > "$SETTINGS_FILE"
  echo "Hooks removed from ~/.claude/settings.json (backup at ${SETTINGS_FILE}.bak)"
else
  echo "settings.json not found or invalid — skipping hook removal"
fi

# ---------------------------------------------------------------------------
# Remove installed files
# ---------------------------------------------------------------------------

[ -f "$HOME/.claude/agents/memory-writer.md" ] && rm "$HOME/.claude/agents/memory-writer.md" && echo "Removed ~/.claude/agents/memory-writer.md"
[ -f "$HOME/.claude/stow.conf" ]               && rm "$HOME/.claude/stow.conf"               && echo "Removed ~/.claude/stow.conf"
[ -f "$HOME/.claude/stow-checkpoint.log" ]     && rm "$HOME/.claude/stow-checkpoint.log"     && echo "Removed ~/.claude/stow-checkpoint.log"
rm -f /tmp/stow_ckpt_* /tmp/stow_prompt_*

# ---------------------------------------------------------------------------
# Remind user about vault
# ---------------------------------------------------------------------------

VAULT_DIR=$(grep VAULT_DIR "$HOME/.claude/stow.conf" 2>/dev/null | cut -d= -f2)
echo ""
echo "Done. Your vault was NOT removed."
if [ -n "$VAULT_DIR" ]; then
  echo "If you want to delete it: rm -rf $VAULT_DIR"
fi
echo "Remove the claude-stow block from ~/.claude/CLAUDE.md manually."
