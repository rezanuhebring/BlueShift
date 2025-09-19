<#
.SYNOPSIS
    BlueShift Azure AD Join Guidance Script
    Guides the user through Azure AD join process

.DESCRIPTION
    This script opens the Windows Settings deep link for Azure AD join
    and monitors the join status until completion.

.PARAMETER ConfigPath
    Path to the migration configuration JSON file

.PARAMETER DryRun
    Enable dry-run mode for testing

.EXAMPLE
    .\Guide-AzureADJoin.ps1 -ConfigPath .\config\migration.json

.EXAMPLE
    .\Guide-AzureADJoin.ps1 -ConfigPath .\config\migration.json -DryRun
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
Write-Host "  BlueShift Azure AD Join Guidance" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Check current Azure AD join status
$initialStatus = Get-AzureADJoinStatus
Write-LogMessage "Initial Azure AD join status - Joined: $($initialStatus.IsAzureADJoined), Hybrid: $($initialStatus.IsHybridJoined)" -Level Info

if ($initialStatus.IsAzureADJoined) {
    Write-LogMessage "Device is already Azure AD joined" -Level Info
    Write-Host "✅ Device is already Azure AD joined!" -ForegroundColor Green
    Write-Host "User Principal Name: $($initialStatus.UserPrincipalName)" -ForegroundColor Green
    exit 0
}

# Display instructions
Write-Host "🪄 Langkah manual diperlukan: Buka Settings > Accounts > Access work or school > Connect > Join this device to Azure Active Directory." -ForegroundColor Yellow
Write-Host ""
Write-Host "Instructions:" -ForegroundColor Cyan
Write-Host "1. The Settings app will open automatically" -ForegroundColor White
Write-Host "2. Click 'Access work or school'" -ForegroundColor White
Write-Host "3. Click 'Connect'" -ForegroundColor White
Write-Host "4. Select 'Join this device to Azure Active Directory'" -ForegroundColor White
Write-Host "5. Enter your Azure AD credentials:" -ForegroundColor White
Write-Host "   - Email: $($script:Config.UserPrincipalName)" -ForegroundColor Green
Write-Host "6. Follow the on-screen instructions" -ForegroundColor White
Write-Host "7. Restart when prompted" -ForegroundColor White
Write-Host ""
Write-Host "⚠️ Do not close this window until the process is complete!" -ForegroundColor Yellow
Write-Host ""

if (!$script:IsDryRun) {
    # Open Settings deep link
    Write-LogMessage "Opening Settings deep link for Azure AD join" -Level Info
    try {
        Start-Process "ms-settings:workplace"
        Write-Host "✅ Settings app opened successfully" -ForegroundColor Green
    }
    catch {
        Write-LogMessage "Failed to open Settings app: $_" -Level Error
        Write-Host "❌ Failed to open Settings app automatically" -ForegroundColor Red
        Write-Host "Please manually open Settings > Accounts > Access work or school" -ForegroundColor Yellow
    }

    # Wait for user confirmation to start monitoring
    Write-Host ""
    Read-Host "Press Enter when you have started the Azure AD join process in Settings"

    # Monitor Azure AD join status
    Write-LogMessage "Starting Azure AD join status monitoring" -Level Info
    Write-Host "🔄 Monitoring Azure AD join status..." -ForegroundColor Yellow

    $joinCompleted = Wait-AzureADJoinCompletion

    if ($joinCompleted) {
        Write-Host ""
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host "     Azure AD Join Completed!" -ForegroundColor Cyan
        Write-Host "=========================================" -ForegroundColor Cyan

        $finalStatus = Get-AzureADJoinStatus
        Write-Host "✅ Azure AD Joined: $($finalStatus.IsAzureADJoined)" -ForegroundColor Green
        Write-Host "User Principal Name: $($finalStatus.UserPrincipalName)" -ForegroundColor Green
        Write-Host "Device ID: $($finalStatus.DeviceId)" -ForegroundColor Green
        Write-Host "Tenant ID: $($finalStatus.TenantId)" -ForegroundColor Green

        Write-LogMessage "Azure AD join completed successfully" -Level Info
        Write-LogMessage "UPN: $($finalStatus.UserPrincipalName), DeviceId: $($finalStatus.DeviceId)" -Level Info

        # Clean up scheduled task if it exists
        try {
            $taskName = "BlueShift_PostDomainLeave"
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($task) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
                Write-LogMessage "Cleaned up scheduled task: $taskName" -Level Info
            }
        }
        catch {
            Write-LogMessage "Failed to clean up scheduled task: $_" -Level Warning
        }

        Write-Host ""
        Write-Host "🎉 Azure AD join completed successfully!" -ForegroundColor Green
        Write-Host "You can now proceed with profile migration." -ForegroundColor Green

        exit 0
    }
    else {
        Write-Host ""
        Write-Host "❌ Azure AD join did not complete within the timeout period" -ForegroundColor Red
        Write-Host "This could be due to:" -ForegroundColor Yellow
        Write-Host "  - Network connectivity issues" -ForegroundColor Yellow
        Write-Host "  - Invalid credentials" -ForegroundColor Yellow
        Write-Host "  - Azure AD policy restrictions" -ForegroundColor Yellow
        Write-Host "  - User cancelled the process" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Please check the Azure AD join status manually and try again." -ForegroundColor Yellow

        Write-LogMessage "Azure AD join monitoring timed out" -Level Error
        exit 1
    }
}
else {
    Write-LogMessage "[DRY RUN] Would open Settings deep link and monitor Azure AD join" -Level Info
    Write-Host "[DRY RUN] Would open Settings deep link and monitor Azure AD join" -ForegroundColor Yellow
    Write-Host "✅ Dry run completed - no actual changes made" -ForegroundColor Green
    exit 0
}
