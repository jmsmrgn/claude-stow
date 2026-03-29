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
# STEP 5 — settings.json hook injection
# ---------------------------------------------------------------------------

SETTINGS_FILE="$HOME/.claude/settings.json"
SETTINGS_DIR="$HOME/.claude"
HOOK_COMMAND="$SCRIPT_DIR/hooks/inject-context.sh"
HOOK_STATUS=""

# Build the hook entry JSON with the resolved absolute path
HOOK_ENTRY=$(jq -n \
  --arg cmd "$HOOK_COMMAND" \
  '{
    matcher: "Task",
    hooks: [{ type: "command", command: $cmd }]
  }')

if [ ! -f "$SETTINGS_FILE" ] || [ ! -s "$SETTINGS_FILE" ]; then
  # Case 1/2: file does not exist or is empty
  mkdir -p "$SETTINGS_DIR"
  NEW_CONTENT=$(jq -n \
    --arg cmd "$HOOK_COMMAND" \
    '{
      hooks: {
        PostToolUse: [
          {
            matcher: "Task",
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
          PostToolUse: [
            {
              matcher: "Task",
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
        .hooks.PostToolUse[]?
        | select(.matcher == "Task")
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
              PostToolUse: [
                {
                  matcher: "Task",
                  hooks: [{ type: "command", command: $cmd }]
                }
              ]
            }
          }' \
          "$SETTINGS_FILE")
      else
        # Case 4: valid JSON, has hooks key, entry not present
        HAS_POST_TOOL_USE=$(jq '.hooks | has("PostToolUse")' "$SETTINGS_FILE")

        if [ "$HAS_POST_TOOL_USE" = "false" ]; then
          MERGED=$(jq \
            --arg cmd "$HOOK_COMMAND" \
            '.hooks.PostToolUse = [
              {
                matcher: "Task",
                hooks: [{ type: "command", command: $cmd }]
              }
            ]' \
            "$SETTINGS_FILE")
        else
          MERGED=$(jq \
            --arg cmd "$HOOK_COMMAND" \
            '.hooks.PostToolUse += [
              {
                matcher: "Task",
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
# STEP 6 — Post-install output
# ---------------------------------------------------------------------------

echo ""
echo "Vault installed at: $VAULT_DIR"
echo "Hook status: $HOOK_STATUS"
echo ""
echo "Open Global/CONTEXT.md and fill in your identity and project context. Then start a Claude Code session."
