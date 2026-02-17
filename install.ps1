#Requires -Version 5.1
<#
.SYNOPSIS
    scan-repo Windows Installer

.DESCRIPTION
    Installs scan-repo and all prerequisite security scanning tools on Windows
    by setting up WSL 2 (Windows Subsystem for Linux) with Ubuntu, then running
    the Linux installer inside it.

    scan-repo is a bash script and runs natively inside WSL. After this script
    completes you use scan-repo from a WSL terminal, or call it from PowerShell
    via the `wsl` command.

.PARAMETER SkipWslInstall
    Skip WSL installation (use if WSL/Ubuntu is already set up).

.PARAMETER WslDistro
    WSL distribution name to use/install. Default: Ubuntu

.PARAMETER AssumeYes
    Pass --yes to the bash installer to skip confirmation prompts.

.PARAMETER InstallPrefix
    Directory inside WSL to install binaries. Default: /usr/local/bin

.EXAMPLE
    # Full installation (run in an elevated PowerShell)
    .\install.ps1

.EXAMPLE
    # Assume yes, skip WSL setup (WSL already installed)
    .\install.ps1 -SkipWslInstall -AssumeYes

.NOTES
    Requires:
      - Windows 10 version 2004+ (build 19041+) or Windows 11
      - PowerShell 5.1 or later
      - Internet connection

    Run this script in an elevated (Administrator) PowerShell session.
#>

[CmdletBinding()]
param(
    [switch]$SkipWslInstall,
    [string]$WslDistro = "Ubuntu",
    [switch]$AssumeYes,
    [string]$InstallPrefix = "/usr/local/bin"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Colors ────────────────────────────────────────────────────────────────────

function Write-Header  { Write-Host "`n$args" -ForegroundColor Cyan }
function Write-Ok      { Write-Host "  [OK]    $args" -ForegroundColor Green }
function Write-Info    { Write-Host "  [INFO]  $args" -ForegroundColor Blue }
function Write-Warn    { Write-Host "  [WARN]  $args" -ForegroundColor Yellow }
function Write-Fail    { Write-Host "  [ERROR] $args" -ForegroundColor Red }

# ── Prerequisite checks ───────────────────────────────────────────────────────

function Test-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal] $identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-WindowsVersion {
    $build = [System.Environment]::OSVersion.Version.Build
    if ($build -lt 19041) {
        Write-Fail "WSL 2 requires Windows 10 build 19041 or later (you have build $build)."
        Write-Fail "Please update Windows and try again."
        exit 1
    }
}

function Assert-Admin {
    if (-not (Test-Admin)) {
        Write-Fail "This script must be run as Administrator."
        Write-Info "Right-click PowerShell → 'Run as Administrator', then re-run:"
        Write-Info "  .\install.ps1"
        exit 1
    }
}

# ── WSL helpers ───────────────────────────────────────────────────────────────

function Get-WslStatus {
    <# Returns $true if WSL is available and the target distro is installed #>
    $wslExe = "$env:SystemRoot\System32\wsl.exe"
    if (-not (Test-Path $wslExe)) { return $false }

    $installed = & wsl --list --quiet 2>$null | Where-Object { $_ -match $WslDistro }
    return ($null -ne $installed -and $installed -ne "")
}

function Install-Wsl {
    Write-Header "Installing WSL 2 with $WslDistro"

    # Enable WSL and Virtual Machine Platform features
    Write-Info "Enabling Windows features (WSL, VirtualMachinePlatform)..."
    $features = @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")
    foreach ($feature in $features) {
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature).State
        if ($state -ne "Enabled") {
            Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -All | Out-Null
            Write-Ok "Enabled $feature"
        } else {
            Write-Info "$feature already enabled"
        }
    }

    # Set WSL 2 as default
    Write-Info "Setting WSL 2 as default..."
    & wsl --set-default-version 2 2>&1 | Out-Null

    # Update the WSL kernel
    Write-Info "Updating WSL kernel..."
    & wsl --update 2>&1 | Out-Null

    # Install the chosen distro
    Write-Info "Installing $WslDistro from the Microsoft Store (this may take a few minutes)..."
    & wsl --install --distribution $WslDistro --no-launch 2>&1 | Out-Null

    Write-Ok "WSL installation initiated."
    Write-Warn "A system restart may be required before the first WSL launch."
    Write-Info "After restarting, re-run: .\install.ps1 -SkipWslInstall"

    $restart = Read-Host "Restart now? [y/N]"
    if ($restart -match "^[Yy]$") {
        Restart-Computer -Force
    } else {
        Write-Warn "Please restart manually, then re-run the installer."
        exit 0
    }
}

function Start-WslDistro {
    <# First boot of a freshly installed distro to complete Ubuntu setup #>
    Write-Info "Initialising $WslDistro (first launch may take a minute)..."
    & wsl --distribution $WslDistro --user root -- echo "WSL ready" 2>&1 | Out-Null
}

# ── Install tools inside WSL ─────────────────────────────────────────────────

function Install-ScanRepoInWsl {
    Write-Header "Running scan-repo installer inside WSL ($WslDistro)"

    # Resolve the directory containing this script, then find install.sh / scan-repo
    $scriptDir   = Split-Path -Parent $MyInvocation.PSCommandPath
    $installSh   = Join-Path $scriptDir "install.sh"
    $scanRepoSh  = Join-Path $scriptDir "scan-repo"

    if (-not (Test-Path $installSh)) {
        Write-Fail "install.sh not found at: $installSh"
        Write-Fail "Make sure install.ps1, install.sh, and scan-repo are in the same directory."
        exit 1
    }

    # Convert Windows paths to WSL paths (e.g. C:\Users\... → /mnt/c/Users/...)
    $wslInstallSh  = & wsl --distribution $WslDistro -- wslpath -u $installSh.Replace("\", "/")
    $wslInstallSh  = $wslInstallSh.Trim()

    # Build argument list for the bash installer
    $bashArgs = "--prefix `"$InstallPrefix`""
    if ($AssumeYes)         { $bashArgs += " --yes" }

    Write-Info "Executing: bash $wslInstallSh $bashArgs"
    Write-Info ""

    & wsl --distribution $WslDistro --user root -- bash $wslInstallSh $bashArgs.Split(" ")

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Installer exited with code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}

# ── Post-install guidance ─────────────────────────────────────────────────────

function Show-NextSteps {
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  Installation complete!" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Open a WSL terminal and run:" -ForegroundColor Cyan
    Write-Host "    cd /mnt/c/path/to/your/repo"
    Write-Host "    scan-repo --markdown"
    Write-Host ""
    Write-Host "  From PowerShell (pass args after --):" -ForegroundColor Cyan
    Write-Host "    wsl -- scan-repo --markdown --all-formats /mnt/c/path/to/repo"
    Write-Host ""
    Write-Host "  See all options:" -ForegroundColor Cyan
    Write-Host "    wsl -- scan-repo --help"
    Write-Host ""
    Write-Host "  Tip: Windows drives are mounted at /mnt/<drive-letter>/" -ForegroundColor Yellow
    Write-Host "  Example: C:\Users\you\project → /mnt/c/Users/you/project" -ForegroundColor Yellow
    Write-Host ""
}

# ── Main ─────────────────────────────────────────────────────────────────────

function Main {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         scan-repo  ·  Windows Installer (via WSL)         ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    Assert-Admin
    Assert-WindowsVersion

    $wslReady = Get-WslStatus

    if (-not $SkipWslInstall -and -not $wslReady) {
        Write-Info "WSL / $WslDistro not detected. Installing now..."
        Install-Wsl
        Start-WslDistro
    } elseif ($wslReady) {
        Write-Ok "WSL with $WslDistro is already installed."
    } else {
        Write-Info "Skipping WSL install (-SkipWslInstall). Using existing WSL distribution."
    }

    Install-ScanRepoInWsl
    Show-NextSteps
}

Main
