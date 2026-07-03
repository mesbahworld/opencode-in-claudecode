# ─────────────────────────────────────────────────────────────────────────────
# setup.ps1 — installer for OpenCode-in-ClaudeCode (Windows / PowerShell).
#
# What it does:
#   1. Checks for prerequisites: claude (Claude Code CLI), node, jq.
#   2. Copies oc-proxy.js to $HOME\.claude\oc-proxy.js.
#   3. Creates $HOME\.claude\claude-oc.env from .env (or .env.example) — never overwrites.
#   4. Installs claude-oc.ps1 (PowerShell function module) to $HOME\.claude\claude-oc.ps1.
#   5. Adds a one-line `.` dot-source to your PowerShell profile, idempotently.
#
# Usage:  ./setup.ps1                      # interactive (prompts for empty values)
#         ./setup.ps1 -NonInteractive      # skip prompts; fail on missing values
# ─────────────────────────────────────────────────────────────────────────────
[CmdletBinding()]
param(
  [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
$Interactive = -not $NonInteractive.IsPresent

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$ClaudeDir = Join-Path $HOME ".claude"
if (-not (Test-Path $ClaudeDir)) { New-Item -ItemType Directory -Path $ClaudeDir | Out-Null }

function Check-Cmd {
  param([string]$Cmd, [string]$Label, [string]$Hint)
  $found = Get-Command $Cmd -ErrorAction SilentlyContinue
  if ($found) {
    Write-Host "  [OK]  $($Label.PadRight(10)) $($found.Source)"
  } else {
    Write-Host "  [MISSING]  $Label"
    Write-Host "      install: $Hint"
    if ($Interactive) {
      $ans = Read-Host "      continue anyway? [y/N]"
      if ($ans -ne "y") { exit 1 }
    } else {
      exit 1
    }
  }
}

Write-Host "Checking prerequisites…"
Check-Cmd claude "claude"  "npm i -g @anthropic-ai/claude-code@windows"
Check-Cmd node   "node"    "https://nodejs.org  (winget install OpenJS.NodeJS)"
Check-Cmd jq     "jq"      "winget install jqlang.jq  |  choco install jq"

# ── 1. install oc-proxy.js ───────────────────────────────────────────────────

Write-Host
Write-Host "Installing oc-proxy.js -> $ClaudeDir\oc-proxy.js"
Copy-Item -Force (Join-Path $Here "oc-proxy.js") (Join-Path $ClaudeDir "oc-proxy.js")

# ── 2. configure env ─────────────────────────────────────────────────────────

$EnvDst = Join-Path $ClaudeDir "claude-oc.env"
$EnvSrc = Join-Path $Here ".env"
if (-not (Test-Path $EnvSrc)) { $EnvSrc = Join-Path $Here ".env.example" }

if (-not (Test-Path $EnvDst)) {
  Write-Host "Installing env -> $EnvDst  (from $EnvSrc)"
  Copy-Item $EnvSrc $EnvDst
} else {
  Write-Host "Env already exists at $EnvDst — leaving in place (edit it manually to change)."
}

function Prompt-IfEmpty {
  param([string]$Var, [string]$Label)
  $cur = $null
  if (Test-Path $EnvDst) {
    $line = Get-Content $EnvDst | Where-Object { $_ -match "^$Var=" } | Select-Object -First 1
    if ($line) {
      $cur = ($line -replace "^$Var=", "" -replace '"', "").Trim()
    }
  }
  if ([string]::IsNullOrEmpty($cur) -and $Interactive) {
    $val = Read-Host "  $Label"
    if ($val) {
      $content = Get-Content $EnvDst
      $matched = $false
      $content = $content | ForEach-Object {
        if ($_ -match "^$Var=") { $matched = $true; "$VAR=`"$val`"" }
        else { $_ }
      }
      if (-not $matched) { $content += "$Var=`"$val`"" }
      Set-Content -Path $EnvDst -Value $content
    }
  }
}

if ($Interactive) {
  Write-Host
  Write-Host "Key values (leave blank to skip / keep example):"
  Prompt-IfEmpty "OPENCODE_GO_KEY"  "OpenCode Go API key  (https://opencode.ai/auth)"
  Prompt-IfEmpty "LITELLM_API_KEY"  "LiteLLM API key      (blank if no auth)"
  Prompt-IfEmpty "LITELLM_BASE_URL" "LiteLLM base URL     (e.g. https://llm.mesbahuddin.com)"
}

Write-Host
Write-Host "Env file:  $EnvDst   (edit anytime)"

# ── 3. install PowerShell functions ──────────────────────────────────────────

$FnSrc = Join-Path $Here "claude-oc.ps1"
$FnDst = Join-Path $ClaudeDir "claude-oc.ps1"
if (Test-Path $FnSrc) {
  Write-Host "Installing functions -> $FnDst"
  Copy-Item -Force $FnSrc $FnDst
} else {
  Write-Host "Warning: claude-oc.ps1 not found in $Here — PowerShell functions not installed."
}

# ── 4. inject into PowerShell profile ─────────────────────────────────────────

$ProfilePath = $PROFILE.CurrentUserAllHosts
$ProfileDir = Split-Path -Parent $ProfilePath
if (-not (Test-Path $ProfileDir)) { New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null }

$Marker = "# >>> claude-oc (opencode-in-claudecode) >>>"
$MarkerEnd = "# <<< claude-oc <<<"

$needAdd = $true
if (Test-Path $ProfilePath) {
  $content = Get-Content $ProfilePath -ErrorAction SilentlyContinue
  if ($content | Where-Object { $_ -match "claude-oc \(opencode-in-claudecode\)" }) {
    Write-Host "Source line already present in $ProfilePath — refreshing block…"
    # remove old block
    $new = [System.Collections.ArrayList]::new()
    $skip = $false
    foreach ($l in $content) {
      if ($l -match "claude-oc \(opencode-in-claudecode\) >>>") { $skip = $true; continue }
      if ($l -match "claude-oc <<<") { $skip = $false; continue }
      if (-not $skip) { [void]$new.Add($l) }
    }
    Set-Content -Path $ProfilePath -Value $new
    $needAdd = $true
  } else {
    $needAdd = $true
  }
}

if ($needAdd -and (Test-Path $FnDst)) {
  Add-Content -Path $ProfilePath -Value "`n$Marker`n. `"$FnDst`"`n$MarkerEnd"
  Write-Host "Source line added to $ProfilePath."
}

# ── done ─────────────────────────────────────────────────────────────────────

Write-Host
Write-Host "Done. Restart your PowerShell session (or run:  . `"$FnDst`")"
Write-Host
Write-Host "Commands available:"
Write-Host "  claude-oc               Claude Code via opencode-go Anthropic endpoint (MiniMax M3 / Qwen)"
Write-Host "  claude-oc-init          pin current project to opencode-go (for VS Code)"
Write-Host "  claude-px               Claude Code via local proxy (GLM / Kimi / DeepSeek)"
Write-Host "  px / px-stop            start / stop the local proxy"
Write-Host "  claude-px-init          pin current project to proxy (for VS Code)"
Write-Host "  claude-litellm          Claude Code via your LiteLLM gateway"
Write-Host "  claude-litellm-init     pin current project to LiteLLM (for VS Code)"
Write-Host "  claude-oc-revert        unpin current project (restores default Claude subscription)"