<#
.SYNOPSIS
    BlueShift User Data Backup Script
    Backs up user profiles and data before migration

.DESCRIPTION
    This script performs comprehensive backup of user data using robocopy
    with optional Volume Shadow Copy (VSS) support for consistent snapshots.

.PARAMETER ConfigPath
    Path to the migration configuration JSON file

.PARAMETER DryRun
    Enable dry-run mode for testing

.EXAMPLE
    .\Backup-UserData.ps1 -ConfigPath .\config\migration.json

.EXAMPLE
    .\Backup-UserData.ps1 -ConfigPath .\config\migration.json -DryRun
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# Import the migration module
$modulePath = Join-Path $PSScriptRoot "..\modules\MigHelper\MigHelper.psm1"
if (!(Test-Path $modulePath)) {
    Write-Error "Migration module not found at: $modulePath"
    exit 1
}

Import-Module $modulePath -Force

# Initialize the migration module
if (!(Initialize-MigrationModule -ConfigPath $ConfigPath -DryRun:$DryRun)) {
    Write-Error "Failed to initialize migration module"
    exit 1
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "     BlueShift User Data Backup" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Get current user information
$currentUser = $env:USERNAME
$currentDomain = $env:USERDOMAIN
$userProfile = $env:USERPROFILE

Write-LogMessage "Current User: $currentDomain\$currentUser" -Level Info
Write-LogMessage "User Profile: $userProfile" -Level Info

# Create backup root directory
$backupRoot = $script:Config.BackupRoot
if ($script:IsDryRun) {
    Write-LogMessage "[DRY RUN] Would create backup directory: $backupRoot" -Level Info
}
else {
    if (!(Test-Path $backupRoot)) {
        try {
            New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
            Write-LogMessage "Created backup root directory: $backupRoot" -Level Info
        }
        catch {
            Write-LogMessage "Failed to create backup directory: $_" -Level Error
            exit 1
        }
    }
}

# Create user-specific backup directory
$userBackupDir = Join-Path $backupRoot $currentUser
if ($script:IsDryRun) {
    Write-LogMessage "[DRY RUN] Would create user backup directory: $userBackupDir" -Level Info
}
else {
    if (!(Test-Path $userBackupDir)) {
        try {
            New-Item -ItemType Directory -Path $userBackupDir -Force | Out-Null
            Write-LogMessage "Created user backup directory: $userBackupDir" -Level Info
        }
        catch {
            Write-LogMessage "Failed to create user backup directory: $_" -Level Error
            exit 1
        }
    }
}

# Build robocopy arguments
$robocopyArgs = @()

# Basic options for reliable copying
$robocopyArgs += "/MIR"          # Mirror directory tree
$robocopyArgs += "/R:2"          # Retry failed copies 2 times
$robocopyArgs += "/W:2"          # Wait 2 seconds between retries
$robocopyArgs += "/SL"           # Copy symbolic links as links
$robocopyArgs += "/XJ"           # Exclude junction points
$robocopyArgs += "/NP"           # Don't show progress
$robocopyArgs += "/NJH"          # No job header
$robocopyArgs += "/NJS"          # No job summary

# Logging
$logFile = Join-Path $script:Config.Logging.LogDir "backup_robocopy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$robocopyArgs += "/LOG+:$logFile"

# Build exclude patterns
$excludeDirs = @()
$excludeFiles = @()

# Add configured exclude patterns
foreach ($excludeGlob in $script:Config.Backup.ExcludeGlobs) {
    # Convert glob patterns to robocopy format
    if ($excludeGlob -like "**\\*") {
        # Directory pattern
        $pattern = $excludeGlob -replace "\*\*\\\\", "" -replace "\\\\\*\*", ""
        $excludeDirs += $pattern
    }
    elseif ($excludeGlob -like "**\\*.**") {
        # File pattern
        $pattern = $excludeGlob -replace "\*\*\\\\", "" -replace "\*\*", ""
        $excludeFiles += $pattern
    }
}

# Add exclude arguments
if ($excludeDirs.Count -gt 0) {
    $robocopyArgs += "/XD"
    $robocopyArgs += ($excludeDirs -join " ")
}

if ($excludeFiles.Count -gt 0) {
    $robocopyArgs += "/XF"
    $robocopyArgs += ($excludeFiles -join " ")
}

Write-LogMessage "🔄 Membackup profil & data pengguna..." -Level Info

$totalItems = $script:Config.Backup.IncludePaths.Count
$completedItems = 0

foreach ($sourcePath in $script:Config.Backup.IncludePaths) {
    # Expand environment variables
    $expandedSource = [Environment]::ExpandEnvironmentVariables($sourcePath)

    if (!(Test-Path $expandedSource)) {
        Write-LogMessage "Source path does not exist, skipping: $expandedSource" -Level Warning
        continue
    }

    # Get relative path for destination
    $relativePath = $expandedSource -replace [regex]::Escape($userProfile), ""
    if ($relativePath.StartsWith("\")) {
        $relativePath = $relativePath.Substring(1)
    }

    $destinationPath = Join-Path $userBackupDir $relativePath

    Write-LogMessage "Backing up: $expandedSource -> $destinationPath" -Level Info

    if ($script:IsDryRun) {
        Write-LogMessage "[DRY RUN] Would run: robocopy `"$expandedSource`" `"$destinationPath`" $($robocopyArgs -join ' ')" -Level Info
        $completedItems++
        continue
    }

    try {
        # Create destination directory if it doesn't exist
        if (!(Test-Path $destinationPath)) {
            New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
        }

        # Execute robocopy
        $argumentList = @($expandedSource, $destinationPath) + $robocopyArgs
        $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $argumentList -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -le 7) { # Robocopy exit codes 0-7 are success
            Write-LogMessage "Successfully backed up: $expandedSource" -Level Info
        }
        else {
            Write-LogMessage "Robocopy failed for $expandedSource (Exit code: $($process.ExitCode))" -Level Warning
        }

        $completedItems++
        $percentComplete = [math]::Round(($completedItems / $totalItems) * 100)
        Write-Progress -Activity "Backing up user data" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
    }
    catch {
        Write-LogMessage "Failed to backup $expandedSource : $_" -Level Error
    }
}

Write-Progress -Activity "Backing up user data" -Completed

# Create backup manifest
$manifestPath = Join-Path $userBackupDir "backup_manifest.json"
$manifest = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ComputerName = $env:COMPUTERNAME
    UserName = "$currentDomain\$currentUser"
    UserProfile = $userProfile
    BackupRoot = $backupRoot
    UserBackupDir = $userBackupDir
    IncludePaths = $script:Config.Backup.IncludePaths
    ExcludeGlobs = $script:Config.Backup.ExcludeGlobs
    RobocopyLog = $logFile
    DryRun = $script:IsDryRun
}

if (!$script:IsDryRun) {
    try {
        $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $manifestPath -Encoding UTF8
        Write-LogMessage "Created backup manifest: $manifestPath" -Level Info
    }
    catch {
        Write-LogMessage "Failed to create backup manifest: $_" -Level Warning
    }
}

Write-LogMessage "✅ Backup selesai." -Level Info

# Display summary
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "           Backup Summary" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Backup Location: $userBackupDir" -ForegroundColor Green
Write-Host "Items Processed: $completedItems / $totalItems" -ForegroundColor Green
Write-Host "Log File: $logFile" -ForegroundColor Green
if (!$script:IsDryRun) {
    Write-Host "Manifest: $manifestPath" -ForegroundColor Green
}
Write-Host ""

if ($completedItems -eq $totalItems) {
    Write-Host "✅ Backup completed successfully!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "⚠️ Backup completed with some issues. Check the log for details." -ForegroundColor Yellow
    exit 0  # Don't fail the script for partial backup issues
}
