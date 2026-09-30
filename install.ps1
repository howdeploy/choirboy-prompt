#Requires -Version 7.0
<#
PowerShell implementation of the Choirboy Prompt multi-runtime installer.
It does not invoke install.sh or Bash. Python is used only for the repository's
existing context and artifact lifecycle helpers.

Usage: pwsh -NoProfile -File ./install.ps1 [--target claude,codex] [--uninstall]
       [--list] [--instructions FILE] [--project] [--settings PATH]
#>

$ErrorActionPreference = 'Stop'
$script:PluginRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$script:Mark = 'agent-plugin:vibe-lore'
$script:RegistrationVersion = '2'
$script:RegistrationMark = "$($script:Mark):registration=$($script:RegistrationVersion)"
$script:HookExtension = if ($IsWindows) { '.ps1' } else { '.sh' }
$script:HookScript = Join-Path $script:PluginRoot "hooks/session-start$($script:HookExtension)"
$script:StopHookScript = Join-Path $script:PluginRoot "hooks/artifact-stop$($script:HookExtension)"
$script:KimiSessionHookScript = Join-Path $script:PluginRoot "hooks/kimi-session-start$($script:HookExtension)"
$script:KimiPromptHookScript = Join-Path $script:PluginRoot "hooks/kimi-user-prompt$($script:HookExtension)"
$script:KimiStopHookScript = Join-Path $script:PluginRoot "hooks/kimi-artifact-stop$($script:HookExtension)"
$script:ArtifactGenerator = Join-Path $script:PluginRoot 'scripts/artifact-generator.py'
$script:BuildContext = Join-Path $script:PluginRoot 'scripts/build-context.py'
$script:CodexContextLimit = 4000
$script:AllTargets = @('claude', 'codex', 'opencode', 'hermes', 'kimi', 'gemini', 'grok', 'grokbot', 'pi', 'omp', 'llama')
$script:HomePath = if ($HOME) { [IO.Path]::GetFullPath($HOME) } else { [Environment]::GetFolderPath('UserProfile') }
$script:KimiHome = if ($env:KIMI_CODE_HOME) { [IO.Path]::GetFullPath($env:KIMI_CODE_HOME) } else { Join-Path $script:HomePath '.kimi-code' }
$script:Uninstall = $false
$script:ListOnly = $false
$script:Scope = 'user'
$script:SettingsFile = ''
$script:TargetSpec = ''
$script:InstructionsFiles = [Collections.Generic.List[string]]::new()
$script:CliArgs = @($args)

function Write-Usage {
    @'
PowerShell installer for Choirboy Prompt.

  --target LIST       comma-separated targets; use "none" for no runtimes
  --uninstall         remove this installer's registrations
  --list              show detected target status
  --instructions FILE add or remove a managed instruction block (repeatable)
  --project           use ./.claude/settings.json (Claude target)
  --settings PATH     use an explicit Claude settings file
  -h, --help          show this help

Targets: claude,codex,opencode,hermes,kimi,gemini,grok,grokbot,pi,omp,llama
'@
}

function Stop-Installer([string] $Message) {
    throw $Message
}

function Resolve-Python {
    $script:PythonPrefix = @()
    foreach ($name in @('python3', 'python', 'py')) {
        $candidate = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $candidate) {
            $script:PythonExe = $candidate.Source
            if ($name -eq 'py') { $script:PythonPrefix = @('-3') }
            return
        }
    }
    Stop-Installer 'Python 3 is required (python3, python, or the Windows py launcher).'
}

function Invoke-Python([string[]] $Arguments) {
    $allArgs = @()
    if ($script:PythonPrefix.Count -gt 0) { $allArgs += $script:PythonPrefix }
    $allArgs += $Arguments
    $output = & $script:PythonExe @allArgs
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Stop-Installer "Python helper failed with exit code ${code}: $($Arguments -join ' ')"
    }
    return ,$output
}

function Get-PythonCommandText {
    $exe = $script:PythonExe.Replace('"', '\"')
    $quoted = if ($exe -match '\s') { "`"$exe`"" } else { $exe }
    if ($script:PythonPrefix.Count) { return "$quoted $($script:PythonPrefix -join ' ')" }
    return $quoted
}

function Resolve-UserPath([string] $Path) {
    if ($Path -eq '~') { return $script:HomePath }
    if ($Path.StartsWith('~/') -or $Path.StartsWith('~\')) {
        return [IO.Path]::GetFullPath((Join-Path $script:HomePath $Path.Substring(2)))
    }
    return [IO.Path]::GetFullPath($Path)
}

function Get-ClaudeSettingsPath {
    if ($script:SettingsFile) { return (Resolve-UserPath $script:SettingsFile) }
    if ($script:Scope -eq 'project') { return (Join-Path (Get-Location).Path '.claude/settings.json') }
    return (Join-Path $script:HomePath '.claude/settings.json')
}

function Get-TargetPath([string] $Target) {
    switch ($Target) {
        'claude'   { return (Get-ClaudeSettingsPath) }
        'codex'    { return (Join-Path $script:HomePath '.codex/hooks.json') }
        'opencode' { return (Join-Path $script:HomePath '.config/opencode/plugins/agent-plugin.ts') }
        'hermes'   { return (Join-Path $script:HomePath '.hermes/config.yaml') }
        'kimi'     { return (Join-Path $script:KimiHome 'config.toml') }
        'gemini'   { return (Join-Path $script:HomePath '.gemini/GEMINI.md') }
        'grok'     { return (Join-Path $script:HomePath '.grok/AGENTS.md') }
        'grokbot'  { return (Join-Path $script:HomePath '.grokbot/choirboy-context/SKILL.md') }
        'pi'       { return (Join-Path $script:HomePath '.pi/agent/APPEND_SYSTEM.md') }
        'omp'      { return (Join-Path $script:HomePath '.omp/agent/AGENTS.md') }
        'llama'    { return (Join-Path $script:HomePath '.config/llama.cpp/choirboy-system-prompt.md') }
        default    { Stop-Installer "unknown target: $Target" }
    }
}

function Test-CommandAvailable([string] $Name) {
    return $null -ne (Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Test-TargetPresent([string] $Target) {
    $dir = switch ($Target) {
        'claude' { Join-Path $script:HomePath '.claude' }
        'codex' { Join-Path $script:HomePath '.codex' }
        'opencode' { Join-Path $script:HomePath '.config/opencode' }
        'hermes' { Join-Path $script:HomePath '.hermes' }
        'kimi' { $script:KimiHome }
        'gemini' { Join-Path $script:HomePath '.gemini' }
        'grok' { Join-Path $script:HomePath '.grok' }
        'grokbot' { Join-Path $script:HomePath '.grokbot' }
        'pi' { Join-Path $script:HomePath '.pi' }
        'omp' { Join-Path $script:HomePath '.omp' }
        'llama' { Join-Path $script:HomePath '.config/llama.cpp' }
    }
    $commands = switch ($Target) {
        'grokbot' { @('grokbot', 'grok-bot') }
        'llama' { @('llama-server', 'llama-cli', 'llamafile') }
        default { @($Target) }
    }
    foreach ($command in $commands) { if (Test-CommandAvailable $command) { return $true } }
    if ($Target -eq 'llama' -and (Test-Path -LiteralPath (Join-Path $script:HomePath '.llama'))) { return $true }
    return (Test-Path -LiteralPath $dir -PathType Container)
}

function Convert-ToBashPath([string] $Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($IsWindows -and $full -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2] -replace '\\', '/'
        return "/$drive/$rest"
    }
    return ($full -replace '\\', '/')
}

function Quote-BashDouble([string] $Value) {
    return '"' + ($Value -replace '\\', '\\\\' -replace '"', '\\"' -replace '\$', '\\$' -replace '`', '\\`') + '"'
}

function Get-HookCommand([string] $ScriptPath, [string] $Suffix = '') {
    if ($IsWindows) {
        $nativePath = [IO.Path]::GetFullPath($ScriptPath).Replace('"', '`"')
        $command = "pwsh -NoProfile -File `"$nativePath`""
    } else {
        $command = 'bash ' + (Quote-BashDouble (Convert-ToBashPath $ScriptPath))
    }
    if ($Suffix) { $command += " $Suffix" }
    return $command
}

function Get-BashHookPath([string] $ScriptPath) {
    if ($IsWindows) { return [IO.Path]::GetFullPath($ScriptPath) }
    return (Convert-ToBashPath $ScriptPath)
}

function Get-HookId([string] $ScriptPath) { return [IO.Path]::GetFileNameWithoutExtension($ScriptPath) }

function New-Backup([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '-' + [DateTime]::UtcNow.Ticks
    $destination = "$Path.bak.$stamp"
    Copy-Item -LiteralPath $Path -Destination $destination
    return $destination
}

function Write-AtomicText([string] $Path, [string] $Text, [switch] $Backup) {
    $parent = Split-Path -Parent $Path
    if ($parent) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    if ($Backup -and $exists) { New-Backup $Path | Out-Null }
    $temp = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.tmp.' + [guid]::NewGuid().ToString('N'))
    $encoding = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($temp, $Text, $encoding)
    try {
        if ($exists) {
            try { [IO.File]::Replace($temp, $Path, $null) }
            catch { [IO.File]::Move($temp, $Path, $true) }
        } else {
            [IO.File]::Move($temp, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}

function Read-Text([string] $Path) {
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

function Get-MarkerMatches([string] $Text, [string] $Marker) {
    $pattern = '(?m)^[\t ]*' + [regex]::Escape($Marker) + '[\t ]*(?:\r?\n|$)'
    return ,@([regex]::Matches($Text, $pattern))
}

function Assert-SingleManagedBlock([string] $Text, [string] $Start, [string] $End) {
    $starts = Get-MarkerMatches $Text $Start
    $ends = Get-MarkerMatches $Text $End
    if ($starts.Count -gt 1 -or $ends.Count -gt 1) { Stop-Installer 'duplicate managed-block markers found' }
    if ($starts.Count -ne $ends.Count) { Stop-Installer 'managed block has an unmatched marker' }
    if ($starts.Count -eq 1 -and $starts[0].Index -ge $ends[0].Index) { Stop-Installer 'managed block markers are out of order' }
    return [pscustomobject]@{ Starts = $starts; Ends = $ends }
}

function Sync-ManagedBlock([string] $Path, [string] $Start, [string] $End, [string] $Desired) {
    $parent = Split-Path -Parent $Path
    if ($parent) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    $current = if ($exists) { Read-Text $Path } else { '' }
    $desiredMarkers = Assert-SingleManagedBlock $Desired $Start $End
    if ($desiredMarkers.Starts.Count -ne 1 -or $desiredMarkers.Ends.Count -ne 1 -or
        $desiredMarkers.Starts[0].Index -ne 0 -or
        ($desiredMarkers.Ends[0].Index + $desiredMarkers.Ends[0].Length) -ne $Desired.Length) {
        Stop-Installer 'generated content is not exactly one complete managed block'
    }
    $markers = Assert-SingleManagedBlock $current $Start $End
    if ($markers.Starts.Count -eq 0) {
        $separator = if (-not $current) { '' } elseif (-not $current.EndsWith("`n")) { "`n`n" } elseif (-not $current.EndsWith("`n`n")) { "`n" } else { '' }
        $updated = $current + $separator + $Desired
    } else {
        $begin = $markers.Starts[0].Index
        $finish = $markers.Ends[0].Index + $markers.Ends[0].Length
        $updated = $current.Substring(0, $begin) + $Desired + $current.Substring($finish)
    }
    Write-AtomicText $Path $updated -Backup:$exists
    return 'changed'
}

function Remove-ManagedBlock([string] $Path, [string] $Start, [string] $End) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'absent' }
    $current = Read-Text $Path
    $markers = Assert-SingleManagedBlock $current $Start $End
    if ($markers.Starts.Count -eq 0) { return 'absent' }
    $begin = $markers.Starts[0].Index
    $finish = $markers.Ends[0].Index + $markers.Ends[0].Length
    # Remove one blank separator immediately before the block, matching install.sh.
    if ($begin -gt 0) {
        $prefix = $current.Substring(0, $begin)
        if ($prefix -match '(?:\r?\n)[\t ]*(?:\r?\n)$') {
            $lastLine = $prefix.LastIndexOf("`n")
            $previousLine = if ($lastLine -gt 0) { $prefix.LastIndexOf("`n", $lastLine - 1) } else { -1 }
            if ($previousLine -ge 0) { $begin = $previousLine + 1 } else { $begin = 0 }
        }
    }
    $updated = $current.Substring(0, $begin) + $current.Substring($finish)
    Write-AtomicText $Path $updated -Backup
    return 'changed'
}

function ConvertTo-JsonText($Value) {
    return (($Value | ConvertTo-Json -Depth 100) + "`n")
}

function Read-JsonObject([string] $Path, [string] $Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [ordered]@{} }
    try { $data = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable }
    catch { Stop-Installer "refusing to replace invalid JSON in ${Description} ${Path}: $($_.Exception.Message)" }
    if ($data -isnot [Collections.IDictionary]) { Stop-Installer "refusing to replace non-object JSON in ${Description} $Path" }
    return $data
}

function Get-JsonPathNode($Data, [string[]] $Keys, [bool] $Create) {
    $node = $Data
    for ($i = 0; $i -lt ($Keys.Count - 1); $i++) {
        $key = $Keys[$i]
        if (-not $node.Contains($key)) {
            if (-not $Create) { return $null }
            $node[$key] = [ordered]@{}
        }
        if ($node[$key] -isnot [Collections.IDictionary]) {
            Stop-Installer "refusing to replace non-object JSON path: $($Keys[0..$i] -join '.')"
        }
        $node = $node[$key]
    }
    return ,$node
}

function Test-ManagedHookEntry($Entry, [string] $HookId) {
    if ($Entry -isnot [Collections.IDictionary] -or $Entry.hooks -isnot [Collections.IList]) { return $false }
    foreach ($hook in $Entry.hooks) {
        if ($hook -isnot [Collections.IDictionary]) { continue }
        $text = [string]$hook.command
        if ($hook.args -is [Collections.IList]) { $text += ' ' + ($hook.args -join ' ') }
        if ($text.Contains($HookId, [StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

function Test-HookHandlerExact($Entry, [string] $Command, [string] $Argument, [Nullable[int]] $Timeout, [Nullable[int]] $ContextLimit) {
    if ($Entry -isnot [Collections.IDictionary] -or $Entry.hooks -isnot [Collections.IList] -or $Entry.hooks.Count -ne 1) { return $false }
    $hook = $Entry.hooks[0]
    if ($hook -isnot [Collections.IDictionary] -or $hook.command -cne $Command) { return $false }
    $expectedFieldCount = 2
    if ($Argument) {
        if ($hook.args -isnot [Collections.IList] -or $hook.args.Count -ne 1 -or $hook.args[0] -cne $Argument) { return $false }
        $expectedFieldCount++
    } elseif ($hook.Contains('args')) { return $false }
    if ($null -ne $Timeout) { if ($hook.timeout -ne $Timeout.Value) { return $false }; $expectedFieldCount++ } elseif ($hook.Contains('timeout')) { return $false }
    if ($null -ne $ContextLimit) { if ($hook.additionalContextLimit -ne $ContextLimit.Value) { return $false }; $expectedFieldCount++ } elseif ($hook.Contains('additionalContextLimit')) { return $false }
    if ($hook.type -cne 'command' -or $hook.Count -ne $expectedFieldCount) { return $false }
    return $true
}

function Get-JsonHookStatus([string] $Path, [string] $Command, [string] $DotPath, [string] $Argument, [Nullable[int]] $Timeout, [Nullable[int]] $ContextLimit, [string] $HookId) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'absent' }
    $data = Read-JsonObject $Path 'hook settings'
    $keys = $DotPath.Split('.')
    $node = Get-JsonPathNode $data $keys $false
    if ($null -eq $node) { return 'absent' }
    $entries = $node[$keys[-1]]
    if ($null -eq $entries) { return 'absent' }
    if ($entries -isnot [Collections.IList]) { return 'stale' }
    $owned = @($entries | Where-Object { Test-ManagedHookEntry $_ $HookId })
    if ($owned.Count -eq 0) { return 'absent' }
    if ($owned.Count -eq 1 -and (Test-HookHandlerExact $owned[0] $Command $Argument $Timeout $ContextLimit)) { return 'current' }
    return 'stale'
}

function Set-JsonHook([string] $Path, [string] $Command, [string] $Mode, [string] $DotPath, [string] $Argument, [Nullable[int]] $Timeout, [Nullable[int]] $ContextLimit, [string] $HookId) {
    $data = Read-JsonObject $Path 'hook settings'
    $keys = $DotPath.Split('.')
    $node = Get-JsonPathNode $data $keys $true
    $property = $keys[-1]
    $entries = $node[$property]
    if ($null -eq $entries) { $entries = [Collections.Generic.List[object]]::new() }
    elseif ($entries -isnot [Collections.IList]) { Stop-Installer "refusing to replace non-array JSON path: $DotPath" }
    else { $entries = [Collections.Generic.List[object]]::new([object[]]$entries) }

    if ($Mode -eq 'install') {
        $kept = [Collections.Generic.List[object]]::new()
        foreach ($entry in $entries) {
            if (Test-ManagedHookEntry $entry $HookId) { continue }
            $kept.Add($entry)
        }
        $entries = $kept
        $handler = [ordered]@{ type = 'command'; command = $Command }
        if ($Argument) { $handler.args = @($Argument) }
        if ($null -ne $Timeout) { $handler.timeout = $Timeout.Value }
        if ($null -ne $ContextLimit) { $handler.additionalContextLimit = $ContextLimit.Value }
        $entry = [ordered]@{ hooks = @($handler) }
        $entries.Add($entry)
    } else {
        $before = $entries.Count
        $kept = [Collections.Generic.List[object]]::new()
        foreach ($entry in $entries) { if (-not (Test-ManagedHookEntry $entry $HookId)) { $kept.Add($entry) } }
        if ($kept.Count -eq $before) { return 'unchanged' }
        $entries = $kept
    }
    $node[$property] = @($entries.ToArray())
    Write-AtomicText $Path (ConvertTo-JsonText $data) -Backup:(Test-Path -LiteralPath $Path -PathType Leaf)
    return 'changed'
}

function Get-KimiBlock {
    $session = Get-HookCommand $script:KimiSessionHookScript
    $prompt = Get-HookCommand $script:KimiPromptHookScript
    $stop = Get-HookCommand $script:KimiStopHookScript
    $sessionToml = ConvertTo-Json -InputObject $session -Compress
    $promptToml = ConvertTo-Json -InputObject $prompt -Compress
    $stopToml = ConvertTo-Json -InputObject $stop -Compress
    return @"
# >>> $($script:Mark) >>>
# $($script:RegistrationMark)
[[hooks]]
event = "SessionStart"
matcher = "^(startup|resume)$"
command = $sessionToml
timeout = 30

[[hooks]]
event = "PreCompact"
matcher = "^(manual|auto)$"
command = $sessionToml
timeout = 30

[[hooks]]
event = "UserPromptSubmit"
command = $promptToml
timeout = 30

[[hooks]]
event = "Stop"
command = $stopToml
timeout = 30
# <<< $($script:Mark) <<<
"@
}

function Test-TargetInstalled([string] $Target) {
    $path = Get-TargetPath $Target
    switch ($Target) {
        'claude' {
            try {
                $command = if ($IsWindows) { Get-HookCommand $script:HookScript } else { 'bash' }
                $stopCommand = if ($IsWindows) { Get-HookCommand $script:StopHookScript } else { 'bash' }
                $argument = if ($IsWindows) { '' } else { Get-BashHookPath $script:HookScript }
                $stopArgument = if ($IsWindows) { '' } else { Get-BashHookPath $script:StopHookScript }
                return (Get-JsonHookStatus $path $command 'hooks.SessionStart' $argument 15 $null (Get-HookId $script:HookScript)) -eq 'current' -and
                    (Get-JsonHookStatus $path $stopCommand 'hooks.Stop' $stopArgument 15 $null (Get-HookId $script:StopHookScript)) -eq 'current'
            } catch { return $false }
        }
        'codex' {
            try {
                return (Get-JsonHookStatus $path (Get-HookCommand $script:HookScript) 'hooks.SessionStart' '' 15 $script:CodexContextLimit (Get-HookId $script:HookScript)) -eq 'current' -and
                    (Get-JsonHookStatus $path (Get-HookCommand $script:StopHookScript) 'hooks.Stop' '' 15 $null (Get-HookId $script:StopHookScript)) -eq 'current'
            } catch { return $false }
        }
        'opencode' { return (Test-ExactManagedFile $path (New-OpenCodePlugin)) }
        'hermes' {
            $allow = Join-Path $script:HomePath '.hermes/shell-hooks-allowlist.json'
            $storedHookPath = if ($IsWindows) { $script:HookScript.Replace('\', '\\') } else { $script:HookScript }
            return (Test-FileContains $path @($script:RegistrationMark, $storedHookPath)) -and
                (Test-FileContains $allow @($storedHookPath))
        }
        'kimi' { return (Test-FileContains $path @((Get-KimiBlock).TrimEnd())) }
        'gemini' { return (Test-InstructionCurrent $path) }
        'grok' { return (Test-InstructionCurrent $path) }
        'grokbot' { return (Test-ExactManagedFile $path (New-GrokBotWorkflow)) }
        'pi' { return (Test-InstructionCurrent $path) -and (Test-SkillLinkCurrent (Join-Path $script:HomePath '.pi/agent/skills/load-context')) }
        'omp' { return (Test-InstructionCurrent $path) -and (Test-SkillLinkCurrent (Join-Path $script:HomePath '.omp/agent/skills/load-context')) }
        'llama' {
            $prompt = Join-Path $script:HomePath '.config/llama.cpp/choirboy-system-prompt.md'
            return (Test-InstructionCurrent $prompt) -and
                (Test-SkillLinkCurrent (Join-Path $script:HomePath '.config/llama.cpp/skills/load-context')) -and
                (Test-LlamaUiCurrent $prompt)
        }
    }
    return $false
}

function Test-FileContains([string] $Path, [string[]] $Needles) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $text = Read-Text $Path
    foreach ($needle in $Needles) { if (-not $text.Contains($needle, [StringComparison]::Ordinal)) { return $false } }
    return $true
}

function Test-InstructionCurrent([string] $Path) {
    return (Test-FileContains $Path @($script:RegistrationMark, $script:ArtifactGenerator))
}

function Test-ExactManagedFile([string] $Path, [string] $Expected) {
    return (Test-Path -LiteralPath $Path -PathType Leaf) -and ((Read-Text $Path) -ceq $Expected)
}

function Test-TargetManagedPresent([string] $Target) {
    $path = Get-TargetPath $Target
    if ($Target -in @('claude', 'codex')) {
        return (Test-FileContains $path @((Get-HookId $script:HookScript))) -or
            (Test-FileContains $path @((Get-HookId $script:StopHookScript)))
    }
    $needles = switch ($Target) {
        'opencode' { @($script:Mark) }
        'hermes' { @($script:Mark) }
        'kimi' { @($script:Mark) }
        { $_ -in 'gemini', 'grok', 'grokbot' } { @($script:Mark) }
        'pi' { @($script:Mark) }
        'omp' { @($script:Mark) }
        'llama' { @($script:Mark) }
    }
    if (Test-FileContains $path $needles) { return $true }
    if ($Target -eq 'pi') { return (Test-Path -LiteralPath (Join-Path $script:HomePath '.pi/agent/skills/load-context')) }
    if ($Target -eq 'omp') { return (Test-Path -LiteralPath (Join-Path $script:HomePath '.omp/agent/skills/load-context')) }
    if ($Target -eq 'llama') {
        return (Test-Path -LiteralPath (Join-Path $script:HomePath '.config/llama.cpp/skills/load-context')) -or
            (Test-Path -LiteralPath (Join-Path $script:HomePath '.config/llama.cpp/choirboy-ui.json'))
    }
    return $false
}

function Get-TargetStatus([string] $Target) {
    if (-not (Test-TargetPresent $Target)) { return 'absent' }
    if (Test-TargetInstalled $Target) { if ($Target -eq 'grokbot') { return 'prepared' }; return 'installed' }
    if (Test-TargetManagedPresent $Target) { return 'stale' }
    return 'detected'
}

function New-OpenCodePlugin {
    $hookJson = ConvertTo-Json -InputObject ([IO.Path]::GetFullPath($script:HookScript)) -Compress
    $windows = if ($IsWindows) { 'true' } else { 'false' }
    $template = @'
// >>> agent-plugin:vibe-lore >>>
// __REGISTRATION_MARK__
// OpenCode adapter for choirboy-prompt.
// Appends the canonical fixed lore to every model-bound system context.
// Fail-open: a missing hook, timeout, or malformed payload never blocks chat.

import { spawnSync } from "child_process"
import type { Plugin } from "@opencode-ai/plugin"

const HOOK_SCRIPT = __HOOK_SCRIPT__
const WINDOWS_RUNTIME = __WINDOWS_RUNTIME__
const DELIVERY_MARKER = "<choirboy-delivery "
const SESSION_DELIVERY_MARKER = ' delivery="session-start"'

export const AgentPlugin: Plugin = async () => {
  return {
    "experimental.chat.system.transform": async (input, output) => {
      try {
        const sessionID = typeof input.sessionID === "string" ? input.sessionID : ""
        if (!sessionID) return
        if (!Array.isArray(output.system)) return
        if (
          output.system.some(
            (value) =>
              typeof value === "string" &&
              value.includes(DELIVERY_MARKER) &&
              value.includes(SESSION_DELIVERY_MARKER) &&
              value.includes("<choirboy-context>"),
          )
        ) return

        // System context is rebuilt for every model request. Recompute the
        // lifecycle payload here so pending -> ready and later lore/dossier
        // changes are visible immediately, including after session compaction.
        const result = spawnSync(
          WINDOWS_RUNTIME ? "pwsh" : "bash",
          WINDOWS_RUNTIME
            ? ["-NoProfile", "-File", HOOK_SCRIPT, "--format", "plain"]
            : [HOOK_SCRIPT, "--format", "plain"],
          {
          encoding: "utf8",
          timeout: 15000,
          maxBuffer: 2 * 1024 * 1024,
          },
        )
        const delivered = (result.stdout ?? "").trim()
        if (
          result.status !== 0 ||
          !delivered.includes(DELIVERY_MARKER) ||
          !delivered.includes("<choirboy-context>")
        ) return
        output.system.push(delivered)
      } catch {
        // fail-open: lore delivery must never break the OpenCode session
      }
    },
  }
}

export default AgentPlugin
// <<< agent-plugin:vibe-lore <<<
'@
    $rendered = $template.Replace('__HOOK_SCRIPT__', $hookJson)
    $rendered = $rendered.Replace('__WINDOWS_RUNTIME__', $windows)
    return $rendered.Replace('__REGISTRATION_MARK__', $script:RegistrationMark)
}

function New-GrokBotWorkflow {
    $sourcePath = Join-Path $script:PluginRoot 'skills/load-context/SKILL.md'
    $content = Read-Text $sourcePath
    if (-not $content.StartsWith("---`n") -and -not $content.StartsWith("---`r`n")) {
        Stop-Installer "invalid generated skill (missing frontmatter): $sourcePath"
    }
    if ($content -notmatch '(?m)^---\r?\n') { Stop-Installer "invalid generated skill (unterminated frontmatter): $sourcePath" }
    $content = $content.Replace('name: load-context', 'name: choirboy-context')
    $marker = "`n<!-- $($script:Mark): managed Grok Bot workflow; $($script:RegistrationMark) -->`n"
    # The first delimiter closes frontmatter; locate it after the opening delimiter.
    $closing = [regex]::Match($content.Substring(4), "\r?`n---\r?`n")
    if (-not $closing.Success) { Stop-Installer "invalid generated skill (unterminated frontmatter): $sourcePath" }
    $insertAt = 4 + $closing.Index + $closing.Length
    return $content.Substring(0, $insertAt) + $marker + $content.Substring($insertAt)
}

function Set-ManagedWholeFile([string] $Path, [string] $Expected, [string] $Mode, [string] $Description) {
    if ($Mode -eq 'status') {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'absent' }
        $current = Read-Text $Path
        if ($current -ceq $Expected) { return 'current' }
        if ($current.Contains($script:Mark, [StringComparison]::Ordinal)) { return 'stale' }
        return 'absent'
    }
    if ($Mode -eq 'install') {
        $exists = Test-Path -LiteralPath $Path -PathType Leaf
        if ($exists) {
            $current = Read-Text $Path
            if ($current -ceq $Expected) { return 'unchanged' }
            if (-not $current.Contains($script:Mark, [StringComparison]::Ordinal)) {
                Stop-Installer "refusing to overwrite an unmarked ${Description}: $Path"
            }
        }
        Write-AtomicText $Path $Expected -Backup:$exists
        return 'changed'
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'unchanged' }
    $current = Read-Text $Path
    if (-not $current.Contains($script:Mark, [StringComparison]::Ordinal)) {
        Stop-Installer "refusing to remove an unmarked ${Description}: $Path"
    }
    New-Backup $Path | Out-Null
    Remove-Item -LiteralPath $Path -Force
    return 'changed'
}

function Set-HermesAllowlist([string] $Mode) {
    $path = Join-Path $script:HomePath '.hermes/shell-hooks-allowlist.json'
    $command = Get-HookCommand $script:HookScript '--format hermes'
    $data = Read-JsonObject $path 'Hermes allowlist'
    $approvals = $data.approvals
    if ($null -eq $approvals) { $approvals = [Collections.Generic.List[object]]::new() }
    elseif ($approvals -isnot [Collections.IList]) { Stop-Installer "refusing to replace non-array approvals in $path" }
    else { $approvals = [Collections.Generic.List[object]]::new([object[]]$approvals) }
    $hookId = Get-HookId $script:HookScript
    $isOurs = { param($a) $a -is [Collections.IDictionary] -and $a.event -ceq 'pre_llm_call' -and ([string]$a.command).Contains($hookId) }
    $owned = @($approvals | Where-Object { & $isOurs $_ })
    if ($Mode -eq 'install' -and $owned.Count -eq 1 -and $owned[0].event -ceq 'pre_llm_call' -and $owned[0].command -ceq $command) { return 'unchanged' }
    $kept = [Collections.Generic.List[object]]::new()
    foreach ($approval in $approvals) { if (-not (& $isOurs $approval)) { $kept.Add($approval) } }
    if ($Mode -eq 'install') { $kept.Add([ordered]@{ event = 'pre_llm_call'; command = $command }) }
    if ($kept.Count -eq $approvals.Count -and $Mode -eq 'uninstall') { return 'unchanged' }
    $data.approvals = @($kept.ToArray())
    Write-AtomicText $path (ConvertTo-JsonText $data) -Backup:(Test-Path -LiteralPath $path -PathType Leaf)
    return 'changed'
}

function New-InstructionBlock([string] $Style) {
    $pythonCommand = Get-PythonCommandText
    $body = @'
## Team context (agent-plugin)

Lifecycle registration: `__REGISTRATION_MARK__`.

At session start, read these plugin files and work from their context:

- __PLUGIN_ROOT__/prompt.md — agent operating rules
- __PLUGIN_ROOT__/security-posture.md — security and audit frame
- __PLUGIN_ROOT__/lore.md — established project history and decisions
- __PLUGIN_ROOT__/user.md — user profile
- __PLUGIN_ROOT__/research/ — decision rationale, read on demand

At session start, run
`__PYTHON__ "__ARTIFACT_GENERATOR__" session-context`.
When the output begins with `# Established project history`, the dossiers are
ready: use that output as project memory. Any other output is a status, not a
request to write files. Load the fixed lore from the files listed above. Author
or refresh dossiers only when the user explicitly asks to update Choirboy
memory. The lifecycle script restores a shipped ready bundle when it still
matches the canonical sources; it does not generate dossier prose.

Do not reopen settled decisions without cause. If you propose a departure,
state what changed since the relevant research document.
'@
    $body = $body.Replace('__REGISTRATION_MARK__', $script:RegistrationMark)
    $body = $body.Replace('__PLUGIN_ROOT__', $script:PluginRoot)
    $body = $body.Replace('__ARTIFACT_GENERATOR__', $script:ArtifactGenerator)
    $body = $body.Replace('__PYTHON__', $pythonCommand)
    if ($Style -eq 'html') { return "<!-- $($script:Mark) START -->`n$($body.TrimEnd())`n<!-- $($script:Mark) END -->`n" }
    return "# >>> $($script:Mark) >>>`n$($body.TrimEnd())`n# <<< $($script:Mark) <<<`n"
}

function Write-InstructionBlock([string] $Path, [string] $Style, [string] $Label) {
    $start = if ($Style -eq 'html') { "<!-- $($script:Mark) START -->" } else { "# >>> $($script:Mark) >>>" }
    $end = if ($Style -eq 'html') { "<!-- $($script:Mark) END -->" } else { "# <<< $($script:Mark) <<<" }
    if ($script:Uninstall) {
        Write-Host "${Label}: removing instruction block from $Path"
        $status = Remove-ManagedBlock $Path $start $end
        if ($status -eq 'absent') { Write-Host '  no managed block — skipped' }
        else { Write-Host "  block removed from $Path" }
    } else {
        Write-Host "${Label}: installing instruction block into $Path"
        $status = Sync-ManagedBlock $Path $start $end (New-InstructionBlock $Style)
        if ($status -eq 'changed') { Write-Host "  block synchronized in $Path" }
        else { Write-Host '  block already current — skipped' }
    }
}

function Test-SkillLinkCurrent([string] $Destination) {
    if (-not (Test-Path -LiteralPath $Destination)) { return $false }
    try {
        $item = Get-Item -LiteralPath $Destination -Force
        if ($item.LinkType -notin @('SymbolicLink', 'Junction')) { return $false }
        $resolved = (Resolve-Path -LiteralPath $Destination).Path
        $source = (Resolve-Path -LiteralPath (Join-Path $script:PluginRoot 'skills/load-context')).Path
        return [IO.Path]::GetFullPath($resolved) -eq [IO.Path]::GetFullPath($source)
    } catch { return $false }
}

function Set-SkillLink([string] $Destination) {
    $source = Join-Path $script:PluginRoot 'skills/load-context'
    if ($script:Uninstall) {
        if (Test-SkillLinkCurrent $Destination) {
            Remove-Item -LiteralPath $Destination -Force
            Write-Host "  skill link removed: $Destination"
        } elseif (Test-Path -LiteralPath $Destination) {
            Write-Host "  skill at $Destination is not ours — left in place"
        } else { Write-Host '  skill link was not present' }
        return
    }
    $parent = Split-Path -Parent $Destination
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    if (Test-Path -LiteralPath $Destination) {
        if (-not (Test-SkillLinkCurrent $Destination)) {
            $sourceSkill = Join-Path $source 'SKILL.md'
            $destinationSkill = Join-Path $Destination 'SKILL.md'
            if (Test-Path -LiteralPath $destinationSkill -PathType Leaf) {
                Write-AtomicText $destinationSkill (Read-Text $sourceSkill) -Backup
                Write-Host "  skill updated: $destinationSkill"
            } else {
                Write-Host "  existing skill path has no SKILL.md; left in place: $Destination"
            }
            return
        }
    } else {
        try { New-Item -ItemType SymbolicLink -Path $Destination -Target $source | Out-Null }
        catch {
            if (-not $IsWindows) { throw }
            New-Item -ItemType Junction -Path $Destination -Target $source | Out-Null
        }
    }
    Write-Host "  skill linked: $Destination"
}

function Get-LlamaUiPath { return (Join-Path $script:HomePath '.config/llama.cpp/choirboy-ui.json') }

function Test-LlamaUiCurrent([string] $PromptPath) {
    $ui = Get-LlamaUiPath
    if (-not (Test-Path -LiteralPath $ui -PathType Leaf) -or -not (Test-Path -LiteralPath $PromptPath -PathType Leaf)) { return $false }
    try { $data = Read-JsonObject $ui 'llama UI config'; $promptText = Read-Text $PromptPath }
    catch { return $false }
    return ($data.systemMessage -is [string]) -and ($data.systemMessage -ceq $promptText) -and
        $promptText.Contains($script:Mark, [StringComparison]::Ordinal)
}

function Set-LlamaUi([string] $PromptPath, [string] $Mode) {
    $ui = Get-LlamaUiPath
    if (Test-Path -LiteralPath $ui -PathType Leaf) {
        $item = Get-Item -LiteralPath $ui -Force
        if ($item.LinkType -eq 'SymbolicLink') { Stop-Installer "refusing to replace symlinked llama UI config: $ui" }
    }
    $data = Read-JsonObject $ui 'llama UI config'
    $message = $data.systemMessage
    $ours = $message -is [string] -and $message.Contains($script:Mark, [StringComparison]::Ordinal)
    if ($Mode -eq 'uninstall') {
        if (-not $ours) { return 'unchanged' }
        $data.systemMessage = ''
    } else {
        $text = Read-Text $PromptPath
        if ($message -ceq $text -and $data.showSystemMessage -ceq $true) { return 'unchanged' }
        $data.systemMessage = $text
        $data.showSystemMessage = $true
    }
    Write-AtomicText $ui (ConvertTo-JsonText $data) -Backup:(Test-Path -LiteralPath $ui -PathType Leaf)
    return 'changed'
}

function Get-LifecycleLegacyRoots {
    $files = @(
        (Get-ClaudeSettingsPath),
        (Join-Path $script:HomePath '.codex/hooks.json'),
        (Join-Path $script:HomePath '.config/opencode/plugins/agent-plugin.ts'),
        (Join-Path $script:HomePath '.hermes/config.yaml'),
        (Join-Path $script:KimiHome 'config.toml'),
        (Join-Path $script:HomePath '.gemini/GEMINI.md'),
        (Join-Path $script:HomePath '.grok/AGENTS.md'),
        (Join-Path $script:HomePath '.pi/agent/APPEND_SYSTEM.md'),
        (Join-Path $script:HomePath '.omp/agent/AGENTS.md'),
        (Join-Path $script:HomePath '.config/llama.cpp/choirboy-system-prompt.md')
    ) + @($script:InstructionsFiles)
    $patterns = @(
        '(?<root>(?:[A-Za-z]:)?/[^"\r\n`]*?)/hooks/session-start[.](?:sh|ps1)',
        '(?<root>(?:[A-Za-z]:)?/[^"\r\n`]*?)/scripts/artifact-generator[.]py',
        '(?<root>(?:[A-Za-z]:)?/[^"\r\n`]*?)/prompt[.]md'
    )
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        $text = (Read-Text $file) -replace '\\+', '/'
        foreach ($pattern in $patterns) {
            foreach ($match in [regex]::Matches($text, $pattern)) {
                $root = $match.Groups['root'].Value.Trim()
                if ($IsWindows -and $root -match '^/([a-zA-Z])/(.*)$') { $root = "$($Matches[1].ToUpperInvariant()):/$($Matches[2])" }
                $candidate = "$root/artifacts"
                if ($seen.Add($candidate)) { $candidate }
            }
        }
    }
}

function Invoke-DoClaude {
    $file = Get-ClaudeSettingsPath
    $parent = Split-Path -Parent $file
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Write-AtomicText $file "{}`n" }
    if ($script:Uninstall) {
        Write-Host "claude: removing SessionStart/Stop hooks from $file"
        foreach ($spec in @(
            @{ Dot = 'hooks.SessionStart'; Script = $script:HookScript },
            @{ Dot = 'hooks.Stop'; Script = $script:StopHookScript }
        )) {
            $command = if ($IsWindows) { Get-HookCommand $spec.Script } else { 'bash' }
            $hookArgument = if ($IsWindows) { '' } else { Get-BashHookPath $spec.Script }
            $hookId = Get-HookId $spec.Script
            $status = Set-JsonHook $file $command 'uninstall' $spec.Dot $hookArgument 15 $null $hookId
            if ($status -eq 'changed') { Write-Host "  $($spec.Dot.Split('.')[-1]) removed" } else { Write-Host "  $($spec.Dot.Split('.')[-1]) was not registered" }
        }
    } else {
        Write-Host "claude: installing SessionStart/Stop hooks into $file"
        if (Test-FileContains $file @('choirboy-prompt@choirboy-prompt')) { [Console]::Error.WriteLine("  warning: marketplace plugin appears enabled in $file; manual hooks would run twice") }
        foreach ($spec in @(
            @{ Dot = 'hooks.SessionStart'; Script = $script:HookScript },
            @{ Dot = 'hooks.Stop'; Script = $script:StopHookScript }
        )) {
            $command = if ($IsWindows) { Get-HookCommand $spec.Script } else { 'bash' }
            $hookArgument = if ($IsWindows) { '' } else { Get-BashHookPath $spec.Script }
            $hookId = Get-HookId $spec.Script
            $status = Set-JsonHook $file $command 'install' $spec.Dot $hookArgument 15 $null $hookId
            $event = $spec.Dot.Split('.')[-1]
            if ($status -eq 'changed') { Write-Host "  $event installed" } else { Write-Host "  $event already registered — skipped" }
        }
    }
}

function Invoke-DoCodex {
    $file = Get-TargetPath 'codex'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $file)) | Out-Null
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Write-AtomicText $file "{}`n" }
    if ($script:Uninstall) {
        Write-Host "codex: removing SessionStart/Stop hooks from $file"
        $first = Set-JsonHook $file (Get-HookCommand $script:HookScript) 'uninstall' 'hooks.SessionStart' '' 15 $script:CodexContextLimit (Get-HookId $script:HookScript)
        $second = Set-JsonHook $file (Get-HookCommand $script:StopHookScript) 'uninstall' 'hooks.Stop' '' 15 $null (Get-HookId $script:StopHookScript)
        if ($first -eq 'changed') { Write-Host '  SessionStart removed' } else { Write-Host '  SessionStart was not registered' }
        if ($second -eq 'changed') { Write-Host '  Stop removed' } else { Write-Host '  Stop was not registered' }
    } else {
        Write-Host "codex: installing SessionStart/Stop hooks into $file"
        $config = Join-Path $script:HomePath '.codex/config.toml'
        if (Test-Path -LiteralPath $config -PathType Leaf) {
            if ((Read-Text $config) -match '(?m)^\s*hooks\s*=\s*false') { [Console]::Error.WriteLine('  warning: codex hooks are explicitly disabled in ~/.codex/config.toml') }
        }
        $first = Set-JsonHook $file (Get-HookCommand $script:HookScript) 'install' 'hooks.SessionStart' '' 15 $script:CodexContextLimit (Get-HookId $script:HookScript)
        $second = Set-JsonHook $file (Get-HookCommand $script:StopHookScript) 'install' 'hooks.Stop' '' 15 $null (Get-HookId $script:StopHookScript)
        if ($first -eq 'changed') { Write-Host "  SessionStart installed (additionalContextLimit=$($script:CodexContextLimit))" } else { Write-Host '  SessionStart already registered — skipped' }
        if ($second -eq 'changed') { Write-Host '  Stop installed' } else { Write-Host '  Stop already registered — skipped' }
    }
}

function Invoke-DoOpenCode {
    $file = Get-TargetPath 'opencode'
    if ($script:Uninstall) { Write-Host "opencode: removing model-context plugin from $file" }
    else { Write-Host "opencode: installing model-context plugin into $file" }
    $status = Set-ManagedWholeFile $file (New-OpenCodePlugin) $(if ($script:Uninstall) { 'uninstall' } else { 'install' }) 'plugin file'
    if ($script:Uninstall) {
        if ($status -eq 'changed') { Write-Host '  plugin removed (timestamped backup kept)' } else { Write-Host '  plugin was not installed' }
    } else {
        if ($status -eq 'changed') { Write-Host '  plugin installed (model-bound lore delivery)' } else { Write-Host '  plugin already installed — skipped' }
    }
}

function Invoke-DoHermes {
    $file = Get-TargetPath 'hermes'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $file)) | Out-Null
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Write-AtomicText $file '' }
    $start = "# >>> $($script:Mark) >>>"; $end = "# <<< $($script:Mark) <<<"
    if ($script:Uninstall) {
        Write-Host "hermes: removing pre_llm_call hook from $file"
        $status = Remove-ManagedBlock $file $start $end
        if ($status -eq 'absent') { Write-Host "  no managed block in $file — skipped" } else { Write-Host "  block removed from $file" }
        Set-HermesAllowlist 'uninstall' | Out-Null
        Write-Host '  consent allowlist entry removed'
        return
    }
    Write-Host "hermes: installing pre_llm_call hook into $file"
    if (-not (Test-FileContains $file @($start)) -and (Read-Text $file) -match '(?m)^hooks:') {
        Stop-Installer "hermes: $file already has a top-level 'hooks:' section — merge manually"
    }
    $cmd = Get-HookCommand $script:HookScript '--format hermes'
    $yamlCommand = $cmd.Replace('\', '\\').Replace('"', '\"')
    $block = @"
# >>> $($script:Mark) >>>
# $($script:RegistrationMark)
hooks:
  pre_llm_call:
    - command: "$yamlCommand"
      timeout: 15
# <<< $($script:Mark) <<<
"@
    $status = Sync-ManagedBlock $file $start $end $block
    if ($status -eq 'changed') { Write-Host "  block synchronized in $file" } else { Write-Host '  block already current — skipped' }
    Set-HermesAllowlist 'install' | Out-Null
    Write-Host "  consent allowlist entry added (pre_llm_call: $cmd)"
}

function Invoke-DoKimi {
    $file = Get-TargetPath 'kimi'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $file)) | Out-Null
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Write-AtomicText $file '' }
    $start = "# >>> $($script:Mark) >>>"; $end = "# <<< $($script:Mark) <<<"
    if ($script:Uninstall) {
        Write-Host "kimi: removing SessionStart/PreCompact/UserPromptSubmit/Stop hooks from $file"
        $status = Remove-ManagedBlock $file $start $end
        if ($status -eq 'absent') { Write-Host "  no managed block in $file — skipped" } else { Write-Host "  block removed from $file" }
        return
    }
    Write-Host "kimi: installing SessionStart/PreCompact/UserPromptSubmit/Stop hooks into $file"
    if (-not (Test-FileContains $file @($start)) -and (Read-Text $file) -match '(?m)^hooks\s*=') {
        Stop-Installer "kimi: $file already defines 'hooks =' — switch it to [[hooks]] entries or merge manually"
    }
    $status = Sync-ManagedBlock $file $start $end (Get-KimiBlock)
    if ($status -eq 'changed') { Write-Host "  block synchronized in $file" } else { Write-Host '  block already current — skipped' }
}

function Invoke-DoPi {
    $path = Get-TargetPath 'pi'
    Write-InstructionBlock $path 'html' 'pi'
    Set-SkillLink (Join-Path $script:HomePath '.pi/agent/skills/load-context')
}

function Invoke-DoOmp {
    $path = Get-TargetPath 'omp'
    Write-InstructionBlock $path 'html' 'omp'
    Set-SkillLink (Join-Path $script:HomePath '.omp/agent/skills/load-context')
}

function Invoke-DoLlama {
    $prompt = Get-TargetPath 'llama'
    Write-InstructionBlock $prompt 'html' 'llama'
    Set-SkillLink (Join-Path $script:HomePath '.config/llama.cpp/skills/load-context')
    if ($script:Uninstall) {
        Write-Host "llama: clearing choirboy system message in $(Get-LlamaUiPath)"
        Set-LlamaUi $prompt 'uninstall' | Out-Null
    } else {
        Write-Host "llama: writing UI default system message to $(Get-LlamaUiPath)"
        $status = Set-LlamaUi $prompt 'install'
        if ($status -eq 'changed') { Write-Host '  UI config updated' } else { Write-Host '  UI config already current — skipped' }
        Write-Host "  next: start llama-server with --ui-config-file $(Get-LlamaUiPath)"
    }
}

function Invoke-DoGemini { Write-InstructionBlock (Get-TargetPath 'gemini') 'html' 'gemini' }
function Invoke-DoGrok { Write-InstructionBlock (Get-TargetPath 'grok') 'html' 'grok' }

function Invoke-DoGrokBot {
    $path = Get-TargetPath 'grokbot'
    $legacy = Join-Path $script:HomePath '.grokbot/AGENTS.md'
    $legacyStart = "<!-- $($script:Mark) START -->"
    $legacyEnd = "<!-- $($script:Mark) END -->"
    if (Test-FileContains $legacy @("<!-- $($script:Mark) START -->")) {
        Write-Host "grokbot: removing legacy instruction block from $legacy"
        $legacyStatus = Remove-ManagedBlock $legacy $legacyStart $legacyEnd
        if ($legacyStatus -eq 'changed') { Write-Host "  block removed from $legacy" }
    }
    if ($script:Uninstall) { Write-Host "grokbot: removing prepared workflow from $path" }
    else { Write-Host "grokbot: preparing importable workflow at $path" }
    $status = Set-ManagedWholeFile $path (New-GrokBotWorkflow) $(if ($script:Uninstall) { 'uninstall' } else { 'install' }) 'workflow'
    if ($script:Uninstall) {
        if ($status -eq 'changed') { Write-Host '  prepared workflow removed (delete an already imported workflow in Grok Bot manually)' }
        else { Write-Host '  prepared workflow was not present' }
    } else {
        if ($status -eq 'changed') { Write-Host '  workflow prepared' } else { Write-Host '  workflow already current — skipped' }
        Write-Host '  next: import/link this SKILL.md in Grok Bot Workflows, then run @choirboy-context in each new chat'
    }
}

function Invoke-Target([string] $Target) {
    switch ($Target) {
        'claude' { Invoke-DoClaude }
        'codex' { Invoke-DoCodex }
        'opencode' { Invoke-DoOpenCode }
        'hermes' { Invoke-DoHermes }
        'kimi' { Invoke-DoKimi }
        'gemini' { Invoke-DoGemini }
        'grok' { Invoke-DoGrok }
        'grokbot' { Invoke-DoGrokBot }
        'pi' { Invoke-DoPi }
        'omp' { Invoke-DoOmp }
        'llama' { Invoke-DoLlama }
        default { Stop-Installer "unknown target: $Target (known: $($script:AllTargets -join ','))" }
    }
}

function Show-TargetList {
    '{0,-8} {1,-10} {2}' -f 'TARGET', 'STATUS', 'LOCATION'
    foreach ($target in $script:Targets) {
        $status = Get-TargetStatus $target
        $location = if ($status -eq 'absent') { '-' } else { Get-TargetPath $target }
        '{0,-8} {1,-10} {2}' -f $target, $status, $location
    }
}

function Parse-InstallerArguments {
    for ($i = 0; $i -lt $script:CliArgs.Count; $i++) {
        $arg = [string]$script:CliArgs[$i]
        switch ($arg) {
            '--target' {
                if ($i + 1 -ge $script:CliArgs.Count) { Stop-Installer '--target requires a comma-separated list' }
                $script:TargetSpec = [string]$script:CliArgs[++$i]
            }
            '--uninstall' { $script:Uninstall = $true }
            '--list' { $script:ListOnly = $true }
            '--instructions' {
                if ($i + 1 -ge $script:CliArgs.Count) { Stop-Installer '--instructions requires a path' }
                $script:InstructionsFiles.Add((Resolve-UserPath ([string]$script:CliArgs[++$i])))
            }
            '--project' { $script:Scope = 'project' }
            '--settings' {
                if ($i + 1 -ge $script:CliArgs.Count) { Stop-Installer '--settings requires a path' }
                $script:SettingsFile = [string]$script:CliArgs[++$i]
            }
            { $_ -in '-h', '--help' } { Write-Usage; exit 0 }
            default { Write-Usage; Stop-Installer "unknown argument: $arg" }
        }
    }
    if ($script:TargetSpec) {
        if ($script:TargetSpec -eq 'none') { $script:Targets = @() }
        else { $script:Targets = @($script:TargetSpec -split '[,\s]+' | Where-Object { $_ }) }
    } elseif ($script:SettingsFile -or $script:Scope -eq 'project') {
        $script:Targets = @('claude')
    } else {
        $script:Targets = @($script:AllTargets | Where-Object { Test-TargetPresent $_ })
    }
    foreach ($target in $script:Targets) {
        if ($target -notin $script:AllTargets) { Stop-Installer "unknown target: $target (known: $($script:AllTargets -join ','))" }
    }
}

function Invoke-InstallerMain {
    if ($PSVersionTable.PSVersion.Major -lt 7) { Stop-Installer 'PowerShell 7 or newer is required.' }
    if (-not $script:PluginRoot -or -not (Test-Path -LiteralPath $script:PluginRoot -PathType Container)) {
        Stop-Installer 'run install.ps1 from a repository checkout.'
    }
    Resolve-Python
    Parse-InstallerArguments

    if (-not $script:Uninstall -and -not $script:ListOnly -and (Test-Path -LiteralPath $script:BuildContext -PathType Leaf)) {
        Invoke-Python @($script:BuildContext) | Out-Null
    }
    if ($script:ListOnly) { Show-TargetList; return }
    if ($script:Targets.Count -eq 0 -and $script:InstructionsFiles.Count -eq 0) {
        Stop-Installer 'no agent runtimes detected; use --target or --instructions'
    }

    if (-not $script:Uninstall) {
        if (-not (Test-Path -LiteralPath $script:ArtifactGenerator -PathType Leaf)) {
            Stop-Installer "artifact lifecycle is missing: $($script:ArtifactGenerator)"
        }
        $arguments = [Collections.Generic.List[string]]::new()
        $arguments.Add($script:ArtifactGenerator)
        $arguments.Add('prepare')
        $arguments.Add('--migrate-from')
        $arguments.Add((Join-Path $script:PluginRoot 'artifacts'))
        foreach ($root in @(Get-LifecycleLegacyRoots)) {
            if ($root) { $arguments.Add('--migrate-from'); $arguments.Add([string]$root) }
        }
        $artifactStatus = Invoke-Python $arguments.ToArray()
        Write-Host "agent-plugin: artifact lifecycle prepared — $($artifactStatus -join ' ')"
    }

    foreach ($target in $script:Targets) { Invoke-Target $target }
    foreach ($file in $script:InstructionsFiles) {
        $style = if ($file -match '(?i)\.(md|markdown)$') { 'html' } else { 'hash' }
        Write-InstructionBlock $file $style "file:$file"
    }
    if ($script:Uninstall) { Write-Host 'agent-plugin: uninstall complete' }
    else { Write-Host 'agent-plugin: install complete — the next agent session will author or load project artifacts' }
}

try {
    Invoke-InstallerMain
} catch {
    [Console]::Error.WriteLine("install.ps1: $($_.Exception.Message)")
    exit 1
}
