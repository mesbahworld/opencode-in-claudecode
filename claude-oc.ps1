# ─────────────────────────────────────────────────────────────────────────────
# claude-oc.ps1 — PowerShell functions for OpenCode-in-ClaudeCode.
# Dot-sourced by your PowerShell profile via setup.ps1.
# Config is read from $ClaudeOcEnv (default $HOME\.claude\claude-oc.env).
# ─────────────────────────────────────────────────────────────────────────────

if (-not $script:ClaudeOcEnv) { $script:ClaudeOcEnv = Join-Path $HOME ".claude\claude-oc.env" }
if (-not $script:ClaudeOcProxy) { $script:ClaudeOcProxy = Join-Path $HOME ".claude\oc-proxy.js" }
$script:PxFront = "127.0.0.1"

# Load env file into $script:Cfg.
function _claude_oc_LoadEnv {
  if (-not (Test-Path $script:ClaudeOcEnv)) { return }
  $script:Cfg = @{}
  foreach ($line in Get-Content $script:ClaudeOcEnv) {
    if ($line -match "^\s*#|^\s*$") { continue }
    if ($line -match "^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$") {
      $k = $Matches[1]; $v = $Matches[2].Trim().Trim('"')
      $script:Cfg[$k] = $v
    }
  }
}
_claude_oc_LoadEnv

# ── helpers ──────────────────────────────────────────────────────────────────

# Read a config value with a per-call override + fallback.
function _claude_oc_Get([string]$Key, [string]$Override) {
  if ($Override) { return $Override }
  if ($script:Cfg.ContainsKey($Key)) { return $script:Cfg[$Key] }
  return ""
}

# Merge the provider env block into .\.claude\settings.local.json (preserves MCP etc).
function _claude_oc_Pin {
  param(
    [string]$BaseUrl, [string]$ApiKey, [string]$AuthToken,
    [string]$Opus, [string]$OpusName,
    [string]$Sonnet, [string]$SonnetName,
    [string]$Haiku, [string]$HaikuName,
    [string]$Sub
  )
  $dotClaude = Join-Path (Get-Location) ".claude"
  if (-not (Test-Path $dotClaude)) { New-Item -ItemType Directory -Path $dotClaude | Out-Null }
  $f = Join-Path $dotClaude "settings.local.json"
  $obj = @{}
  if (Test-Path $f) {
    try { $obj = Get-Content $f -Raw | ConvertFrom-Json -AsHashtable } catch { $obj = @{} }
  }
  if (-not $obj.ContainsKey("env")) { $obj["env"] = @{} }
  $obj["env"]["ANTHROPIC_BASE_URL"] = $BaseUrl
  $obj["env"]["ANTHROPIC_AUTH_TOKEN"] = $AuthToken
  $obj["env"]["ANTHROPIC_API_KEY"] = $ApiKey
  $obj["env"]["ANTHROPIC_DEFAULT_OPUS_MODEL"] = $Opus
  $obj["env"]["ANTHROPIC_DEFAULT_OPUS_MODEL_NAME"] = $OpusName
  $obj["env"]["ANTHROPIC_DEFAULT_SONNET_MODEL"] = $Sonnet
  $obj["env"]["ANTHROPIC_DEFAULT_SONNET_MODEL_NAME"] = $SonnetName
  $obj["env"]["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = $Haiku
  $obj["env"]["ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME"] = $HaikuName
  $obj["env"]["CLAUDE_CODE_SUBAGENT_MODEL"] = $Sub
  $obj | ConvertTo-Json -Depth 10 | Set-Content -Path $f -Encoding UTF8
}

function _claude_oc_Unpin {
  $f = Join-Path (Get-Location) ".claude\settings.local.json"
  if (-not (Test-Path $f)) { Write-Host "Nothing to revert — no .claude\settings.local.json in $(Get-Location)."; return }
  try {
    $obj = Get-Content $f -Raw | ConvertFrom-Json -AsHashtable
  } catch { Write-Host "$f is not valid JSON — skipping."; return }
  if ($obj.ContainsKey("env")) {
    foreach ($k in @(
      "ANTHROPIC_BASE_URL","ANTHROPIC_AUTH_TOKEN","ANTHROPIC_API_KEY",
      "ANTHROPIC_DEFAULT_OPUS_MODEL","ANTHROPIC_DEFAULT_OPUS_MODEL_NAME",
      "ANTHROPIC_DEFAULT_SONNET_MODEL","ANTHROPIC_DEFAULT_SONNET_MODEL_NAME",
      "ANTHROPIC_DEFAULT_HAIKU_MODEL","ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME",
      "CLAUDE_CODE_SUBAGENT_MODEL"
    )) { $obj["env"].Remove($k) | Out-Null }
  }
  $obj | ConvertTo-Json -Depth 10 | Set-Content -Path $f -Encoding UTF8
  Write-Host "Reverted $(Get-Location) to your default Claude subscription. Reload VS Code (Developer: Reload Window)."
}

function _claude_oc_RunClaude {
  param(
    [string]$BaseUrl, [string]$ApiKey,
    [string]$Opus, [string]$OpusName,
    [string]$Sonnet, [string]$SonnetName,
    [string]$Haiku, [string]$HaikuName,
    [string]$Sub,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args
  )
  $env:ANTHROPIC_BASE_URL = $BaseUrl
  $env:ANTHROPIC_AUTH_TOKEN = ""
  $env:ANTHROPIC_API_KEY = $ApiKey
  $env:ANTHROPIC_DEFAULT_OPUS_MODEL = $Opus
  $env:ANTHROPIC_DEFAULT_OPUS_MODEL_NAME = $OpusName
  $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $Sonnet
  $env:ANTHROPIC_DEFAULT_SONNET_MODEL_NAME = $SonnetName
  $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $Haiku
  $env:ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME = $HaikuName
  $env:CLAUDE_CODE_SUBAGENT_MODEL = $Sub
  & claude @Args
}

# ── claude-oc: OpenCode Go via Anthropic endpoint (direct, no proxy) ──────────

function claude-oc {
  $opus   = _claude_oc_Get "OC_OPUS_MODEL"   $env:OPUS
  $opn    = _claude_oc_Get "OC_OPUS_NAME"   $env:OPUS_NAME
  $son    = _claude_oc_Get "OC_SONNET_MODEL" $env:SONNET
  $sonn   = _claude_oc_Get "OC_SONNET_NAME"  $env:SONNET_NAME
  $hai    = _claude_oc_Get "OC_HAIKU_MODEL" $env:HAIKU
  $hain   = _claude_oc_Get "OC_HAIKU_NAME"  $env:HAIKU_NAME
  $sub    = _claude_oc_Get "OC_SUBAGENT_MODEL" $env:SUBAGENT
  _claude_oc_RunClaude `
    (_claude_oc_Get "OPENCODE_GO_BASE_URL" "") (_claude_oc_Get "OPENCODE_GO_KEY" "") `
    $opus $opn $son $sonn $hai $hain $sub @args
}

function claude-oc-init {
  _claude_oc_Pin `
    (_claude_oc_Get "OPENCODE_GO_BASE_URL" "") (_claude_oc_Get "OPENCODE_GO_KEY" "") "" `
    (_claude_oc_Get "OC_OPUS_MODEL" $env:OPUS)   (_claude_oc_Get "OC_OPUS_NAME" $env:OPUS_NAME) `
    (_claude_oc_Get "OC_SONNET_MODEL" $env:SONNET) (_claude_oc_Get "OC_SONNET_NAME" $env:SONNET_NAME) `
    (_claude_oc_Get "OC_HAIKU_MODEL" $env:HAIKU) (_claude_oc_Get "OC_HAIKU_NAME" $env:HAIKU_NAME) `
    (_claude_oc_Get "OC_SUBAGENT_MODEL" $env:SUBAGENT)
  Write-Host "Pinned $(Get-Location): $(_claude_oc_Get "OC_OPUS_NAME" $env:OPUS_NAME) (opencode-go, direct). Existing settings preserved. Reload VS Code."
}

# ── claude-px: via local proxy (OpenAI-endpoint models) ───────────────────────

function _claude_oc_PxPort { return (_claude_oc_Get "PX_PORT" $env:PX_PORT) }

function _claude_oc_ProxyRunning {
  $port = _claude_oc_PxPort
  $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
  return [bool]$c
}

function px {
  param([string]$Upstream, [string]$UpstreamKey)
  if (_claude_oc_ProxyRunning) { Write-Host "Proxy already running on port $(_claude_oc_PxPort)."; return }
  if (-not (Test-Path $script:ClaudeOcProxy)) { Write-Host "oc-proxy.js not found at $script:ClaudeOcProxy — run setup."; return }
  if (-not $Upstream)     { $Upstream     = _claude_oc_Get "OPENCODE_GO_BASE_URL" "" }
  if (-not $UpstreamKey)  { $UpstreamKey  = _claude_oc_Get "OPENCODE_GO_KEY" "" }
  $port = _claude_oc_PxPort
  $env:PX_PORT = $port
  $env:PX_UPSTREAM_BASE_URL = $Upstream
  $env:PX_UPSTREAM_API_KEY  = $UpstreamKey
  $log = Join-Path $env:TEMP "oc-proxy.log"
  Start-Process -FilePath "node" -ArgumentList @($script:ClaudeOcProxy) -WindowStyle Hidden -RedirectStandardOutput $log
  Start-Sleep -Seconds 1
  if (_claude_oc_ProxyRunning) { Write-Host "Proxy started on http://127.0.0.1:$port -> $Upstream." }
  else { Write-Host "Failed to start proxy. Check $log" }
}

function px-stop {
  $port = _claude_oc_PxPort
  $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
  if ($c) {
    Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
    Write-Host "Proxy stopped (PID $($c.OwningProcess))."
  } else { Write-Host "Proxy not running." }
}

function claude-px {
  px
  if (-not (_claude_oc_ProxyRunning)) { return }
  $port = _claude_oc_PxPort
  _claude_oc_RunClaude `
    "http://127.0.0.1:$port" (_claude_oc_Get "OPENCODE_GO_KEY" "") `
    (_claude_oc_Get "PX_OPUS_MODEL" $env:OPUS)   (_claude_oc_Get "PX_OPUS_NAME" $env:OPUS_NAME) `
    (_claude_oc_Get "PX_SONNET_MODEL" $env:SONNET) (_claude_oc_Get "PX_SONNET_NAME" $env:SONNET_NAME) `
    (_claude_oc_Get "PX_HAIKU_MODEL" $env:HAIKU) (_claude_oc_Get "PX_HAIKU_NAME" $env:HAIKU_NAME) `
    (_claude_oc_Get "PX_SUBAGENT_MODEL" $env:SUBAGENT) @args
}

function claude-px-init {
  $port = _claude_oc_PxPort
  _claude_oc_Pin `
    "http://127.0.0.1:$port" (_claude_oc_Get "OPENCODE_GO_KEY" "") "" `
    (_claude_oc_Get "PX_OPUS_MODEL" $env:OPUS)   (_claude_oc_Get "PX_OPUS_NAME" $env:OPUS_NAME) `
    (_claude_oc_Get "PX_SONNET_MODEL" $env:SONNET) (_claude_oc_Get "PX_SONNET_NAME" $env:SONNET_NAME) `
    (_claude_oc_Get "PX_HAIKU_MODEL" $env:HAIKU) (_claude_oc_Get "PX_HAIKU_NAME" $env:HAIKU_NAME) `
    (_claude_oc_Get "PX_SUBAGENT_MODEL" $env:SUBAGENT)
  Write-Host "Pinned $(Get-Location): $(_claude_oc_Get "PX_OPUS_NAME" $env:OPUS_NAME) via local proxy. Run 'px' in a terminal first (for VS Code). Reload VS Code."
}

# ── claude-litellm: your LiteLLM gateway ─────────────────────────────────────

function claude-litellm {
  $url = _claude_oc_Get "LITELLM_BASE_URL" ""
  $useProxy = _claude_oc_Get "LITELLM_USE_PROXY" $env:LITELLM_USE_PROXY
  if ($useProxy -eq "1") {
    px (_claude_oc_Get "LITELLM_BASE_URL" "") (_claude_oc_Get "LITELLM_API_KEY" "")
    if (-not (_claude_oc_ProxyRunning)) { return }
    $url = "http://127.0.0.1:$(_claude_oc_PxPort)"
  }
  _claude_oc_RunClaude `
    $url (_claude_oc_Get "LITELLM_API_KEY" "") `
    (_claude_oc_Get "LITELLM_OPUS_MODEL" $env:OPUS)   (_claude_oc_Get "LITELLM_OPUS_NAME" $env:OPUS_NAME) `
    (_claude_oc_Get "LITELLM_SONNET_MODEL" $env:SONNET) (_claude_oc_Get "LITELLM_SONNET_NAME" $env:SONNET_NAME) `
    (_claude_oc_Get "LITELLM_HAIKU_MODEL" $env:HAIKU) (_claude_oc_Get "LITELLM_HAIKU_NAME" $env:HAIKU_NAME) `
    (_claude_oc_Get "LITELLM_SUBAGENT_MODEL" $env:SUBAGENT) @args
}

function claude-litellm-init {
  $url = _claude_oc_Get "LITELLM_BASE_URL" ""
  $useProxy = _claude_oc_Get "LITELLM_USE_PROXY" $env:LITELLM_USE_PROXY
  if ($useProxy -eq "1") { $url = "http://127.0.0.1:$(_claude_oc_PxPort)" }
  _claude_oc_Pin `
    $url (_claude_oc_Get "LITELLM_API_KEY" "") "" `
    (_claude_oc_Get "LITELLM_OPUS_MODEL" $env:OPUS)   (_claude_oc_Get "LITELLM_OPUS_NAME" $env:OPUS_NAME) `
    (_claude_oc_Get "LITELLM_SONNET_MODEL" $env:SONNET) (_claude_oc_Get "LITELLM_SONNET_NAME" $env:SONNET_NAME) `
    (_claude_oc_Get "LITELLM_HAIKU_MODEL" $env:HAIKU) (_claude_oc_Get "LITELLM_HAIKU_NAME" $env:HAIKU_NAME) `
    (_claude_oc_Get "LITELLM_SUBAGENT_MODEL" $env:SUBAGENT)
  Write-Host "Pinned $(Get-Location): $(_claude_oc_Get "LITELLM_OPUS_NAME" $env:OPUS_NAME) (LiteLLM). Existing settings preserved. Reload VS Code."
}

# Shared revert.
function claude-oc-revert   { _claude_oc_Unpin }
function claude-px-revert   { _claude_oc_Unpin }
function claude-litellm-revert { _claude_oc_Unpin }