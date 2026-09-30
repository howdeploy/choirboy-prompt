# Native PowerShell equivalent of hooks/kimi-user-prompt.sh for Windows installs.
#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'powershell-common.ps1')
$pluginRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sessionHook = Join-Path $PSScriptRoot 'session-start.ps1'
$inputText = [Console]::In.ReadToEnd()
$event = @{}
try { if ($inputText) { $event = $inputText | ConvertFrom-Json -AsHashtable } } catch { }
if ($event.hook_event_name -cne 'UserPromptSubmit') { exit 0 }

$sessionId = if ($event.session_id) { [string]$event.session_id } elseif ($event.sessionId) { [string]$event.sessionId } else { '' }
$key = ''
if ($sessionId) {
    $keyMaterial = ConvertTo-Json -InputObject @(2, $sessionId, [string]$event.cwd) -Compress
    $key = Get-ChoirboySha256 $keyMaterial
}
$stateRoot = if ($env:CHOIRBOY_STATE_DIR) { $env:CHOIRBOY_STATE_DIR }
elseif ($env:KIMI_CODE_HOME) { Join-Path $env:KIMI_CODE_HOME 'choirboy-prompt/hook-state' }
else { Join-Path $HOME '.kimi-code/choirboy-prompt/hook-state' }
$marker = ''
try { [IO.Directory]::CreateDirectory($stateRoot) | Out-Null } catch { [Console]::Error.WriteLine('agent-plugin: cannot create Kimi hook state; delivering without marker') }
if ($key) { $marker = Join-Path $stateRoot "$key.delivered" }

$pwsh = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $pwsh) { [Console]::Error.WriteLine('agent-plugin: PowerShell 7 is unavailable; Kimi delivery failed open'); exit 0 }
$payloadLines = & $pwsh.Source -NoProfile -File $sessionHook --format plain
$payloadExit = $LASTEXITCODE
$payload = @($payloadLines) -join "`n"
if ($payloadExit -ne 0) { [Console]::Error.WriteLine('agent-plugin: Kimi context delivery failed open'); exit 0 }

$ready = $payload.Contains("`n# Established project history`n", [StringComparison]::Ordinal)
$fingerprint = ''
if ($ready) {
    $normalized = [regex]::Replace($payload, ' nonce="[^"]*"', ' nonce=""', 1)
    $fingerprint = Get-ChoirboySha256 $normalized
    if ($marker -and (Test-Path -LiteralPath $marker -PathType Leaf)) {
        $previous = [IO.File]::ReadAllText($marker).Trim()
        if ($previous -ceq $fingerprint) { exit 0 }
    }
}
[Console]::Out.WriteLine($payload)
if ($ready -and $marker -and $fingerprint) {
    try { Write-ChoirboyAtomicText $marker ($fingerprint + "`n") } catch { }
}
