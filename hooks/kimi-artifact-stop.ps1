# Native PowerShell equivalent of hooks/kimi-artifact-stop.sh for Windows installs.
#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'powershell-common.ps1')
$pluginRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$generator = Join-Path $pluginRoot 'scripts/artifact-generator.py'
try {
    $result = Invoke-ChoirboyPython $generator @('stop-kimi')
    if ($result.Output) { [Console]::Out.WriteLine($result.Output) }
    if ($result.ExitCode -eq 2) { exit 2 }
    if ($result.ExitCode -eq 0) { exit 0 }
} catch { }
[Console]::Error.WriteLine('agent-plugin: Kimi artifact Stop hook failed open')
exit 0
