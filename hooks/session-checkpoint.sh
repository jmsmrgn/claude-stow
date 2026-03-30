#!/usr/bin/env bash
# session-checkpoint.sh — Stop hook: automated vault checkpoint via subprocess
#
# Fires on every Stop event. Finds the most recent session JSONL for the current
# project, extracts conversation content, and launches a background claude -p
# subprocess to write vault updates. Silent — emits nothing to stdout.
#
# The subprocess uses native file tools (Read, Edit, Write, Bash) — no MCP required.
# Skips sessions with fewer than 3 user turns to avoid noise from accidental opens.
# Output from the subprocess is logged to ~/.claude/stow-checkpoint.log.

CONFIG_FILE="$HOME/.claude/stow.conf"

# Load vault config
[[ ! -f "$CONFIG_FILE" ]] && exit 0
# shellcheck source=/dev/null
source "$CONFIG_FILE"
[[ -z "$VAULT_DIR" ]] && exit 0

PROJECT_NAME=$(basename "$PWD")
ENCODED_PATH=$(echo "$PWD" | sed 's|/|-|g')
PROJECTS_DIR="$HOME/.claude/projects/$ENCODED_PATH"

# Find most recent JSONL for this project
JSONL_FILE=$(ls -t "$PROJECTS_DIR"/*.jsonl 2>/dev/null | head -1)
[[ -z "$JSONL_FILE" || ! -f "$JSONL_FILE" ]] && exit 0

# Skip if JSONL hasn't grown since the last checkpoint run
JSONL_HASH=$(echo "$JSONL_FILE" | md5 -q 2>/dev/null || echo "$JSONL_FILE" | md5sum | cut -d' ' -f1)
STATE_FILE="/tmp/stow_ckpt_${JSONL_HASH}.last"
CURRENT_SIZE=$(wc -c < "$JSONL_FILE" | tr -d ' ')
LAST_SIZE=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
[[ "$CURRENT_SIZE" -le "$LAST_SIZE" ]] && exit 0

# Build vault update prompt via Python — handles all string interpolation and
# escaping cleanly. Exits with no output if the session is too short to warrant
# a vault write (< 3 user turns or no extractable content).
PROMPT_FILE=$(mktemp /tmp/stow_prompt_XXXXXX.txt)
LOG_FILE="$HOME/.claude/stow-checkpoint.log"

python3 - "$JSONL_FILE" "$PROJECT_NAME" "$VAULT_DIR" << 'PYEOF' > "$PROMPT_FILE" 2>/dev/null
import json, sys
from datetime import date

jsonl_path, project, vault = sys.argv[1], sys.argv[2], sys.argv[3]
today = date.today().isoformat()

# Parse all entries
entries = []
with open(jsonl_path) as f:
    for line in f:
        try:
            entries.append(json.loads(line.strip()))
        except Exception:
            pass

# Guard: skip trivial sessions
user_turns = sum(1 for e in entries if e.get('type') == 'user')
if user_turns < 3:
    sys.exit(0)

# Extract meaningful conversation text
messages = []
for e in entries:
    t = e.get('type')
    if t not in ('user', 'assistant'):
        continue
    content = e.get('message', {}).get('content', '')
    if isinstance(content, list):
        texts = [
            b['text'].strip()[:400]
            for b in content
            if isinstance(b, dict)
            and b.get('type') == 'text'
            and not b.get('text', '').strip().startswith('<')
            and len(b.get('text', '').strip()) > 20
        ]
        text = ' '.join(texts)
    else:
        text = str(content).strip()
        if text.startswith('<') or len(text) <= 20:
            text = ''
    if text:
        messages.append(f"{'USER' if t == 'user' else 'ASSISTANT'}: {text}")

transcript = '\n\n'.join(messages[-30:])
if not transcript:
    sys.exit(0)

print(f"""You are updating a project memory vault after a Claude Code session. Be concise and accurate.

Project: {project}
Vault: {vault}
Date: {today}

Session transcript (recent exchanges):
{transcript}

---

Complete the following tasks:

1. Read {vault}/Projects/{project}/STATUS.md
   If the file does not exist, create it with this structure:
   ---
   updated: '{today}'
   ---
   ## Current state
   ## Last session
   ## Next steps
   ## Key locations

2. Update STATUS.md:
   - Current state: one sentence on where the project stands now
   - Last session: {today} — one sentence summary of what was accomplished
   - Next steps: brief bullet list of immediate next actions
   Update the frontmatter `updated` field to {today}. Keep STATUS.md under 40 lines.

3. Read {vault}/Projects/{project}/DECISIONS.md
   If any locked decisions emerged this session (architectural choices, rejected approaches,
   naming conventions), append new rows to the decisions table:
   | **{today}** Decision text | One-sentence rationale |
   Skip entirely if no decisions were clearly made and locked.

Write only to files inside {vault}/Projects/{project}/. Do not invent decisions.""")
PYEOF

# Bail if Python produced no prompt (session too short or no content)
if [[ ! -s "$PROMPT_FILE" ]]; then
  rm -f "$PROMPT_FILE"
  exit 0
fi

# Record current size before launching so rapid re-fires are skipped
echo "$CURRENT_SIZE" > "$STATE_FILE"

# Launch vault update as a background subprocess — silent, logs all output
claude -p "$(cat "$PROMPT_FILE")" \
  --tools "Read,Edit,Write,Bash" \
  --permission-mode bypassPermissions \
  --model claude-haiku-4-5-20251001 \
  --no-session-persistence \
  >> "$LOG_FILE" 2>&1 &

rm -f "$PROMPT_FILE"
