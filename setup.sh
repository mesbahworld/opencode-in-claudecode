#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup.sh — installer for OpenCode-in-ClaudeCode (macOS + Linux).
#
# What it does:
#   1. Checks for prerequisites: claude (Claude Code CLI), node, jq.
#   2. Copies oc-proxy.js to ~/.claude/oc-proxy.js.
#   3. Creates ~/.claude/claude-oc.env from .env (or .env.example) — never overwrites.
#   4. Installs claude-oc.sh to ~/.claude/claude-oc.sh.
#   5. Adds a one-line `source` to your shell rc (~/.zshrc or ~/.bashrc), idempotently.
#
# Usage:  ./setup.sh            # interactive (prompts for missing .env values)
#         ./setup.sh --non-interactive   # skip prompts; fail on missing values
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

INTERACTIVE=1
[ "${1:-}" = "--non-interactive" ] && INTERACTIVE=0

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

# ── prerequisite checks ───────────────────────────────────────────────────────

check() {
  local cmd="$1" label="$2" hint="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf "  ✓  %-10s %s\n" "$cmd" "$(command -v "$cmd")"
  else
    printf "  ✗  %-10s MISSING\n" "$label"
    printf "     install: %s\n" "$hint"
    if [ "$INTERACTIVE" = "1" ]; then
      read -r -p "     continue anyway? [y/N] " ans
      [ "${ans:-}" = "y" ] || exit 1
    else
      exit 1
    fi
  fi
}

echo "Checking prerequisites…"
check claude "claude"  "npm i -g @anthropic-ai/claude-code"
check node   "node"    "https://nodejs.org  (or: brew install node / sudo dnf install nodejs)"
check jq     "jq"      "brew install jq  |  sudo dnf install jq  |  sudo apt install jq"

# ── 1. install oc-proxy.js ───────────────────────────────────────────────────

echo
echo "Installing oc-proxy.js → $CLAUDE_DIR/oc-proxy.js"
cp -f "$HERE/oc-proxy.js" "$CLAUDE_DIR/oc-proxy.js"
chmod +x "$CLAUDE_DIR/oc-proxy.js"

# ── 2. configure env ─────────────────────────────────────────────────────────

ENV_DST="$CLAUDE_DIR/claude-oc.env"

# Pick a source .env: prefer a local .env (user-filled), fall back to .env.example.
ENV_SRC="$HERE/.env"
[ -f "$ENV_SRC" ] || ENV_SRC="$HERE/.env.example"

if [ ! -f "$ENV_DST" ]; then
  echo "Installing env → $ENV_DST  (from $ENV_SRC)"
  cp "$ENV_SRC" "$ENV_DST"
  chmod 600 "$ENV_DST"
else
  echo "Env already exists at $ENV_DST — leaving in place (edit it manually to change)."
fi

# Prompt for the critical values if empty (interactive only).
prompt_if_empty() {
  local var="$1" label="$2"
  local cur; cur=$(grep -E "^${var}=" "$ENV_DST" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true)
  cur="${cur# }"; cur="${cur% }"
  if [ -z "$cur" ] && [ "$INTERACTIVE" = "1" ]; then
    read -r -p "  $label: " val
    if [ -n "$val" ]; then
      # update or append
      if grep -qE "^${var}=" "$ENV_DST"; then
        # in-place update (portable sed)
        sed -i.bak "s|^${var}=.*|${var}=\"${val}\"|" "$ENV_DST"
      else
        printf '%s="%s"\n' "$var" "$val" >> "$ENV_DST"
      fi
      rm -f "$ENV_DST.bak"
    fi
  fi
}

if [ "$INTERACTIVE" = "1" ]; then
  echo
  echo "Key values (leave blank to skip / keep example):"
  prompt_if_empty OPENCODE_GO_KEY   "OpenCode Go API key  (https://opencode.ai/auth)"
  prompt_if_empty LITELLM_API_KEY   "LiteLLM API key      (blank if no auth)"
  prompt_if_empty LITELLM_BASE_URL  "LiteLLM base URL     (e.g. https://llm.mesbahuddin.com)"
fi

echo
echo "Env file:  $ENV_DST   (edit anytime)"

# ── 3. install functions ──────────────────────────────────────────────────────

FN_DST="$CLAUDE_DIR/claude-oc.sh"
echo "Installing functions → $FN_DST"
cp -f "$HERE/claude-oc.sh" "$FN_DST"

# ── 4. inject into shell rc ──────────────────────────────────────────────────

# Pick the rc file: zsh if present, else bash.
RC=""
if [ -n "${ZDOTDIR:-}" ] && [ -f "$ZDOTDIR/.zshrc" ]; then
  RC="$ZDOTDIR/.zshrc"
elif [ -f "$HOME/.zshrc" ]; then
  RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
  RC="$HOME/.bashrc"
fi

MARKER="# >>> claude-oc (opencode-in-claudecode) >>>"
MARKER_END="# <<< claude-oc <<<"

if [ -z "$RC" ]; then
  echo
  echo "No ~/.zshrc or ~/.bashrc found. Add this line to your shell init manually:"
  echo "  . \"$FN_DST\""
else
  if grep -qF "$MARKER" "$RC" 2>/dev/null; then
    echo "Source line already present in $RC — refreshing block…"
    # remove the old block
    sed -i.bak "/$MARKER/,/$MARKER_END/d" "$RC" || true
    rm -f "$RC.bak"
  fi
  {
    echo ""
    echo "$MARKER"
    echo ". \"$FN_DST\""
    echo "$MARKER_END"
  } >> "$RC"
  echo "Source line added to $RC."
fi

# ── done ─────────────────────────────────────────────────────────────────────

echo
echo "Done. Restart your terminal (or run:  source \"$FN_DST\")"
echo
echo "Commands available:"
echo "  claude-oc               Claude Code via opencode-go Anthropic endpoint (MiniMax M3 / Qwen)"
echo "  claude-oc-init          pin current project to opencode-go (for VS Code)"
echo "  claude-px               Claude Code via local proxy (GLM / Kimi / DeepSeek)"
echo "  px / px-stop            start / stop the local proxy"
echo "  claude-px-init          pin current project to proxy (for VS Code)"
echo "  claude-litellm          Claude Code via your LiteLLM gateway"
echo "  claude-litellm-init     pin current project to LiteLLM (for VS Code)"
echo "  claude-oc-revert        unpin current project (restores default Claude subscription)"