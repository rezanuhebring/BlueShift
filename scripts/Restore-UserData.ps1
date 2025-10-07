<#
.SYNOPSIS
    BlueShift User Data Restore Script
    Restores user data after Azure AD migration

.DESCRIPTION
    This script restores user data from backup after successful Azure AD migration.
    It supports both full restore and selective restore options.

.PARAMETER ConfigPath
    Path to the migration configuration JSON file

.PARAMETER BackupPath
    Path to the backup directory (optional, will auto-detect if not specified)

.PARAMETER RestoreMode
    Restore mode: Full, Selective, or VerifyOnly

.PARAMETER DryRun
    Enable dry-run mode for testing

.PARAMETER Force
    Force restore even if verification fails

.EXAMPLE
    .\Restore-UserData.ps1 -ConfigPath .\config\migration.json

.EXAMPLE
    .\Restore-UserData.ps1 -ConfigPath .\config\migration.json -RestoreMode Selective -DryRun
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [string]$BackupPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Full", "Selective", "VerifyOnly")]
    [string]$RestoreMode = "Full",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$Force
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
Write-Host "   BlueShift User Data Restore" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Get current user information
$currentUser = $env:USERNAME
$currentDomain = $env:USERDOMAIN
$userProfile = $env:USERPROFILE

Write-LogMessage "Current User: $currentDomain\$currentUser" -Level Info
Write-LogMessage "User Profile: $userProfile" -Level Info

# Determine backup location
if ($BackupPath) {
    $backupRoot = $BackupPath
}
else {
    $backupRoot = $script:Config.BackupRoot
}

$userBackupDir = Join-Path $backupRoot $currentUser

# Verify backup exists
if (!(Test-Path $userBackupDir)) {
    Write-LogMessage "Backup directory not found: $userBackupDir" -Level Error
    Write-LogMessage "Please ensure the backup was created successfully before migration." -Level Error
    exit 1
}

# Load backup manifest
$manifestPath = Join-Path $userBackupDir "backup_manifest.json"
if (Test-Path $manifestPath) {
    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        Write-LogMessage "Loaded backup manifest from: $manifestPath" -Level Info
        Write-LogMessage "Backup created: $($manifest.Timestamp)" -Level Info
        Write-LogMessage "Original user: $($manifest.UserName)" -Level Info
    }
    catch {
        Write-LogMessage "Failed to load backup manifest: $_" -Level Warning
        $manifest = $null
    }
}
else {
    Write-LogMessage "Backup manifest not found, proceeding without verification" -Level Warning
    $manifest = $null
}

# Verify backup integrity
function Test-BackupIntegrity {
    param([string]$BackupDir)

    Write-LogMessage "Verifying backup integrity..." -Level Info

    $issues = @()
    $totalFiles = 0
    $corruptedFiles = 0

    # Check if backup directory exists and has content
    if (!(Test-Path $BackupDir)) {
        $issues += "Backup directory does not exist: $BackupDir"
        return $false, $issues
    }

    # Get all files in backup
    $files = Get-ChildItem -Path $BackupDir -Recurse -File -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        $totalFiles++

        # Check if file is accessible
        try {
            $null = Get-ItemProperty -Path $file.FullName -ErrorAction Stop
        }
        catch {
            $corruptedFiles++
            $issues += "Corrupted file: $($file.FullName)"
        }
    }

    Write-LogMessage "Total files in backup: $totalFiles" -Level Info
    if ($corruptedFiles -gt 0) {
        Write-LogMessage "Corrupted files: $corruptedFiles" -Level Warning
    }

    return ($corruptedFiles -eq 0), $issues
}

$backupValid, $backupIssues = Test-BackupIntegrity -BackupDir $userBackupDir

if (!$backupValid) {
    Write-LogMessage "Backup integrity check failed!" -Level Error
    foreach ($issue in $backupIssues) {
        Write-LogMessage "Issue: $issue" -Level Error
    }

    if (!$Force) {
        Write-LogMessage "Use -Force parameter to restore despite integrity issues" -Level Error
        exit 1
    }
    else {
        Write-LogMessage "Proceeding with restore despite integrity issues (Force mode)" -Level Warning
    }
}

# Get restore options for selective restore
if ($RestoreMode -eq "Selective") {
    Write-Host ""
    Write-Host "Available restore options:" -ForegroundColor Yellow
    Write-Host "1. Desktop" -ForegroundColor Green
    Write-Host "2. Documents" -ForegroundColor Green
    Write-Host "3. Downloads" -ForegroundColor Green
    Write-Host "4. Pictures" -ForegroundColor Green
    Write-Host "5. Videos" -ForegroundColor Green
    Write-Host "6. Music" -ForegroundColor Green
    Write-Host "7. AppData (Roaming)" -ForegroundColor Green
    Write-Host "8. AppData (Local)" -ForegroundColor Green
    Write-Host "9. All of the above" -ForegroundColor Green
    Write-Host ""

    $selection = Read-Host "Enter your selection (1-9)"
    Write-Host ""

    $restoreOptions = switch ($selection) {
        "1" { @("Desktop") }
        "2" { @("Documents") }
        "3" { @("Downloads") }
        "4" { @("Pictures") }
        "5" { @("Videos") }
        "6" { @("Music") }
        "7" { @("AppData\\Roaming") }
        "8" { @("AppData\\Local") }
        "9" { @("Desktop", "Documents", "Downloads", "Pictures", "Videos", "Music", "AppData\\Roaming", "AppData\\Local") }
        default {
            Write-LogMessage "Invalid selection: $selection" -Level Error
            exit 1
        }
    }
}

# Perform restore
Write-LogMessage "🔄 Starting restore process..." -Level Info

$restoreSummary = @{
    TotalItems = 0
    Successful = 0
    Failed = 0
    Skipped = 0
}

foreach ($includePath in $script:Config.Backup.IncludePaths) {
    # Expand environment variables for source path
    $expandedSource = [Environment]::ExpandEnvironmentVariables($includePath)

    # Get relative path for backup location
    $relativePath = $expandedSource -replace [regex]::Escape($userProfile), ""
    if ($relativePath.StartsWith("\")) {
        $relativePath = $relativePath.Substring(1)
    }

    $sourcePath = Join-Path $userBackupDir $relativePath

    # Skip if source doesn't exist in backup
    if (!(Test-Path $sourcePath)) {
        Write-LogMessage "Backup source not found, skipping: $sourcePath" -Level Warning
        $restoreSummary.Skipped++
        continue
    }

    # For selective restore, check if this path should be restored
    if ($RestoreMode -eq "Selective") {
        $pathName = $relativePath.Split('\')[0]
        if ($restoreOptions -notcontains $pathName -and $restoreOptions -notcontains "AppData\Roaming" -and $restoreOptions -notcontains "AppData\Local") {
            Write-LogMessage "Skipping (selective mode): $relativePath" -Level Info
            $restoreSummary.Skipped++
            continue
        }
    }

    $restoreSummary.TotalItems++

    Write-LogMessage "Restoring: $sourcePath -> $expandedSource" -Level Info

    if ($DryRun) {
        Write-LogMessage "[DRY RUN] Would restore: $sourcePath -> $expandedSource" -Level Info
        $restoreSummary.Successful++
        continue
    }

    try {
        # Create destination directory if it doesn't exist
        $destinationDir = Split-Path -Path $expandedSource -Parent
        if (!(Test-Path $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }

        # Build robocopy arguments for restore
        $robocopyArgs = @(
            "`"$sourcePath`"",  # Source (wrap in quotes to handle spaces)
            "`"$expandedSource`"",  # Destination (wrap in quotes to handle spaces)
            "/E",              # Copy subdirectories, including empty ones
            "/R:2",            # Retry failed copies 2 times
            "/W:2",            # Wait 2 seconds between retries
            "/SL",             # Copy symbolic links as links
            "/XJ",             # Exclude junction points
            "/NP",             # Don't show progress
            "/NJH",            # No job header
            "/NJS",            # No job summary
            "/LOG+:$(Join-Path $script:Config.Logging.LogDir "restore_robocopy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log")"
        )

        # Execute robocopy
        $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -le 7) { # Robocopy exit codes 0-7 are success
            Write-LogMessage "Successfully restored: $expandedSource" -Level Info
            $restoreSummary.Successful++
        }
        else {
            Write-LogMessage "Robocopy failed for $expandedSource (Exit code: $($process.ExitCode))" -Level Warning
            $restoreSummary.Failed++
        }
    }
    catch {
        Write-LogMessage "Failed to restore $expandedSource : $_" -Level Error
        $restoreSummary.Failed++
    }
}

# Create restore manifest
$restoreManifestPath = Join-Path $userBackupDir "restore_manifest.json"
$restoreManifest = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ComputerName = $env:COMPUTERNAME
    UserName = "$currentDomain\$currentUser"
    UserProfile = $userProfile
    BackupRoot = $backupRoot
    UserBackupDir = $userBackupDir
    RestoreMode = $RestoreMode
    DryRun = $DryRun.IsPresent
    Force = $Force.IsPresent
    BackupIntegrityValid = $backupValid
    RestoreSummary = $restoreSummary
    BackupManifest = $manifest
}

if (!$DryRun) {
    try {
        $restoreManifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $restoreManifestPath -Encoding UTF8
        Write-LogMessage "Created restore manifest: $restoreManifestPath" -Level Info
    }
    catch {
        Write-LogMessage "Failed to create restore manifest: $_" -Level Warning
    }
}

# Display summary
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "         Restore Summary" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Restore Mode: $RestoreMode" -ForegroundColor Green
Write-Host "Backup Location: $userBackupDir" -ForegroundColor Green
Write-Host "Total Items: $($restoreSummary.TotalItems)" -ForegroundColor Green
Write-Host "Successful: $($restoreSummary.Successful)" -ForegroundColor Green
Write-Host "Failed: $($restoreSummary.Failed)" -ForegroundColor $(if ($restoreSummary.Failed -gt 0) { "Red" } else { "Green" })
Write-Host "Skipped: $($restoreSummary.Skipped)" -ForegroundColor Green

if ($backupValid) {
    Write-Host "Backup Integrity: ✅ Valid" -ForegroundColor Green
}
else {
    Write-Host "Backup Integrity: ❌ Issues Found" -ForegroundColor Red
}

if (!$DryRun) {
    Write-Host "Restore Manifest: $restoreManifestPath" -ForegroundColor Green
}
Write-Host ""

# Final status
if ($restoreSummary.Failed -eq 0) {
    Write-Host "✅ Restore completed successfully!" -ForegroundColor Green
    Write-LogMessage "✅ Data berhasil dipulihkan." -Level Info
    exit 0
}
else {
    Write-Host "⚠️ Restore completed with some issues. Check the log for details." -ForegroundColor Yellow
    Write-LogMessage "⚠️ Pemulihan selesai dengan beberapa masalah." -Level Warning
    exit 0  # Don't fail the script for partial restore issues
}
