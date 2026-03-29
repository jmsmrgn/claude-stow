#!/usr/bin/env bash
# status.sh — post-install verification for claude-lore
# Run at any time to confirm the system is wired correctly.

CONFIG_FILE="$HOME/.claude/lore.conf"
SETTINGS_FILE="$HOME/.claude/settings.json"
AGENT_FILE="$HOME/.claude/agents/memory-writer.md"

# Resolve vault path the same way inject-context.sh does:
# read from lore.conf, fall back to ~/claude-lore
VAULT_DIR=""
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi
if [[ -z "$VAULT_DIR" ]]; then
  VAULT_DIR="$HOME/claude-lore"
fi

echo "claude-lore status"
echo "------------------"

# 1. Vault directory
if [[ -d "$VAULT_DIR" ]]; then
  printf "%-16s%s [found]\n" "Vault:" "$VAULT_DIR"
else
  printf "%-16s%s [NOT FOUND]\n" "Vault:" "$VAULT_DIR"
  echo "  -> Run setup.sh to create the vault, or update VAULT_DIR in ~/.claude/lore.conf  (see README: Install)"
fi

# 2. Global/CONTEXT.md
CONTEXT_FILE="$VAULT_DIR/Global/CONTEXT.md"
if [[ -f "$CONTEXT_FILE" ]]; then
  if stat --version > /dev/null 2>&1; then
    # GNU stat (Linux)
    mtime=$(stat --format="%y" "$CONTEXT_FILE" | cut -d' ' -f1)
  else
    # BSD stat (macOS)
    mtime=$(stat -f "%Sm" -t "%Y-%m-%d" "$CONTEXT_FILE")
  fi
  printf "%-16s%s\n" "CONTEXT.md:" "last modified $mtime"
else
  printf "%-16s%s\n" "CONTEXT.md:" "NOT FOUND"
  echo "  -> Create $CONTEXT_FILE and fill in your identity and stack  (see README: Vault structure)"
fi

# 3. SessionStart hook
HOOK_FOUND=0
if [[ -f "$SETTINGS_FILE" ]] && command -v jq > /dev/null 2>&1; then
  HOOK_CMD=$(jq -r '[.hooks.SessionStart[]? | .hooks[]? | select(.type == "command") | .command] | first // ""' "$SETTINGS_FILE" 2>/dev/null)
  if echo "$HOOK_CMD" | grep -q "inject-context.sh"; then
    HOOK_FOUND=1
  fi
fi
if [[ "$HOOK_FOUND" -eq 1 ]]; then
  printf "%-16s%s\n" "SessionStart:" "wired [inject-context.sh]"
else
  printf "%-16s%s\n" "SessionStart:" "NOT FOUND"
  echo "  -> Run setup.sh to inject the hook into ~/.claude/settings.json  (see README: How it works)"
fi

# 4. memory-writer agent
if [[ -f "$AGENT_FILE" ]]; then
  printf "%-16s%s\n" "memory-writer:" "installed"
else
  printf "%-16s%s\n" "memory-writer:" "NOT FOUND"
  echo "  -> Run setup.sh, or copy agents/memory-writer.md to ~/.claude/agents/  (see README: How vault updates happen)"
fi

# 5. MCPVault
if command -v mcpvault > /dev/null 2>&1; then
  version=$(mcpvault --version 2>/dev/null || mcpvault -v 2>/dev/null || echo "installed")
  printf "%-16s%s\n" "MCPVault:" "$version"
else
  printf "%-16s%s\n" "MCPVault:" "NOT FOUND"
  echo "  -> Run: npm install -g @bitbonsai/mcpvault  (see README: Install)"
fi
