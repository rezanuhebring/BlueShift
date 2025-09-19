<#
.SYNOPSIS
    BlueShift BitLocker Key Export Script
    Exports BitLocker recovery keys before migration

.DESCRIPTION
    This script exports BitLocker recovery keys to ensure they remain
    accessible after the migration process.

.PARAMETER ConfigPath
    Path to the migration configuration JSON file

.PARAMETER DryRun
    Enable dry-run mode for testing

.EXAMPLE
    .\Export-BitLockerKey.ps1 -ConfigPath .\config\migration.json

.EXAMPLE
    .\Export-BitLockerKey.ps1 -ConfigPath .\config\migration.json -DryRun
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
Write-Host "   BlueShift BitLocker Key Export" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Check if BitLocker export is enabled
if (!$script:Config.BitLocker.ExportRecoveryKey) {
    Write-LogMessage "BitLocker key export is disabled in configuration" -Level Info
    Write-Host "ℹ️ BitLocker key export is disabled in configuration." -ForegroundColor Yellow
    exit 0
}

# Get BitLocker export directory
$exportDir = $script:Config.BitLocker.ExportDir
if ([string]::IsNullOrEmpty($exportDir)) {
    $exportDir = Join-Path $PSScriptRoot "..\artifacts\BitLocker"
}

# Ensure export directory exists
if (!$script:IsDryRun) {
    if (!(Test-Path $exportDir)) {
        try {
            New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
            Write-LogMessage "Created BitLocker export directory: $exportDir" -Level Info
        }
        catch {
            Write-LogMessage "Failed to create BitLocker export directory: $_" -Level Error
            exit 1
        }
    }
}

# Export BitLocker keys using the module function
$exportResult = Export-BitLockerKeys -ExportPath $exportDir

if ($exportResult) {
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "       BitLocker Export Summary" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "Export Location: $exportDir" -ForegroundColor Green
    Write-Host ""

    # List exported files
    if (!$script:IsDryRun) {
        $exportedFiles = Get-ChildItem -Path $exportDir -Filter "*.txt" | Where-Object { $_.Name -like "BitLocker_Recovery_*" }
        if ($exportedFiles.Count -gt 0) {
            Write-Host "Exported recovery key files:" -ForegroundColor Green
            foreach ($file in $exportedFiles) {
                Write-Host "  - $($file.Name)" -ForegroundColor Green
            }
        }
        else {
            Write-Host "No BitLocker volumes found or no recovery keys to export." -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "✅ BitLocker key export completed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host ""
    Write-Host "❌ BitLocker key export failed!" -ForegroundColor Red
    Write-Host "Check the log files for more details." -ForegroundColor Red
    exit 1
}
