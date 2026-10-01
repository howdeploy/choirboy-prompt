#Requires -Version 7.0
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw 'This check requires Windows.' }

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-Number($Actual, [int] $Expected, [string] $Message) {
    Assert-Condition ($Actual -is [int] -or $Actual -is [long]) "$Message is not a JSON number"
    Assert-Condition ($Actual -eq $Expected) "$Message is $Actual instead of $Expected"
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temporaryRoot = Join-Path $temporaryParent ('choirboy-powershell-check-' + [guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $temporaryRoot 'checkout'
$savedSearchPath = $env:PATH
$createdLinks = [Collections.Generic.List[string]]::new()

try {
    foreach ($relative in @(
        'install.ps1',
        'hooks/powershell-common.ps1',
        'hooks/session-start.ps1',
        'hooks/artifact-stop.ps1',
        'skills/load-context/SKILL.md'
    )) {
        $source = Join-Path $repositoryRoot $relative
        $destination = Join-Path $fixtureRoot $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }

    $installer = Join-Path $fixtureRoot 'install.ps1'
    . $installer '--target' 'none' '--list'

    # Codex hook values must be numeric, and a null legacy value must be stale.
    $script:HomePath = Join-Path $temporaryRoot 'codex-home'
    Invoke-DoCodex
    $codexSettings = Join-Path $script:HomePath '.codex/hooks.json'
    $data = Get-Content -LiteralPath $codexSettings -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    Assert-Number $data.hooks.SessionStart[0].hooks[0].timeout 15 'Codex SessionStart timeout'
    Assert-Number $data.hooks.SessionStart[0].hooks[0].additionalContextLimit 4000 'Codex context limit'
    Assert-Number $data.hooks.Stop[0].hooks[0].timeout 15 'Codex Stop timeout'
    Assert-Condition (Test-TargetInstalled 'codex') 'Fresh Codex hooks are not reported installed'

    $data.hooks.SessionStart[0].hooks[0].timeout = $null
    $data.hooks.SessionStart[0].hooks[0].additionalContextLimit = $null
    [IO.File]::WriteAllText($codexSettings, ($data | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    Assert-Condition (-not (Test-TargetInstalled 'codex')) 'Null Codex hook values were accepted as current'
    Invoke-DoCodex
    $data = Get-Content -LiteralPath $codexSettings -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    Assert-Number $data.hooks.SessionStart[0].hooks[0].timeout 15 'Refreshed Codex timeout'
    Assert-Number $data.hooks.SessionStart[0].hooks[0].additionalContextLimit 4000 'Refreshed Codex context limit'

    $script:HomePath = Join-Path $temporaryRoot 'claude-home'
    Invoke-DoClaude
    $claudeSettings = Join-Path $script:HomePath '.claude/settings.json'
    $data = Get-Content -LiteralPath $claudeSettings -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    Assert-Number $data.hooks.SessionStart[0].hooks[0].timeout 15 'Claude SessionStart timeout'
    Assert-Number $data.hooks.Stop[0].hooks[0].timeout 15 'Claude Stop timeout'
    Assert-Condition (Test-TargetInstalled 'claude') 'Fresh Claude hooks are not reported installed'

    # Existing unrelated skill directories and junctions must remain untouched.
    $script:HomePath = Join-Path $temporaryRoot 'foreign-home'
    $foreignDirectory = Join-Path $script:HomePath '.pi/agent/skills/load-context'
    [IO.Directory]::CreateDirectory($foreignDirectory) | Out-Null
    $foreignSkill = Join-Path $foreignDirectory 'SKILL.md'
    [IO.File]::WriteAllText($foreignSkill, 'unrelated skill')
    $refused = $false
    try { Set-SkillLink $foreignDirectory } catch { $refused = $true }
    Assert-Condition $refused 'An unrelated skill directory was accepted'
    Assert-Condition ((Get-Content -LiteralPath $foreignSkill -Raw) -eq 'unrelated skill') 'An unrelated skill directory was overwritten'

    $foreignTarget = Join-Path $temporaryRoot 'foreign-target'
    [IO.Directory]::CreateDirectory($foreignTarget) | Out-Null
    $foreignTargetSkill = Join-Path $foreignTarget 'SKILL.md'
    [IO.File]::WriteAllText($foreignTargetSkill, 'linked unrelated skill')
    $foreignLink = Join-Path $script:HomePath '.omp/agent/skills/load-context'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $foreignLink)) | Out-Null
    New-Item -ItemType Junction -Path $foreignLink -Target $foreignTarget | Out-Null
    $createdLinks.Add($foreignLink)
    $refused = $false
    try { Set-SkillLink $foreignLink } catch { $refused = $true }
    Assert-Condition $refused 'An unrelated skill junction was accepted'
    Assert-Condition ((Get-Content -LiteralPath $foreignTargetSkill -Raw) -eq 'linked unrelated skill') 'An unrelated junction target was overwritten'
    $script:Uninstall = $true
    Set-SkillLink $foreignLink
    $script:Uninstall = $false
    Assert-Condition (Test-Path -LiteralPath $foreignLink) 'Uninstall removed an unrelated junction'

    # A link created by the installer must report current and be removable.
    $script:HomePath = Join-Path $temporaryRoot 'owned-home'
    Invoke-DoPi
    $ownedLink = Join-Path $script:HomePath '.pi/agent/skills/load-context'
    $createdLinks.Add($ownedLink)
    Assert-Condition (Test-SkillLinkCurrent $ownedLink) 'Fresh skill link is not recognized as owned'
    Assert-Condition (Test-TargetInstalled 'pi') 'Pi install is not reported installed'
    $script:Uninstall = $true
    Invoke-DoPi
    $script:Uninstall = $false
    Assert-Condition (-not (Test-Path -LiteralPath $ownedLink)) 'Uninstall left the owned skill link in place'

    # A symbolic link must also be recognized when the runner permits one.
    $symbolicLinkCreated = $false
    try {
        New-Item -ItemType SymbolicLink -Path $ownedLink -Target (Join-Path $fixtureRoot 'skills/load-context') -ErrorAction Stop | Out-Null
        $symbolicLinkCreated = $true
    } catch {
        Write-Host "Symbolic link check unavailable: $($_.Exception.Message)"
    }
    if ($symbolicLinkCreated) {
        Assert-Condition (Test-SkillLinkCurrent $ownedLink) 'Owned symbolic link is not recognized'
        $script:Uninstall = $true
        Set-SkillLink $ownedLink
        $script:Uninstall = $false
        Assert-Condition (-not (Test-Path -LiteralPath $ownedLink)) 'Uninstall left the owned symbolic link in place'
    }

    # Check a junction explicitly even when the installer could create a symlink.
    New-Item -ItemType Junction -Path $ownedLink -Target (Join-Path $fixtureRoot 'skills/load-context') | Out-Null
    Assert-Condition (Test-SkillLinkCurrent $ownedLink) 'Owned junction is not recognized'
    $script:Uninstall = $true
    Set-SkillLink $ownedLink
    $script:Uninstall = $false
    Assert-Condition (-not (Test-Path -LiteralPath $ownedLink)) 'Uninstall left the owned junction in place'

    # A failing python3 application must fall through to the working python.exe.
    $workingPython = (Get-Command -Name python -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    & $workingPython -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' *> $null
    Assert-Condition ($LASTEXITCODE -eq 0) 'The check requires a working Python 3 installation'
    $aliasDirectory = Join-Path $temporaryRoot 'python-alias'
    [IO.Directory]::CreateDirectory($aliasDirectory) | Out-Null
    $failingAlias = Join-Path $aliasDirectory 'python3.exe'
    [IO.File]::WriteAllBytes($failingAlias, [byte[]]@(0))
    $env:PATH = $aliasDirectory + [IO.Path]::PathSeparator + $savedSearchPath
    $firstCandidate = (Get-Command -Name python3 -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    Assert-Condition ([string]::Equals($firstCandidate, $failingAlias, [StringComparison]::OrdinalIgnoreCase)) 'The failing python3 alias did not take precedence'
    Resolve-Python
    Assert-Condition ([string]::Equals($script:PythonExe, $workingPython, [StringComparison]::OrdinalIgnoreCase)) 'Installer did not fall back to working Python'
    . (Join-Path $fixtureRoot 'hooks/powershell-common.ps1')
    $hookPython = Get-ChoirboyPython
    Assert-Condition ([string]::Equals($hookPython.Executable, $workingPython, [StringComparison]::OrdinalIgnoreCase)) 'Hook did not fall back to working Python'

    Write-Host 'PowerShell installer review checks passed.'
} finally {
    $env:PATH = $savedSearchPath
    foreach ($link in $createdLinks) {
        $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and $item.LinkType -in @('SymbolicLink', 'Junction')) {
            Remove-Item -LiteralPath $link -Force
        }
    }
    $resolvedRoot = [IO.Path]::GetFullPath($temporaryRoot)
    $expectedParent = [IO.Path]::GetFullPath($temporaryParent).TrimEnd([char[]]@('\', '/'))
    Assert-Condition ([string]::Equals((Split-Path -Parent $resolvedRoot), $expectedParent, [StringComparison]::OrdinalIgnoreCase)) 'Refusing to clean an unexpected path'
    if (Test-Path -LiteralPath $resolvedRoot) { Remove-Item -LiteralPath $resolvedRoot -Recurse -Force }
}
