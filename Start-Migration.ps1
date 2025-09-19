<#
.SYNOPSIS
    BlueShift Migration Tool - Main Entry Point
    Orchestrates the complete migration from Hybrid AD Join to Azure AD Join

.DESCRIPTION
    This is the main entry point for the BlueShift migration tool. It orchestrates
    all migration steps including preflight checks, backup, domain leave, Azure AD join,
    and profile migration.

.PARAMETER ConfigPath
    Path to the migration configuration JSON file

.PARAMETER DryRun
    Enable dry-run mode for testing

.PARAMETER SkipPreflight
    Skip preflight checks

.PARAMETER SkipBackup
    Skip user data backup

.PARAMETER SkipBitLocker
    Skip BitLocker key export

.EXAMPLE
    .\Start-Migration.ps1 -ConfigPath .\config\migration.json

.EXAMPLE
    .\Start-Migration.ps1 -ConfigPath .\config\migration.json -DryRun

.EXAMPLE
    .\Start-Migration.ps1 -ConfigPath .\config\migration.json -SkipPreflight -SkipBackup
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$SkipPreflight,

    [Parameter(Mandatory = $false)]
    [switch]$SkipBackup,

    [Parameter(Mandatory = $false)]
    [switch]$SkipBitLocker
)

# Set execution policy for this session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    🔵  BlueShift Migration Tool              ║" -ForegroundColor Cyan
Write-Host "║              Hybrid AD Join → Azure AD Join Migration       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Validate configuration file
if (!(Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    exit 1
}

# Display configuration summary
$config = Get-Content $ConfigPath -Raw | ConvertFromJson
Write-Host "Configuration Summary:" -ForegroundColor Yellow
Write-Host "  User: $($config.UserPrincipalName)" -ForegroundColor White
Write-Host "  Profile Engine: $($config.ProfileMigrationEngine)" -ForegroundColor White
Write-Host "  Backup Root: $($config.BackupRoot)" -ForegroundColor White
Write-Host "  Dry Run: $DryRun" -ForegroundColor White
Write-Host ""

# Define script paths
$scriptRoot = $PSScriptRoot
$preflightScript = Join-Path $scriptRoot "scripts\Preflight-Checks.ps1"
$backupScript = Join-Path $scriptRoot "scripts\Backup-UserData.ps1"
$bitlockerScript = Join-Path $scriptRoot "scripts\Export-BitLockerKey.ps1"
$domainLeaveScript = Join-Path $scriptRoot "scripts\Leave-Domain.ps1"
$aadJoinScript = Join-Path $scriptRoot "scripts\Guide-AzureADJoin.ps1"

# Migration steps
$migrationSteps = @()

if (!$SkipPreflight) {
    $migrationSteps += @{
        Name = "Preflight Checks"
        Script = $preflightScript
        Description = "Validate system requirements and safety conditions"
    }
}

if (!$SkipBackup) {
    $migrationSteps += @{
        Name = "User Data Backup"
        Script = $backupScript
        Description = "Backup user profiles and data"
    }
}

if (!$SkipBitLocker) {
    $migrationSteps += @{
        Name = "BitLocker Export"
        Script = $bitlockerScript
        Description = "Export BitLocker recovery keys"
    }
}

$migrationSteps += @{
    Name = "Domain Leave"
    Script = $domainLeaveScript
    Description = "Leave Active Directory domain and create temp admin"
}

$migrationSteps += @{
    Name = "Azure AD Join"
    Script = $aadJoinScript
    Description = "Guide through Azure AD join process"
}

# Display migration plan
Write-Host "Migration Plan:" -ForegroundColor Green
for ($i = 0; $i -lt $migrationSteps.Count; $i++) {
    $step = $migrationSteps[$i]
    Write-Host "  $($i + 1). $($step.Name)" -ForegroundColor White
    Write-Host "     $($step.Description)" -ForegroundColor Gray
}
Write-Host ""

if ($DryRun) {
    Write-Host "🔍 DRY RUN MODE - No actual changes will be made" -ForegroundColor Yellow
    Write-Host ""
}

# Confirm execution
if (!$DryRun) {
    $confirm = Read-Host "Do you want to proceed with the migration? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "Migration cancelled by user." -ForegroundColor Yellow
        exit 0
    }
}

# Execute migration steps
$stepNumber = 1
$failedSteps = @()

foreach ($step in $migrationSteps) {
    Write-Host ""
    Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " Step $($stepNumber): $($step.Name)" -ForegroundColor Cyan
    Write-Host " $($step.Description)" -ForegroundColor Gray
    Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

    try {
        $arguments = @("-ConfigPath", "`"$ConfigPath`"")
        if ($DryRun) {
            $arguments += "-DryRun"
        }

        # Execute the script
        $process = Start-Process -FilePath "powershell.exe" -ArgumentList ($arguments -join " ") -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0) {
            Write-Host "✅ Step $($stepNumber) completed successfully" -ForegroundColor Green
        }
        else {
            Write-Host "❌ Step $($stepNumber) failed with exit code: $($process.ExitCode)" -ForegroundColor Red
            $failedSteps += $step.Name

            # Ask user if they want to continue
            if (!$DryRun) {
                $continue = Read-Host "Step failed. Continue with remaining steps? (Y/N)"
                if ($continue -ne 'Y' -and $continue -ne 'y') {
                    Write-Host "Migration stopped by user after step failure." -ForegroundColor Yellow
                    break
                }
            }
        }
    }
    catch {
        Write-Host "❌ Step $($stepNumber) failed with error: $_" -ForegroundColor Red
        $failedSteps += $step.Name
    }

    $stepNumber++
}

# Migration summary
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                     Migration Summary                      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$totalSteps = $migrationSteps.Count
$completedSteps = $totalSteps - $failedSteps.Count

Write-Host "Total Steps: $totalSteps" -ForegroundColor White
Write-Host "Completed: $completedSteps" -ForegroundColor Green
Write-Host "Failed: $($failedSteps.Count)" -ForegroundColor Red

if ($failedSteps.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed Steps:" -ForegroundColor Red
    foreach ($failedStep in $failedSteps) {
        Write-Host "  - $failedStep" -ForegroundColor Red
    }
}

Write-Host ""

if ($completedSteps -eq $totalSteps) {
    Write-Host "🎉 Migration completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Verify Azure AD join status" -ForegroundColor White
    Write-Host "2. Test user login with Azure AD credentials" -ForegroundColor White
    Write-Host "3. Remove temporary admin account if created" -ForegroundColor White
    Write-Host "4. Clean up backup files when satisfied with migration" -ForegroundColor White
}
else {
    Write-Host "⚠️ Migration completed with errors!" -ForegroundColor Yellow
    Write-Host "Please review the failed steps and consider rollback if necessary." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "For support and documentation, see README.md" -ForegroundColor Gray

exit 0
