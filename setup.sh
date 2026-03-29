#!/usr/bin/env bash

# Resolve the absolute path of this script's directory at runtime
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# STEP 1 — Prompt for install path
# ---------------------------------------------------------------------------

printf 'Where should the vault be installed? [default: ~/claude-lore]: '
read -r input_path

if [ -z "$input_path" ]; then
  input_path="$HOME/claude-lore"
fi

# Expand ~ to absolute path
VAULT_DIR="${input_path/#\~/$HOME}"

# ---------------------------------------------------------------------------
# STEP 2 — Dependency checks
# ---------------------------------------------------------------------------

if ! command -v jq > /dev/null 2>&1; then
  echo ""
  echo "ERROR: jq is required but not installed."
  echo "Install it with: brew install jq"
  exit 1
fi

if ! command -v node > /dev/null 2>&1; then
  echo ""
  echo "ERROR: node is required but not installed."
  echo "Install it with: brew install node"
  exit 1
fi

# ---------------------------------------------------------------------------
# --- mcpvault ---
# ---------------------------------------------------------------------------

if command -v mcpvault > /dev/null 2>&1; then
  echo "mcpvault already installed — skipping."
else
  echo "Installing mcpvault globally via npm..."
  npm install -g @bitbonsai/mcpvault
  if [ $? -ne 0 ]; then
    echo ""
    echo "ERROR: mcpvault installation failed."
    echo "Try running manually: npm install -g @bitbonsai/mcpvault"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# STEP 4 — Create vault directory structure
# ---------------------------------------------------------------------------

SOURCE_VAULT="$SCRIPT_DIR/vault"

if [ ! -d "$SOURCE_VAULT" ]; then
  echo ""
  echo "ERROR: Source vault directory not found at $SOURCE_VAULT"
  echo "Ensure setup.sh is run from the claude-lore repo root or that vault/ exists alongside it."
  exit 1
fi

# Walk source vault and copy files, skipping existing ones
while IFS= read -r -d '' src_file; do
  # Compute relative path from source vault root
  rel_path="${src_file#$SOURCE_VAULT/}"
  dest_file="$VAULT_DIR/$rel_path"
  dest_dir="$(dirname "$dest_file")"

  # Create destination directory if needed
  if [ ! -d "$dest_dir" ]; then
    mkdir -p "$dest_dir"
    if [ $? -ne 0 ]; then
      echo "ERROR: Could not create directory: $dest_dir"
      exit 1
    fi
  fi

  # Skip repo-only files that should never land in the user's vault
  case "$(basename "$src_file")" in
    .gitkeep|.DS_Store) continue ;;
  esac

  if [ -f "$dest_file" ]; then
    echo "Skipping (already exists): $rel_path"
  else
    cp "$src_file" "$dest_file"
    if [ $? -ne 0 ]; then
      echo "ERROR: Could not copy $rel_path to $dest_file"
      exit 1
    fi
    echo "Installed: $rel_path"
  fi
done < <(find "$SOURCE_VAULT" -type f -print0)

# Ensure Projects/ directory exists in the installed vault even with no files
if [ ! -d "$VAULT_DIR/Projects" ]; then
  mkdir -p "$VAULT_DIR/Projects"
fi

# ---------------------------------------------------------------------------
# STEP 5 — Install memory-writer subagent
# ---------------------------------------------------------------------------

AGENTS_DIR="$HOME/.claude/agents"
AGENT_SRC="$SCRIPT_DIR/agents/memory-writer.md"
AGENT_DEST="$AGENTS_DIR/memory-writer.md"

if [ ! -f "$AGENT_SRC" ]; then
  echo "WARNING: agents/memory-writer.md not found in repo — skipping agent install."
else
  if [ ! -d "$AGENTS_DIR" ]; then
    mkdir -p "$AGENTS_DIR"
    if [ $? -ne 0 ]; then
      echo "ERROR: Could not create directory: $AGENTS_DIR"
      exit 1
    fi
  fi

  if [ -f "$AGENT_DEST" ]; then
    echo "Skipping (already exists): ~/.claude/agents/memory-writer.md"
  else
    cp "$AGENT_SRC" "$AGENT_DEST"
    if [ $? -ne 0 ]; then
      echo "ERROR: Could not copy memory-writer.md to $AGENT_DEST"
      exit 1
    fi
    echo "Installed: ~/.claude/agents/memory-writer.md"
  fi
fi

# ---------------------------------------------------------------------------
# STEP 6 — settings.json hook injection
# ---------------------------------------------------------------------------

SETTINGS_FILE="$HOME/.claude/settings.json"
SETTINGS_DIR="$HOME/.claude"
HOOK_COMMAND="$SCRIPT_DIR/hooks/inject-context.sh"
HOOK_STATUS=""

if [ ! -f "$SETTINGS_FILE" ] || [ ! -s "$SETTINGS_FILE" ]; then
  # Case 1/2: file does not exist or is empty
  mkdir -p "$SETTINGS_DIR"
  NEW_CONTENT=$(jq -n \
    --arg cmd "$HOOK_COMMAND" \
    '{
      hooks: {
        SessionStart: [
          {
            matcher: "",
            hooks: [{ type: "command", command: $cmd }]
          }
        ]
      }
    }')
  printf '%s\n' "$NEW_CONTENT" > "$SETTINGS_FILE"
  if [ $? -ne 0 ]; then
    echo "ERROR: Could not write to $SETTINGS_FILE"
    exit 1
  fi
  HOOK_STATUS="injected"
else
  # File exists and has content — validate JSON first
  if ! jq empty "$SETTINGS_FILE" > /dev/null 2>&1; then
    # Case 6: invalid JSON
    echo ""
    echo "WARNING: $SETTINGS_FILE contains invalid JSON. Not modifying."
    echo "Merge the following into $SETTINGS_FILE manually:"
    echo ""
    jq -n \
      --arg cmd "$HOOK_COMMAND" \
      '{
        hooks: {
          SessionStart: [
            {
              matcher: "",
              hooks: [{ type: "command", command: $cmd }]
            }
          ]
        }
      }'
    echo ""
    HOOK_STATUS="manual merge required"
  else
    # Check if our exact hook entry is already present
    ALREADY_PRESENT=$(jq \
      --arg cmd "$HOOK_COMMAND" \
      '[
        .hooks.SessionStart[]?
        | select(.matcher == "")
        | .hooks[]?
        | select(.type == "command" and .command == $cmd)
      ] | length' \
      "$SETTINGS_FILE")

    if [ "$ALREADY_PRESENT" -gt 0 ] 2>/dev/null; then
      # Case 5: already present
      echo "Hook already present — skipping."
      HOOK_STATUS="already present"
    else
      # Backup before modifying
      cp "$SETTINGS_FILE" "${SETTINGS_FILE}.bak"
      if [ $? -ne 0 ]; then
        echo "ERROR: Could not create backup at ${SETTINGS_FILE}.bak"
        exit 1
      fi

      HAS_HOOKS=$(jq 'has("hooks")' "$SETTINGS_FILE")

      if [ "$HAS_HOOKS" = "false" ]; then
        # Case 3: valid JSON, no hooks key
        MERGED=$(jq \
          --arg cmd "$HOOK_COMMAND" \
          '. + {
            hooks: {
              SessionStart: [
                {
                  matcher: "",
                  hooks: [{ type: "command", command: $cmd }]
                }
              ]
            }
          }' \
          "$SETTINGS_FILE")
      else
        # Case 4: valid JSON, has hooks key, entry not present
        HAS_SESSION_START=$(jq '.hooks | has("SessionStart")' "$SETTINGS_FILE")

        if [ "$HAS_SESSION_START" = "false" ]; then
          MERGED=$(jq \
            --arg cmd "$HOOK_COMMAND" \
            '.hooks.SessionStart = [
              {
                matcher: "",
                hooks: [{ type: "command", command: $cmd }]
              }
            ]' \
            "$SETTINGS_FILE")
        else
          MERGED=$(jq \
            --arg cmd "$HOOK_COMMAND" \
            '.hooks.SessionStart += [
              {
                matcher: "",
                hooks: [{ type: "command", command: $cmd }]
              }
            ]' \
            "$SETTINGS_FILE")
        fi
      fi

      printf '%s\n' "$MERGED" > "$SETTINGS_FILE"
      if [ $? -ne 0 ]; then
        echo "ERROR: Could not write merged settings to $SETTINGS_FILE"
        echo "Your original settings are backed up at ${SETTINGS_FILE}.bak"
        exit 1
      fi
      HOOK_STATUS="injected"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# STEP 7 — Post-install output
# ---------------------------------------------------------------------------

echo ""
echo "Vault installed at: $VAULT_DIR"
echo "Hook status: $HOOK_STATUS"
echo ""
echo "------------------------------------------------------------"
echo "Add the following block to ~/.claude/CLAUDE.md"
echo "------------------------------------------------------------"
cat <<CLAUDEMD

## Vault & Project Context

Vault is at $VAULT_DIR via MCPVault (obsidian MCP server).

Structure:

- Global/CONTEXT.md — identity, cross-project constraints, active projects
- Projects/{project}/STATUS.md — current state, last session, next steps
- Projects/{project}/CONTEXT.md — full technical context, load on demand
- Projects/{project}/DECISIONS.md — locked decisions, search on demand

At the start of any project session: read Projects/{project}/STATUS.md and
Global/CONTEXT.md unless already provided in context. Do not load CONTEXT.md
or DECISIONS.md unless the task requires them.

At the end of any session, without being asked:

1. List every decision made this session in one sentence each
2. List every assumption validated or invalidated
3. Patch STATUS.md with current state and next steps
4. Patch DECISIONS.md with any new locked decisions
5. Flag immediately if any session decision contradicts a locked prior decision

Never re-suggest anything listed in any DECISIONS.md graveyard section.

CLAUDEMD
echo "------------------------------------------------------------"
echo ""
echo "Open $VAULT_DIR/Global/CONTEXT.md and fill in your identity and project context. Then start a Claude Code session."
