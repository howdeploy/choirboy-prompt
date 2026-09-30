# Native PowerShell equivalent of hooks/artifact-stop.sh for Windows installs.
#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'powershell-common.ps1')
$pluginRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$generator = Join-Path $pluginRoot 'scripts/artifact-generator.py'
try {
    $result = Invoke-ChoirboyPython $generator @('stop')
    if ($result.ExitCode -eq 0) { [Console]::Out.WriteLine($result.Output); exit 0 }
} catch { }
[Console]::Error.WriteLine('agent-plugin: artifact Stop hook failed open')
[Console]::Out.WriteLine('{}')
exit 0
