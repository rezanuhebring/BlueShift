<#
.SYNOPSIS
    BlueShift Preflight Checks Script
    Performs comprehensive system validation before migration

.DESCRIPTION
    This script validates all prerequisites and safety conditions
    before proceeding with the BlueShift migration process.

.PARAMETER ConfigPath
    Path to the migration configuration JSON file

.PARAMETER DryRun
    Enable dry-run mode for testing

.EXAMPLE
    .\Preflight-Checks.ps1 -ConfigPath .\config\migration.json

.EXAMPLE
    .\Preflight-Checks.ps1 -ConfigPath .\config\migration.json -DryRun
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
Write-Host "      BlueShift Preflight Checks" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Run preflight checks
$results = Test-PreflightChecks

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "           Preflight Summary" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

Write-Host "Checks Passed: $($results.Checks.Count)" -ForegroundColor Green
Write-Host "Warnings: $($results.Warnings.Count)" -ForegroundColor Yellow
Write-Host "Errors: $($results.Errors.Count)" -ForegroundColor Red

if ($results.Passed) {
    Write-Host ""
    Write-Host "✅ All preflight checks passed!" -ForegroundColor Green
    Write-Host "You can proceed with the migration." -ForegroundColor Green
    exit 0
}
else {
    Write-Host ""
    Write-Host "❌ Preflight checks failed!" -ForegroundColor Red
    Write-Host "Please resolve the errors before proceeding." -ForegroundColor Red
    exit 1
}
