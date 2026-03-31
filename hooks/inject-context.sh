#!/usr/bin/env bash
# inject-context.sh — SessionStart hook: inject vault context into Claude Code sessions
#
# Reads vault path from ~/.claude/stow.conf (written by setup.sh).
# Outputs Global/CONTEXT.md and Projects/{cwd-name}/STATUS.md to stdout,
# which Claude Code injects as session context.

CONFIG_FILE="$HOME/.claude/stow.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "# claude-stow: vault context not loaded"
  echo "stow.conf not found at $CONFIG_FILE — re-run setup.sh to fix."
  exit 0
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

if [[ -z "$VAULT_DIR" ]]; then
  echo "# claude-stow: vault context not loaded"
  echo "VAULT_DIR is not set in $CONFIG_FILE — re-run setup.sh to fix."
  exit 0
fi

if [[ ! -d "$VAULT_DIR" ]]; then
  echo "# claude-stow: vault context not loaded"
  echo "Vault directory not found: $VAULT_DIR — update VAULT_DIR in $CONFIG_FILE."
  exit 0
fi

PROJECT_NAME=$(basename "$PWD")
# Allow per-repo override: add PROJECT_NAME=my-name to a .stow file in the repo root.
# Useful when two repos share the same directory name and would otherwise collide in the vault.
if [[ -f "$PWD/.stow" ]]; then
  _override=$(grep -m1 '^PROJECT_NAME=' "$PWD/.stow" | cut -d= -f2-)
  if [[ -n "$_override" ]]; then
    if [[ "$_override" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      PROJECT_NAME="$_override"
    else
      echo "[stow] Invalid PROJECT_NAME in .stow (only alphanumeric, hyphen, underscore allowed): $_override" >&2
    fi
  fi
fi
output=""

if [[ -f "$VAULT_DIR/Global/CONTEXT.md" ]]; then
  output+="## Global Context"$'\n\n'
  output+="$(cat "$VAULT_DIR/Global/CONTEXT.md")"$'\n\n'
else
  output+="# claude-stow: Global/CONTEXT.md not found in vault at $VAULT_DIR"$'\n\n'
fi

if [[ -f "$VAULT_DIR/Projects/$PROJECT_NAME/STATUS.md" ]]; then
  output+="## Project Status: $PROJECT_NAME"$'\n\n'
  output+="$(cat "$VAULT_DIR/Projects/$PROJECT_NAME/STATUS.md")"$'\n\n'
fi

if [[ -n "$output" ]]; then
  printf '# Vault context — loaded at session start\n\n%s' "$output"
fi
