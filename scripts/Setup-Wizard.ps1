<#
.SYNOPSIS
    BlueShift Setup Wizard - Guided installation and configuration tool

.DESCRIPTION
    This script provides a guided setup process for the BlueShift migration tool,
    including dependency installation, configuration, and system preparation.

.NOTES
    Author: BlueShift Team
    Requires: Administrator privileges
    Version: 1.0.0
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

param()

Write-Host "BlueShift Setup Wizard" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan
Write-Host ""

# Check administrator privileges
Write-Host "Checking administrator privileges..." -ForegroundColor Yellow
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Administrator privileges required. Please run as administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ Administrator privileges confirmed" -ForegroundColor Green

# Set execution policy
Write-Host "Setting PowerShell execution policy..." -ForegroundColor Yellow
try {
    $currentPolicy = Get-ExecutionPolicy
    if ($currentPolicy -eq "Restricted" -or $currentPolicy -eq "AllSigned") {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Host "✓ Execution policy set to RemoteSigned" -ForegroundColor Green
    } else {
        Write-Host "✓ Execution policy already allows script execution ($currentPolicy)" -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not set execution policy: $($_.Exception.Message)"
}

# Install required modules
Write-Host "Installing required PowerShell modules..." -ForegroundColor Yellow
$modules = @("PS2EXE")
foreach ($module in $modules) {
    try {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            Write-Host "Installing $module module..." -ForegroundColor Gray
            Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
            Write-Host "✓ $module module installed" -ForegroundColor Green
        } else {
            Write-Host "✓ $module module already installed" -ForegroundColor Green
        }
    } catch {
        Write-Warning "Could not install $module module: $($_.Exception.Message)"
    }
}

# Configure environment variables
Write-Host "Setting up environment variables..." -ForegroundColor Yellow
$adminPass = Read-Host "Temporary admin password for domain leave (required)" -AsSecureString
$adminPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPass))
[Environment]::SetEnvironmentVariable("MIGADMIN_PASS", $adminPass, "User")
Write-Host "✓ MIGADMIN_PASS environment variable set" -ForegroundColor Green

# Create shortcuts
Write-Host "Creating shortcuts..." -ForegroundColor Yellow
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Parent $scriptPath
$mainScript = Join-Path $scriptDir "Start-Migration.ps1"
$desktopPath = [Environment]::GetFolderPath("Desktop")
$startMenuPath = Join-Path ([Environment]::GetFolderPath("StartMenu")) "Programs\BlueShift"

# Create Start Menu folder
if (-not (Test-Path $startMenuPath)) {
    New-Item -ItemType Directory -Path $startMenuPath -Force | Out-Null
}

# Create desktop shortcut
try {
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut((Join-Path $desktopPath "BlueShift Migration.lnk"))
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$mainScript`""
    $Shortcut.WorkingDirectory = $scriptDir
    $Shortcut.IconLocation = "powershell.exe,0"
    $Shortcut.Description = "BlueShift - Windows Migration to Azure AD"
    $Shortcut.Save()
    Write-Host "✓ Desktop shortcut created" -ForegroundColor Green
} catch {
    Write-Warning "Could not create desktop shortcut: $($_.Exception.Message)"
}

# Create Start Menu shortcuts
try {
    $Shortcut = $WshShell.CreateShortcut((Join-Path $startMenuPath "BlueShift Migration.lnk"))
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$mainScript`""
    $Shortcut.WorkingDirectory = $scriptDir
    $Shortcut.IconLocation = "powershell.exe,0"
    $Shortcut.Description = "Run BlueShift Migration"
    $Shortcut.Save()

    $Shortcut = $WshShell.CreateShortcut((Join-Path $startMenuPath "BlueShift Setup.lnk"))
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $Shortcut.WorkingDirectory = $scriptDir
    $Shortcut.IconLocation = "powershell.exe,0"
    $Shortcut.Description = "BlueShift Setup Wizard"
    $Shortcut.Save()
    Write-Host "✓ Start Menu shortcuts created" -ForegroundColor Green
} catch {
    Write-Warning "Could not create Start Menu shortcuts: $($_.Exception.Message)"
}

# Setup complete
Write-Host ""
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "BlueShift has been successfully configured!" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor White
Write-Host "  1. Review configuration in config\migration.json" -ForegroundColor Gray
Write-Host "  2. Run preflight checks: .\scripts\Preflight-Checks.ps1" -ForegroundColor Gray
Write-Host "  3. Start migration: .\Start-Migration.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "Optional Components:" -ForegroundColor White
Write-Host "  • USMT: Requires Windows ADK installation" -ForegroundColor Gray
Write-Host "  • ForensiT: Requires separate licensing" -ForegroundColor Gray
Write-Host ""
Write-Host "Press Enter to exit..." -ForegroundColor Gray
Read-Host | Out-Null
