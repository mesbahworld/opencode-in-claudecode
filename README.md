# opencode-in-claudecode

Use open coding models (OpenCode Go: GLM 5.2, Kimi, MiniMax, Qwen, DeepSeek, MiMo) and your own LiteLLM gateway from inside the **Claude Code** CLI and VS Code plugin — side-by-side with your regular Anthropic subscription.

Three providers, one consistent interface:

| Provider | Command | How | Models |
|---|---|---|---|
| OpenCode Go — Anthropic endpoint | `claude-oc` | direct (no proxy) | MiniMax M3, Qwen 3.7 |
| OpenCode Go — OpenAI endpoint | `claude-px` | local proxy (`oc-proxy.js`) | GLM 5.2, Kimi, DeepSeek, MiMo |
| Your LiteLLM gateway | `claude-litellm` | direct (or via proxy if needed) | any model in your `litellm-config.yaml` |

`claude` (with no suffix) is **unchanged** — it still uses your Anthropic subscription. All provider vars are scoped per-command, never exported globally.

## Quick start

```bash
git clone git@github.com:mesbahworld/opencode-in-claudecode.git
cd opencode-in-claudecode
cp .env.example .env        # edit .env: set OPENCODE_GO_KEY, LITELLM_BASE_URL, etc.
./setup.sh                  # macOS / Linux  (or setup.ps1 on Windows)
```

Then open a new terminal (or `source ~/.claude/claude-oc.sh`):

```bash
claude-oc               # Claude Code on opencode-go (MiniMax M3 / Qwen)
claude-px                # Claude Code on GLM 5.2 / Kimi / DeepSeek (auto-starts proxy)
claude-litellm           # Claude Code on your LiteLLM gateway
claude                   # unchanged — your Anthropic subscription
```

## Commands

### Per-session (CLI — affects this terminal only)

| Command | Description |
|---|---|
| `claude-oc` | Claude Code → opencode-go Anthropic endpoint (MiniMax M3 / Qwen). |
| `claude-px` | Claude Code → local proxy → opencode-go OpenAI endpoint (GLM 5.2 / Kimi / DeepSeek). Auto-starts the proxy. |
| `claude-litellm` | Claude Code → your LiteLLM gateway. |
| `px` | Start the proxy manually (needed for VS Code). |
| `px-stop` | Stop the proxy. |
| `claude` | Your Anthropic subscription — untouched. |

Inline overrides (any provider): `OPUS=qwen3.7-max claude-oc`, `OPUS=kimi-k2.7-code claude-px`, `SONNET=groq/llama-3.3-70b-versatile claude-litellm`.

### Per-project (VS Code plugin + terminal in that directory)

| Command | Description |
|---|---|
| `claude-oc-init` | Pin the current project to opencode-go (Anthropic endpoint). |
| `claude-px-init` | Pin the current project to the proxy. Run `px` in a terminal first. |
| `claude-litellm-init` | Pin the current project to LiteLLM. |
| `claude-oc-revert` | Unpin the current project (works for any of the three). |

The `-init` commands **merge** into `.claude/settings.local.json` with `jq`/`ConvertTo-Json`, preserving `enabledMcpjsonServers`, `allowedTools`, and any other existing keys.

After `-init`, reload the VS Code window: **Cmd/Ctrl+Shift+P → Developer: Reload Window**.

## Configuration (`.env`)

All dynamic values live in `.env` (copied to `~/.claude/claude-oc.env`). The installer never overwrites an existing env file — edit it directly to change models/keys.

Key variables:

```ini
OPENCODE_GO_KEY=sk-...              # https://opencode.ai/auth
OPENCODE_GO_BASE_URL=https://opencode.ai/zen/go

OC_OPUS_MODEL=minimax-m3            # Anthropic-endpoint models for claude-oc
OC_SONNET_MODEL=qwen3.7-max
OC_HAIKU_MODEL=minimax-m3

PX_OPUS_MODEL=glm-5.2               # OpenAI-endpoint models for claude-px
PX_SONNET_MODEL=glm-5.2
PX_HAIKU_MODEL=glm-5.2
PX_PORT=8322

LITELLM_BASE_URL=https://llm.mesbahuddin.com
LITELLM_API_KEY=                     # blank if your gateway has no auth
LITELLM_OPUS_MODEL=opencode-go/glm-5.2
LITELLM_SONNET_MODEL=opencode-go/minimax-m3
LITELLM_HAIKU_MODEL=groq/llama-3.3-70b-versatile
LITELLM_USE_PROXY=0                 # set to 1 if your LiteLLM only speaks OpenAI /chat/completions
```

## How it works

Claude Code only speaks the **Anthropic `/v1/messages`** protocol (streaming SSE). opencode-go serves some models (MiniMax, Qwen) on that endpoint — those work directly via `claude-oc`. Other models (GLM 5.2, Kimi, DeepSeek, MiMo) are only on opencode's **OpenAI `/v1/chat/completions`** endpoint, which Claude Code can't call.

`oc-proxy.js` bridges that gap with **real-time streaming**: it converts the Anthropic request to OpenAI, streams the OpenAI SSE back, and re-emits proper Anthropic SSE chunks (`message_start` → `content_block_delta` → `message_stop`) as tokens arrive — so tools (Bash, Read, Edit, etc.) work and text appears incrementally.

LiteLLM speaks the Anthropic endpoint natively (when configured with `litellm --anthropic`), so `claude-litellm` works direct. If your LiteLLM instance only speaks OpenAI, set `LITELLM_USE_PROXY=1` to route through `oc-proxy.js`.

## Prerequisites

Install before running `setup.sh` / `setup.ps1`:

- **Claude Code CLI** — `npm i -g @anthropic-ai/claude-code`
- **Node.js 18+** — for the proxy (`claude-px`)
- **jq** — for merging project settings (Claude Code itself uses it too)

| OS | Install |
|---|---|
| macOS | `brew install node jq` |
| Linux (dnf/RHEL) | `sudo dnf install nodejs jq` |
| Linux (apt/Debian) | `sudo apt install nodejs jq` |
| Windows | `winget install OpenJS.NodeJS jqlang.jq` |

## Uninstall

Remove the `# >>> claude-oc` … `# <<< claude-oc <<<` block from your `~/.zshrc` (or `~/.bashrc` / PowerShell profile), then delete `~/.claude/oc-proxy.js`, `~/.claude/claude-oc.sh`, `~/.claude/claude-oc.ps1`, and `~/.claude/claude-oc.env`.

## Files

| File | Purpose |
|---|---|
| `.env.example` | Template — copy to `.env` and fill in. |
| `oc-proxy.js` | The Anthropic↔OpenAI streaming proxy (Node.js, no deps). |
| `claude-oc.sh` | Shell functions for zsh/bash (macOS, Linux). |
| `claude-oc.ps1` | PowerShell functions (Windows). |
| `setup.sh` | Installer for macOS / Linux. |
| `setup.ps1` | Installer for Windows. |