# shellcheck shell=bash
# ─────────────────────────────────────────────────────────────────────────────
# claude-oc functions — OpenCode Go + LiteLLM for Claude Code.
# Sourced by .zshrc / .bashrc via the installer. Do NOT execute directly.
# Config is read from $CLAUDE_OC_ENV (default ~/.claude/claude-oc.env).
# ─────────────────────────────────────────────────────────────────────────────

# Locate and load the env file once per shell.
_claude_oc_load_env() {
  if [ -n "${CLAUDE_OC_LOADED:-}" ]; then return 0; fi
  local f="${CLAUDE_OC_ENV:-$HOME/.claude/claude-oc.env}"
  if [ -f "$f" ]; then
    while IFS='=' read -r k v; do
      case "$k" in
        ''|\#*) continue ;;
      esac
      # strip leading/trailing whitespace from value, keep the rest verbatim
      v="${v#"${v%%[![:space:]]*}"}"
      v="${v%"${v##*[![:space:]]}"}"
      # strip surrounding double quotes if present
      v="${v#\"}"; v="${v%\"}"
      export "$k=$v"
    done < "$f"
  fi
  export CLAUDE_OC_LOADED=1
}
_claude_oc_load_env

# ── helpers ──────────────────────────────────────────────────────────────────

# Merge .env keys for a given provider into .claude/settings.local.json (preserves MCPservers etc).
# Usage: _claude_oc_pin <BASE_URL> <API_KEY> <AUTH_TOKEN> <OPUS_MODEL> <OPUS_NAME> <SONNET_MODEL> <SONNET_NAME> <HAIKU_MODEL> <HAIKU_NAME> <SUBAGENT_MODEL>
_claude_oc_pin() {
  mkdir -p .claude
  local f=".claude/settings.local.json"
  local base='{}'
  if [ -f "$f" ] && jq empty "$f" 2>/dev/null; then base=$(cat "$f"); fi
  echo "$base" | jq \
    --arg base_url "$1" --arg api_key "$2" --arg auth_token "$3" \
    --arg opus "$4" --arg opus_name "$5" \
    --arg sonnet "$6" --arg sonnet_name "$7" \
    --arg haiku "$8" --arg haiku_name "$9" \
    --arg sub "${10}" \
    '.env = ((.env // {}) + {
      "ANTHROPIC_BASE_URL": $base_url,
      "ANTHROPIC_AUTH_TOKEN": $auth_token,
      "ANTHROPIC_API_KEY": $api_key,
      "ANTHROPIC_DEFAULT_OPUS_MODEL": $opus,
      "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME": $opus_name,
      "ANTHROPIC_DEFAULT_SONNET_MODEL": $sonnet,
      "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": $sonnet_name,
      "ANTHROPIC_DEFAULT_HAIKU_MODEL": $haiku,
      "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME": $haiku_name,
      "CLAUDE_CODE_SUBAGENT_MODEL": $sub
    })' > "$f.tmp" && mv "$f.tmp" "$f"
}

# Remove the opencode env vars from .claude/settings.local.json (shared revert).
_claude_oc_unpin() {
  local f=".claude/settings.local.json"
  if [ ! -f "$f" ]; then
    echo "Nothing to revert — no .claude/settings.local.json in $(pwd)."
    return 0
  fi
  if ! jq empty "$f" 2>/dev/null; then
    echo "$f is not valid JSON — skipping."
    return 1
  fi
  jq 'del(.env.ANTHROPIC_BASE_URL, .env.ANTHROPIC_AUTH_TOKEN, .env.ANTHROPIC_API_KEY,
         .env.ANTHROPIC_DEFAULT_OPUS_MODEL, .env.ANTHROPIC_DEFAULT_OPUS_MODEL_NAME,
         .env.ANTHROPIC_DEFAULT_SONNET_MODEL, .env.ANTHROPIC_DEFAULT_SONNET_MODEL_NAME,
         .env.ANTHROPIC_DEFAULT_HAIKU_MODEL, .env.ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME,
         .env.CLAUDE_CODE_SUBAGENT_MODEL)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  echo "Reverted $(pwd) to your default Claude subscription. Reload VS Code (Developer: Reload Window)."
}

# ── claude-oc: OpenCode Go via Anthropic endpoint (direct, no proxy) ──────────
claude-oc() {
  ANTHROPIC_BASE_URL="${OPENCODE_GO_BASE_URL}" \
  ANTHROPIC_AUTH_TOKEN="" \
  ANTHROPIC_API_KEY="${OPENCODE_GO_KEY}" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="${OPUS:-$OC_OPUS_MODEL}" \
  ANTHROPIC_DEFAULT_OPUS_MODEL_NAME="${OPUS_NAME:-$OC_OPUS_NAME}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="${SONNET:-$OC_SONNET_MODEL}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL_NAME="${SONNET_NAME:-$OC_SONNET_NAME}" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="${HAIKU:-$OC_HAIKU_MODEL}" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME="${HAIKU_NAME:-$OC_HAIKU_NAME}" \
  CLAUDE_CODE_SUBAGENT_MODEL="${SUBAGENT:-$OC_SUBAGENT_MODEL}" \
  claude "$@"
}

claude-oc-init() {
  _claude_oc_pin \
    "${OPENCODE_GO_BASE_URL}" "${OPENCODE_GO_KEY}" "" \
    "${OPUS:-$OC_OPUS_MODEL}" "${OPUS_NAME:-$OC_OPUS_NAME}" \
    "${SONNET:-$OC_SONNET_MODEL}" "${SONNET_NAME:-$OC_SONNET_NAME}" \
    "${HAIKU:-$OC_HAIKU_MODEL}" "${HAIKU_NAME:-$OC_HAIKU_NAME}" \
    "${SUBAGENT:-$OC_SUBAGENT_MODEL}"
  echo "Pinned $(pwd): ${OPUS_NAME:-$OC_OPUS_NAME} (opencode-go, direct). Existing settings preserved. Reload VS Code."
}

# ── claude-px: OpenCode Go via local proxy (OpenAI-endpoint models) ───────────
PX_PORT="${PX_PORT:-8322}"

px() {
  if lsof -ti :"$PX_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Proxy already running on port $PX_PORT."
    return 0
  fi
  if [ ! -f "$HOME/.claude/oc-proxy.js" ]; then
    echo "oc-proxy.js not found at ~/.claude/oc-proxy.js — run the installer."
    return 1
  fi
  PX_PORT="$PX_PORT" \
  PX_UPSTREAM_BASE_URL="${OPENCODE_GO_BASE_URL}" \
  PX_UPSTREAM_API_KEY="${OPENCODE_GO_KEY}" \
  node "$HOME/.claude/oc-proxy.js" >/tmp/oc-proxy.log 2>&1 &
  sleep 1
  if lsof -ti :"$PX_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Proxy started on http://127.0.0.1:$PX_PORT (PID $!)."
  else
    echo "Failed to start proxy. Check /tmp/oc-proxy.log"; return 1
  fi
}

px-stop() {
  local pid; pid=$(lsof -ti :"$PX_PORT" -sTCP:LISTEN 2>/dev/null)
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null; echo "Proxy stopped (PID $pid)."
  else echo "Proxy not running."; fi
}

claude-px() {
  px || return 1
  ANTHROPIC_BASE_URL="http://127.0.0.1:$PX_PORT" \
  ANTHROPIC_AUTH_TOKEN="" \
  ANTHROPIC_API_KEY="${OPENCODE_GO_KEY}" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="${OPUS:-$PX_OPUS_MODEL}" \
  ANTHROPIC_DEFAULT_OPUS_MODEL_NAME="${OPUS_NAME:-$PX_OPUS_NAME}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="${SONNET:-$PX_SONNET_MODEL}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL_NAME="${SONNET_NAME:-$PX_SONNET_NAME}" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="${HAIKU:-$PX_HAIKU_MODEL}" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME="${HAIKU_NAME:-$PX_HAIKU_NAME}" \
  CLAUDE_CODE_SUBAGENT_MODEL="${SUBAGENT:-$PX_SUBAGENT_MODEL}" \
  claude "$@"
}

claude-px-init() {
  _claude_oc_pin \
    "http://127.0.0.1:$PX_PORT" "${OPENCODE_GO_KEY}" "" \
    "${OPUS:-$PX_OPUS_MODEL}" "${OPUS_NAME:-$PX_OPUS_NAME}" \
    "${SONNET:-$PX_SONNET_MODEL}" "${SONNET_NAME:-$PX_SONNET_NAME}" \
    "${HAIKU:-$PX_HAIKU_MODEL}" "${HAIKU_NAME:-$PX_HAIKU_NAME}" \
    "${SUBAGENT:-$PX_SUBAGENT_MODEL}"
  echo "Pinned $(pwd): ${OPUS_NAME:-$PX_OPUS_NAME} via local proxy. Run 'px' in a terminal first (for VS Code). Reload VS Code."
}

# ── claude-litellm: your LiteLLM gateway ──────────────────────────────────────
# LiteLLM speaks the Anthropic /v1/messages endpoint directly, so no proxy needed.
# If your gateway only speaks OpenAI /chat/completions, set LITELLM_USE_PROXY=1
# and `claude-litellm` will route through the local oc-proxy instead.
claude-litellm() {
  if [ "${LITELLM_USE_PROXY:-0}" = "1" ]; then
    px || return 1
    local url="http://127.0.0.1:$PX_PORT"
    PX_UPSTREAM_BASE_URL="${LITELLM_BASE_URL}" PX_UPSTREAM_API_KEY="${LITELLM_API_KEY}" px 2>/dev/null
  else
    local url="${LITELLM_BASE_URL}"
  fi
  ANTHROPIC_BASE_URL="$url" \
  ANTHROPIC_AUTH_TOKEN="" \
  ANTHROPIC_API_KEY="${LITELLM_API_KEY}" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="${OPUS:-$LITELLM_OPUS_MODEL}" \
  ANTHROPIC_DEFAULT_OPUS_MODEL_NAME="${OPUS_NAME:-$LITELLM_OPUS_NAME}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="${SONNET:-$LITELLM_SONNET_MODEL}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL_NAME="${SONNET_NAME:-$LITELLM_SONNET_NAME}" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="${HAIKU:-$LITELLM_HAIKU_MODEL}" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME="${HAIKU_NAME:-$LITELLM_HAIKU_NAME}" \
  CLAUDE_CODE_SUBAGENT_MODEL="${SUBAGENT:-$LITELLM_SUBAGENT_MODEL}" \
  claude "$@"
}

claude-litellm-init() {
  local url="${LITELLM_BASE_URL}"
  if [ "${LITELLM_USE_PROXY:-0}" = "1" ]; then url="http://127.0.0.1:$PX_PORT"; fi
  _claude_oc_pin \
    "$url" "${LITELLM_API_KEY}" "" \
    "${OPUS:-$LITELLM_OPUS_MODEL}" "${OPUS_NAME:-$LITELLM_OPUS_NAME}" \
    "${SONNET:-$LITELLM_SONNET_MODEL}" "${SONNET_NAME:-$LITELLM_SONNET_NAME}" \
    "${HAIKU:-$LITELLM_HAIKU_MODEL}" "${HAIKU_NAME:-$LITELLM_HAIKU_NAME}" \
    "${SUBAGENT:-$LITELLM_SUBAGENT_MODEL}"
  echo "Pinned $(pwd): ${OPUS_NAME:-$LITELLM_OPUS_NAME} (LiteLLM). Existing settings preserved. Reload VS Code."
}

# Shared revert for any of the three providers.
claude-oc-revert() { _claude_oc_unpin; }
claude-px-revert() { _claude_oc_unpin; }
claude-litellm-revert() { _claude_oc_unpin; }