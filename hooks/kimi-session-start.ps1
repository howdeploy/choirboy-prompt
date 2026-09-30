# Native PowerShell equivalent of hooks/kimi-session-start.sh for Windows installs.
#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'powershell-common.ps1')
$pluginRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$generator = Join-Path $pluginRoot 'scripts/artifact-generator.py'
$inputText = [Console]::In.ReadToEnd()
$event = @{}
try { if ($inputText) { $event = $inputText | ConvertFrom-Json -AsHashtable } } catch { }

$stateRoot = if ($env:CHOIRBOY_STATE_DIR) { $env:CHOIRBOY_STATE_DIR }
elseif ($env:KIMI_CODE_HOME) { Join-Path $env:KIMI_CODE_HOME 'choirboy-prompt/hook-state' }
else { Join-Path $HOME '.kimi-code/choirboy-prompt/hook-state' }
try { [IO.Directory]::CreateDirectory($stateRoot) | Out-Null } catch { [Console]::Error.WriteLine('agent-plugin: cannot create Kimi hook state; context may repeat') }

if ($event.hook_event_name -in @('SessionStart', 'PreCompact')) {
    $sessionId = if ($event.session_id) { [string]$event.session_id } elseif ($event.sessionId) { [string]$event.sessionId } else { '' }
    if ($sessionId) {
        $keyMaterial = ConvertTo-Json -InputObject @(2, $sessionId, [string]$event.cwd) -Compress
        $key = Get-ChoirboySha256 $keyMaterial
        $marker = Join-Path $stateRoot "$key.delivered"
        if (Test-Path -LiteralPath $marker -PathType Leaf) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }
    }
}
if (Test-Path -LiteralPath $generator -PathType Leaf) {
    try { $null = Invoke-ChoirboyPython $generator @('prepare') }
    catch { [Console]::Error.WriteLine('agent-plugin: Kimi artifact preparation failed open') }
}
exit 0
