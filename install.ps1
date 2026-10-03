<#
Windows entry point for the Choirboy Prompt installer.

Runs under any PowerShell edition, including the Windows PowerShell 5.1 that
ships with Windows. When PowerShell 7 is missing it installs it automatically
(winget first, then the Microsoft-signed MSI from the PowerShell GitHub
releases) and runs scripts/install-core.ps1 under pwsh.

Keep this file ASCII-only and free of PowerShell 7 syntax: Windows PowerShell
reads BOM-less scripts in the ANSI code page and parses the whole file before
running it.

Usage: powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
       [--target claude,codex] [--uninstall] [--list] [--instructions FILE]
       [--project] [--settings PATH]
#>

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$coreScript = Join-Path (Join-Path $scriptDirectory 'scripts') 'install-core.ps1'
$manualInstallUrl = 'https://learn.microsoft.com/powershell/scripting/install/install-powershell-on-windows'

function Write-Step([string] $Message) {
    Write-Host "install.ps1: $Message"
}

function Get-PowerShellMajorVersion([string] $Path) {
    try {
        $output = & $Path -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.Major'
        $major = 0
        if ([int]::TryParse(([string]($output | Select-Object -Last 1)).Trim(), [ref] $major)) { return $major }
    } catch { }
    return 0
}

function Get-PathPwsh {
    $command = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Path }
    return $null
}

function Find-Pwsh7 {
    $candidates = @(Get-PathPwsh)
    foreach ($root in @($env:ProgramFiles, $env:ProgramW6432)) {
        if ($root) { $candidates += Join-Path $root 'PowerShell\7\pwsh.exe' }
    }
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe' }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Get-PowerShellMajorVersion $candidate) -ge 7) { return $candidate }
    }
    return $null
}

# A fresh install updates PATH in the registry, not in this running process.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($env:Path, $machine, $user) | Where-Object { $_ }) -join ';'
}

function Install-PwshWithWinget {
    $winget = Get-Command -Name 'winget' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $winget) {
        Write-Step 'winget is not available'
        return
    }
    Write-Step 'installing PowerShell 7 with winget (Microsoft.PowerShell)'
    & $winget.Path install --id Microsoft.PowerShell --exact --source winget --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { Write-Step "winget exited with code $LASTEXITCODE" }
}

function Get-WindowsArchitecture {
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    switch ($architecture) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        'x86' { return 'x86' }
    }
    return $null
}

function Get-FileSha256([string] $Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToLowerInvariant()
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

function Install-PwshWithMsi {
    $architecture = Get-WindowsArchitecture
    if (-not $architecture) { throw "unsupported processor architecture: $env:PROCESSOR_ARCHITECTURE" }

    # Windows PowerShell 5.1 may still default to TLS 1.0; GitHub requires TLS 1.2.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]3072
    $client = New-Object Net.WebClient
    $client.Headers.Add('User-Agent', 'choirboy-prompt-installer')
    $releases = $client.DownloadString('https://api.github.com/repos/PowerShell/PowerShell/releases?per_page=30') | ConvertFrom-Json

    $pattern = '^PowerShell-\d+\.\d+\.\d+-win-' + $architecture + '\.msi$'
    $asset = $null
    foreach ($release in $releases) {
        if ($release.draft -or $release.prerelease) { continue }
        $asset = $release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
        if ($asset) { break }
    }
    if (-not $asset) { throw "no stable PowerShell 7 MSI for win-$architecture in recent releases" }

    $msi = Join-Path ([IO.Path]::GetTempPath()) $asset.name
    Write-Step "downloading $($asset.name) from GitHub"
    $client.DownloadFile($asset.browser_download_url, $msi)
    try {
        if ($asset.digest) {
            $expected = ([string]$asset.digest -replace '^sha256:', '').ToLowerInvariant()
            if ((Get-FileSha256 $msi) -ne $expected) { throw "checksum mismatch for $($asset.name)" }
        }
        $signature = Get-AuthenticodeSignature -FilePath $msi
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            throw "$($asset.name) is not signed by Microsoft"
        }
        Write-Step 'installing PowerShell 7 from the MSI; confirm the Windows administrator prompt'
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/package', ('"' + $msi + '"'), '/passive', 'ADD_PATH=1') -Verb RunAs -Wait -PassThru
        # 3010: installed, a reboot is requested.
        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) { throw "msiexec exited with code $($process.ExitCode)" }
    } finally {
        Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
    }
}

try {
    if (-not (Test-Path -LiteralPath $coreScript -PathType Leaf)) { throw 'run install.ps1 from a repository checkout.' }
    $onWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $pwsh = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    } elseif (-not $onWindows) {
        throw 'PowerShell 7 or newer is required; on Linux and macOS use ./install.sh.'
    } else {
        $pwsh = Find-Pwsh7
        if (-not $pwsh) {
            Write-Step "PowerShell 7 is not installed (running PowerShell $($PSVersionTable.PSVersion)); installing it automatically"
            Install-PwshWithWinget
            Update-SessionPath
            $pwsh = Find-Pwsh7
            if (-not $pwsh) {
                try { Install-PwshWithMsi } catch { Write-Step "MSI installation failed: $($_.Exception.Message)" }
                Update-SessionPath
                $pwsh = Find-Pwsh7
            }
            if (-not $pwsh) {
                throw "PowerShell 7 could not be installed automatically. Install it manually ($manualInstallUrl) and run this command again."
            }
            Write-Step "PowerShell 7 installed: $pwsh"
            Write-Step 'restart open terminals and agent apps after setup so their hooks can find pwsh'
        }
        # Registered hooks start "pwsh" from PATH, not this resolved path.
        $pathPwsh = Get-PathPwsh
        if (-not $pathPwsh -or (Get-PowerShellMajorVersion $pathPwsh) -lt 7) {
            Write-Warning 'agent hooks run "pwsh" from PATH, which does not resolve to PowerShell 7 yet. Check PATH, then restart terminals and agent apps.'
        }
    }

    $pwshArguments = @('-NoProfile')
    if ($onWindows) { $pwshArguments += @('-ExecutionPolicy', 'Bypass') }
    $pwshArguments += @('-File', $coreScript)
    & $pwsh @pwshArguments @args
    exit $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine("install.ps1: $($_.Exception.Message)")
    exit 1
}
