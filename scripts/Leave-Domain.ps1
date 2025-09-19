<#
.SYNOPSIS
    BlueShift Domain Leave Script
    Leaves the domain and creates temporary admin account

.DESCRIPTION
    This script handles leaving the Active Directory domain and creates
    a temporary local administrator account for post-migration access.

.PARAMETER ConfigPath
    Path to the migration configuration JSON file

.PARAMETER DryRun
    Enable dry-run mode for testing

.EXAMPLE
    .\Leave-Domain.ps1 -ConfigPath .\config\migration.json

.EXAMPLE
    .\Leave-Domain.ps1 -ConfigPath .\config\migration.json -DryRun
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
Write-Host "     BlueShift Domain Leave" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Check if domain leave is enabled
if (!$script:Config.Domain.LeaveDomain) {
    Write-LogMessage "Domain leave is disabled in configuration" -Level Info
    Write-Host "ℹ️ Domain leave is disabled in configuration." -ForegroundColor Yellow
    exit 0
}

# Get current domain status
$computerSystem = Get-WmiObject Win32_ComputerSystem
$isDomainJoined = $computerSystem.PartOfDomain

if (!$isDomainJoined) {
    Write-LogMessage "Computer is not domain-joined" -Level Warning
    Write-Host "⚠️ Computer is not currently domain-joined." -ForegroundColor Yellow
    Write-Host "Skipping domain leave process." -ForegroundColor Yellow
    exit 0
}

$currentDomain = $computerSystem.Domain
Write-LogMessage "Current domain: $currentDomain" -Level Info
Write-Host "Current Domain: $currentDomain" -ForegroundColor Green

# Create temporary admin account if enabled
if ($script:Config.Domain.CreateTempLocalAdmin) {
    $tempAdminName = $script:Config.Domain.TempLocalAdminName

    # Get password from environment variable
    $passwordRef = $script:Config.Domain.TempLocalAdminPassSecretRef
    if ($passwordRef -match "^env:(.+)") {
        $envVarName = $matches[1]
        $tempAdminPassword = [Environment]::GetEnvironmentVariable($envVarName)
    }
    else {
        $tempAdminPassword = $passwordRef
    }

    if ([string]::IsNullOrEmpty($tempAdminPassword)) {
        Write-LogMessage "Temporary admin password not found in environment variable: $envVarName" -Level Error
        Write-Host "❌ Temporary admin password not configured!" -ForegroundColor Red
        exit 1
    }

    Write-LogMessage "🧩 Siap lepas dari domain on-prem." -Level Info

    # Create temporary admin account
    $createResult = New-TemporaryAdminAccount -UserName $tempAdminName -Password $tempAdminPassword

    if (!$createResult) {
        Write-LogMessage "Failed to create temporary admin account" -Level Error
        Write-Host "❌ Failed to create temporary admin account!" -ForegroundColor Red
        exit 1
    }

    Write-LogMessage "Created temporary admin account: $tempAdminName" -Level Info
    Write-Host "✅ Created temporary admin account: $tempAdminName" -ForegroundColor Green
}
else {
    Write-LogMessage "Temporary admin account creation is disabled" -Level Info
    Write-Host "ℹ️ Temporary admin account creation is disabled." -ForegroundColor Yellow
}

# Leave the domain
if (!$script:IsDryRun) {
    Write-LogMessage "Leaving domain: $currentDomain" -Level Info
    Write-Host "Leaving domain: $currentDomain" -ForegroundColor Yellow

    try {
        # Use Remove-Computer cmdlet (PowerShell 5.1+)
        $leaveResult = Remove-Computer -UnjoinDomainCredential (Get-Credential -Message "Enter domain admin credentials to leave the domain") -PassThru -Restart:$false -Confirm:$false

        if ($leaveResult) {
            Write-LogMessage "Successfully left domain: $currentDomain" -Level Info
            Write-Host "✅ Successfully left domain: $currentDomain" -ForegroundColor Green
        }
        else {
            Write-LogMessage "Failed to leave domain: $currentDomain" -Level Error
            Write-Host "❌ Failed to leave domain!" -ForegroundColor Red
            exit 1
        }
    }
    catch {
        Write-LogMessage "Error leaving domain: $_" -Level Error
        Write-Host "❌ Error leaving domain: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-LogMessage "[DRY RUN] Would leave domain: $currentDomain" -Level Info
    Write-Host "[DRY RUN] Would leave domain: $currentDomain" -ForegroundColor Yellow
}

# Schedule post-reboot continuation if needed
if (!$script:IsDryRun) {
    Write-LogMessage "Computer will restart after leaving domain" -Level Info
    Write-Host "🔄 Computer will restart to complete domain leave process..." -ForegroundColor Yellow
    Write-Host "After restart, continue with Azure AD join process." -ForegroundColor Yellow

    # Create a scheduled task to continue after reboot
    $taskName = "BlueShift_PostDomainLeave"
    $scriptPath = Join-Path $PSScriptRoot "Guide-AzureADJoin.ps1"

    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`" -ConfigPath `"$ConfigPath`""
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId $tempAdminName -LogonType InteractiveToken
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

        Write-LogMessage "Created post-reboot continuation task: $taskName" -Level Info
        Write-Host "✅ Created continuation task for after restart" -ForegroundColor Green
    }
    catch {
        Write-LogMessage "Failed to create continuation task: $_" -Level Warning
        Write-Host "⚠️ Failed to create continuation task. Manual continuation required." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "        Domain Leave Summary" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

if ($script:Config.Domain.CreateTempLocalAdmin) {
    Write-Host "Temporary Admin Account: $tempAdminName" -ForegroundColor Green
    Write-Host "⚠️ Remember to remove this account after migration!" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "✅ Domain leave process completed!" -ForegroundColor Green
Write-Host "🔄 System will restart to complete the process..." -ForegroundColor Yellow

# Prompt for restart
if (!$script:IsDryRun) {
    $restart = Read-Host "Press Enter to restart now, or 'N' to restart manually later"
    if ($restart -ne 'N' -and $restart -ne 'n') {
        Write-LogMessage "Initiating system restart..." -Level Info
        Restart-Computer -Force
    }
    else {
        Write-Host "Please restart the computer manually to complete domain leave." -ForegroundColor Yellow
    }
}

exit 0
