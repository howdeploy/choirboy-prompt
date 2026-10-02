# Native PowerShell equivalent of hooks/session-start.sh for Windows installs.
# Supported formats: claude (SessionStart JSON), plain, and hermes.
#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'powershell-common.ps1')

$pluginRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$generator = Join-Path $pluginRoot 'scripts/artifact-generator.py'
$format = 'claude'
$arguments = @($args)
for ($i = 0; $i -lt $arguments.Count; $i++) {
    if ($arguments[$i] -eq '--format') {
        if ($i + 1 -ge $arguments.Count) { [Console]::Error.WriteLine('--format requires a value'); exit 1 }
        $format = [string]$arguments[++$i]
    } elseif ($arguments[$i] -in '-h', '--help') {
        [Console]::Out.WriteLine('session-start.ps1 [--format claude|plain|hermes]')
        exit 0
    } else {
        [Console]::Error.WriteLine("session-start.ps1: unknown argument: $($arguments[$i])")
        exit 1
    }
}
if ($format -notin @('claude', 'plain', 'hermes')) {
    [Console]::Error.WriteLine("session-start.ps1: unknown format: $format")
    exit 1
}

$manifest = Join-Path $pluginRoot '.claude-plugin/plugin.json'
$version = 'unknown'
try { $version = [string](Get-Content -LiteralPath $manifest -Raw -Encoding utf8 | ConvertFrom-Json).version } catch { }

if ($format -eq 'claude') {
    $status = 'Choirboy memory status: unavailable. Python or the artifact generator is missing. Load the load-context skill for the fixed lore. This message is a status, not loaded team context. Do not author dossiers unless the user explicitly asks to update Choirboy memory.'
    if (Test-Path -LiteralPath $generator -PathType Leaf) {
        try {
            $result = Invoke-ChoirboyPython $generator @('session-status')
            if ($result.ExitCode -eq 0) { $status = $result.Output }
        } catch { }
    }
    $response = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = 'SessionStart'; additionalContext = $status } }
    [Console]::Out.WriteLine(($response | ConvertTo-Json -Depth 8 -Compress))
    exit 0
}

$parts = [Collections.Generic.List[string]]::new()
foreach ($relative in @('prompt.md', 'security-posture.md', 'lore.md', 'user.md', 'context/research-index.md')) {
    $path = Join-Path $pluginRoot $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $fragment = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8).Replace("`r", '')
        $fragment = [regex]::Replace($fragment, '\n+$', '')
        if ($fragment) { $parts.Add($fragment) }
    } else { [Console]::Error.WriteLine("agent-plugin: $relative missing — skipped") }
}
$payload = $parts -join "`n`n---`n`n"
$contextHash = Get-ChoirboySha256 ($payload + "`n")
$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd'T'HHmmss'Z'")
$nonce = "$stamp-$PID"
$payload = "<choirboy-delivery version=`"$version`" delivery=`"session-start`" context_sha256=`"$contextHash`" nonce=`"$nonce`" />`n<choirboy-context>`n$payload`n</choirboy-context>"

$artifactContext = ''
if ((Get-ChoirboyPython) -and (Test-Path -LiteralPath $generator -PathType Leaf)) {
    try {
        $result = Invoke-ChoirboyPython $generator @('session-context')
        if ($result.ExitCode -eq 0) { $artifactContext = $result.Output }
        else { throw 'artifact generator exited unsuccessfully' }
    } catch {
        [Console]::Error.WriteLine('agent-plugin: artifact lifecycle could not be prepared')
        $artifactContext = '<choirboy-project-artifacts status="unavailable">Artifact lifecycle failed to initialize; inspect the SessionStart hook stderr.</choirboy-project-artifacts>'
    }
} else {
    $artifactContext = '<choirboy-project-artifacts status="unavailable">Automatic project artifacts require Python 3 and scripts/artifact-generator.py.</choirboy-project-artifacts>'
}
$payload += "`n$artifactContext"

if ($env:CLAUDE_PLUGIN_DATA) {
    try {
        $diagnostic = "version=$version`ndelivery=session-start`ncontext_sha256=$contextHash`nnonce=$nonce`nplugin_root=$pluginRoot`n"
        Write-ChoirboyAtomicText (Join-Path $env:CLAUDE_PLUGIN_DATA 'latest-delivery.log') $diagnostic
    } catch { }
}

if ($format -eq 'plain') {
    [Console]::Out.WriteLine($payload)
    exit 0
}

$inputText = [Console]::In.ReadToEnd()
$firstTurn = $null
$sessionId = ''
if ($inputText) {
    try {
        $event = $inputText | ConvertFrom-Json -AsHashtable
        if ($event.extra -is [Collections.IDictionary] -and $event.extra.Contains('is_first_turn')) { $firstTurn = $event.extra.is_first_turn }
        if ($event.session_id) { $sessionId = [string]$event.session_id }
    } catch { }
}
if ($firstTurn -ceq $false) {
    [Console]::Out.WriteLine('{}')
    exit 0
}
if ($firstTurn -cne $true) {
    if (-not $sessionId) { [Console]::Out.WriteLine('{}'); exit 0 }
    $userName = if ($env:USERNAME) { $env:USERNAME } elseif ($env:USER) { $env:USER } else { 'user' }
    $statePath = Join-Path ([IO.Path]::GetTempPath()) "agent-plugin-hermes-$userName.state"
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        if (([IO.File]::ReadAllText($statePath)).TrimEnd("`r", "`n") -eq $sessionId) { [Console]::Out.WriteLine('{}'); exit 0 }
    }
    try { Write-ChoirboyAtomicText $statePath ($sessionId + "`n") } catch { }
}
[Console]::Out.WriteLine((([ordered]@{ context = $payload }) | ConvertTo-Json -Depth 6 -Compress))
