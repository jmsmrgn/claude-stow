#!/usr/bin/env bash
# session-checkpoint.sh — Stop hook: rate-limited vault checkpoint
#
# Fires on every Stop event but gates vault writes to once per WRITE_EVERY turns.
# Uses a temp file to track turns since the last write across back-to-back sessions.
# Stdout is injected into Claude's context, so the instruction reaches Claude directly.

WRITE_EVERY=5
COUNT_FILE="/tmp/claude_lore_turn_count"

# Read current count, increment, persist
count=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" > "$COUNT_FILE"

# Only emit instruction at threshold
if [ "$count" -ge "$WRITE_EVERY" ]; then
  echo 0 > "$COUNT_FILE"
  echo "Checkpoint: use the memory-writer agent to update the vault for the current project. Patch STATUS.md with current state and next steps. Add any new locked decisions to DECISIONS.md. Keep it brief — this is a background checkpoint, not a session close."
fi
