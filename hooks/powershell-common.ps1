# Shared helpers for the native PowerShell runtime hooks.

function Test-ChoirboyPython3Candidate([string] $Executable, [string[]] $Prefix) {
    try {
        & $Executable @Prefix -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' *> $null
        return $LASTEXITCODE -eq 0
    } catch { return $false }
}

function Get-ChoirboyPython {
    foreach ($name in @('python3', 'python', 'py')) {
        $command = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            $prefix = if ($name -eq 'py') { @('-3') } else { @() }
            if (-not (Test-ChoirboyPython3Candidate $command.Source $prefix)) { continue }
            return [pscustomobject]@{
                Executable = $command.Source
                Prefix = $prefix
            }
        }
    }
    return $null
}

function Invoke-ChoirboyPython([string] $Generator, [string[]] $Arguments) {
    $python = Get-ChoirboyPython
    if ($null -eq $python) { throw 'Python 3 is not available.' }
    $argv = @()
    if ($python.Prefix.Count -gt 0) { $argv += $python.Prefix }
    $argv += $Generator
    $argv += $Arguments
    $output = & $python.Executable @argv
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output) -join "`n" }
}

function Get-ChoirboySha256([string] $Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([Convert]::ToHexString($sha.ComputeHash($bytes))).ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Write-ChoirboyAtomicText([string] $Path, [string] $Text) {
    $parent = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporary = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.tmp.' + [guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($temporary, $Text, [Text.UTF8Encoding]::new($false))
    try {
        if ([IO.File]::Exists($Path)) {
            try { [IO.File]::Replace($temporary, $Path, $null) }
            catch { [IO.File]::Move($temporary, $Path, $true) }
        } else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}
