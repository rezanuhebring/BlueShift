<#
.SYNOPSIS
    BlueShift Migration Helper Module
    A comprehensive tool for migrating Windows devices from Hybrid AD Join to Azure AD Join

.DESCRIPTION
    This module provides functions for migrating Windows 10/11 devices from Hybrid AD Join
    to Azure AD Join while preserving user data, applications, and profiles.

.NOTES
    Author: IT-Engineering
    Version: 1.0.0
    Requires: PowerShell 5.1+ with Administrator privileges
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

# Import required modules
Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction SilentlyContinue
Import-Module BitLocker -ErrorAction SilentlyContinue

# Module variables
$script:Config = $null
$script:LogPath = $null
$script:IsDryRun = $false

<#
.SYNOPSIS
    Initializes the migration module with configuration

.PARAMETER ConfigPath
    Path to the migration configuration JSON file

.PARAMETER DryRun
    Enable dry-run mode for testing
#>
function Initialize-MigrationModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    try {
        # Load configuration
        if (!(Test-Path $ConfigPath)) {
            throw "Configuration file not found: $ConfigPath"
        }

        $script:Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $script:IsDryRun = $DryRun.IsPresent

        # Set up logging
        $logDir = $script:Config.Logging.LogDir
        if (!(Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $script:LogPath = Join-Path $logDir "migration_$timestamp.log"

        Write-LogMessage "BlueShift Migration Module initialized" -Level Info
        Write-LogMessage "Configuration loaded from: $ConfigPath" -Level Info
        Write-LogMessage "Dry-run mode: $($script:IsDryRun)" -Level Info

        return $true
    }
    catch {
        Write-Error "Failed to initialize migration module: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Writes a message to the log file and console

.PARAMETER Message
    The message to log

.PARAMETER Level
    Log level (Info, Warning, Error)
#>
function Write-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Write to console with color
    switch ($Level) {
        "Info" { Write-Host $logEntry -ForegroundColor Green }
        "Warning" { Write-Host $logEntry -ForegroundColor Yellow }
        "Error" { Write-Host $logEntry -ForegroundColor Red }
    }

    # Write to log file if initialized
    if ($script:LogPath) {
        try {
            Add-Content -Path $script:LogPath -Value $logEntry -Encoding UTF8
        }
        catch {
            Write-Warning "Failed to write to log file: $_"
        }
    }
}

<#
.SYNOPSIS
    Performs preflight checks before migration

.OUTPUTS
    Hashtable with check results
#>
function Test-PreflightChecks {
    [CmdletBinding()]
    param()

    Write-LogMessage "Starting preflight checks..." -Level Info

    $results = @{
        Passed = $true
        Checks = @()
        Warnings = @()
        Errors = @()
    }

    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (!$isAdmin) {
        $results.Errors += "Script must be run as Administrator"
        $results.Passed = $false
    }
    else {
        $results.Checks += "Running as Administrator: PASS"
    }

    # Check Windows version
    $osInfo = Get-ComputerInfo
    $minVersions = @{
        "Windows 10" = "21H2"
        "Windows 11" = "22H2"
    }

    $currentVersion = $osInfo.WindowsProductName
    $buildNumber = $osInfo.WindowsVersion

    Write-LogMessage "OS: $currentVersion (Build: $buildNumber)" -Level Info

    # Check disk space
    $systemDrive = $env:SystemDrive
    $diskInfo = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$systemDrive'"
    $freeSpaceGB = [math]::Round($diskInfo.FreeSpace / 1GB, 2)

    if ($freeSpaceGB -lt $script:Config.Safeguards.MinFreeDiskGB) {
        $results.Errors += "Insufficient disk space: ${freeSpaceGB}GB free, minimum ${$script:Config.Safeguards.MinFreeDiskGB}GB required"
        $results.Passed = $false
    }
    else {
        $results.Checks += "Disk space: ${freeSpaceGB}GB free (minimum ${$script:Config.Safeguards.MinFreeDiskGB}GB)"
    }

    # Check power source
    if ($script:Config.Safeguards.RequireACPower) {
        $powerStatus = Get-WmiObject Win32_Battery
        if ($powerStatus) {
            $batteryStatus = Get-WmiObject Win32_Battery | Select-Object -First 1
            if ($batteryStatus.BatteryStatus -ne 2) { # 2 = On AC Power
                $results.Errors += "Device must be connected to AC power"
                $results.Passed = $false
            }
            else {
                $results.Checks += "Power source: AC power connected"
            }
        }
    }

    # Check network connectivity
    if ($script:Config.Safeguards.RequireNetwork) {
        try {
            $testConnection = Test-Connection -ComputerName "www.microsoft.com" -Count 1 -Quiet
            if ($testConnection) {
                $results.Checks += "Network connectivity: PASS"
            }
            else {
                $results.Errors += "No network connectivity detected"
                $results.Passed = $false
            }
        }
        catch {
            $results.Warnings += "Network connectivity check failed: $_"
        }
    }

    # Check domain membership
    $domainInfo = Get-WmiObject Win32_ComputerSystem
    if ($domainInfo.PartOfDomain) {
        $results.Checks += "Domain membership: $($domainInfo.Domain)"
    }
    else {
        $results.Warnings += "Device is not domain-joined"
    }

    # Check BitLocker status
    try {
        $bitlockerVolumes = Get-BitLockerVolume
        foreach ($volume in $bitlockerVolumes) {
            if ($volume.ProtectionStatus -eq "On") {
                $results.Checks += "BitLocker enabled on $($volume.MountPoint)"
            }
        }
    }
    catch {
        $results.Warnings += "BitLocker check failed: $_"
    }

    # Log results
    foreach ($check in $results.Checks) {
        Write-LogMessage $check -Level Info
    }

    foreach ($warning in $results.Warnings) {
        Write-LogMessage $warning -Level Warning
    }

    foreach ($err in $results.Errors) {
        Write-LogMessage $err -Level Error
    }

    if ($results.Passed) {
        Write-LogMessage "✅ Pemeriksaan awal lulus. Siap migrasi." -Level Info
    }
    elseif ($results.Errors.Count -gt 0) {
        Write-LogMessage "❌ Pemeriksaan awal gagal. Hentikan dan perbaiki dahulu." -Level Error
    }
    else {
        Write-LogMessage "⚠️ Ada peringatan. Lihat log untuk detail." -Level Warning
    }

    return $results
}

<#
.SYNOPSIS
    Exports BitLocker recovery keys

.PARAMETER ExportPath
    Path to export recovery keys
#>
function Export-BitLockerKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExportPath
    )

    if ($script:IsDryRun) {
        Write-LogMessage "[DRY RUN] Would export BitLocker keys to: $ExportPath" -Level Info
        return $true
    }

    try {
        if (!(Test-Path $ExportPath)) {
            New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
        }

        $bitlockerVolumes = Get-BitLockerVolume
        $exportedCount = 0

        foreach ($volume in $bitlockerVolumes) {
            if ($volume.KeyProtector.RecoveryPassword) {
                $fileName = "BitLocker_Recovery_$($volume.MountPoint.TrimEnd(':'))_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                $filePath = Join-Path $ExportPath $fileName

                $recoveryInfo = @"
BitLocker Recovery Information
==============================
Mount Point: $($volume.MountPoint)
Recovery Password: $($volume.KeyProtector.RecoveryPassword)
Date Exported: $(Get-Date)
"@

                $recoveryInfo | Out-File -FilePath $filePath -Encoding UTF8
                Write-LogMessage "Exported BitLocker key for $($volume.MountPoint) to $filePath" -Level Info
                $exportedCount++
            }
        }

        if ($exportedCount -gt 0) {
            Write-LogMessage "🔐 Kunci pemulihan BitLocker diekspor." -Level Info
        }

        return $true
    }
    catch {
        Write-LogMessage "Failed to export BitLocker keys: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Creates a temporary local administrator account

.PARAMETER UserName
    Username for the temporary admin account

.PARAMETER Password
    Password for the temporary admin account
#>
function New-TemporaryAdminAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [string]$Password
    )

    if ($script:IsDryRun) {
        Write-LogMessage "[DRY RUN] Would create temporary admin account: $UserName" -Level Info
        return $true
    }

    try {
        # Check if user already exists
        $existingUser = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
        if ($existingUser) {
            Write-LogMessage "Temporary admin account $UserName already exists, removing..." -Level Warning
            Remove-LocalUser -Name $UserName -Confirm:$false
        }

        # Create new user
        $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $newUser = New-LocalUser -Name $UserName -Password $securePassword -Description "Temporary admin for BlueShift migration"

        # Add to Administrators group
        Add-LocalGroupMember -Group "Administrators" -Member $UserName

        Write-LogMessage "Created temporary admin account: $UserName" -Level Info
        return $true
    }
    catch {
        Write-LogMessage "Failed to create temporary admin account: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Removes the temporary administrator account

.PARAMETER UserName
    Username of the temporary admin account to remove
#>
function Remove-TemporaryAdminAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    if ($script:IsDryRun) {
        Write-LogMessage "[DRY RUN] Would remove temporary admin account: $UserName" -Level Info
        return $true
    }

    try {
        $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
        if ($user) {
            Remove-LocalUser -Name $UserName -Confirm:$false
            Write-LogMessage "Removed temporary admin account: $UserName" -Level Info
        }
        else {
            Write-LogMessage "Temporary admin account $UserName not found" -Level Warning
        }
        return $true
    }
    catch {
        Write-LogMessage "Failed to remove temporary admin account: $_" -Level Error
        return $false
    }
}

<#
.SYNOPSIS
    Gets the current Azure AD join status

.OUTPUTS
    Hashtable with join status information
#>
function Get-AzureADJoinStatus {
    [CmdletBinding()]
    param()

    try {
        $dsregStatus = dsregcmd /status

        $status = @{
            IsAzureADJoined = $false
            IsHybridJoined = $false
            UserPrincipalName = $null
            DeviceId = $null
            TenantId = $null
        }

        # Parse dsregcmd output
        foreach ($line in $dsregStatus) {
            if ($line -match "AzureAdJoined\s*:\s*(YES|NO)") {
                $status.IsAzureADJoined = $matches[1] -eq "YES"
            }
            elseif ($line -match "DomainJoined\s*:\s*(YES|NO)") {
                $status.IsHybridJoined = $matches[1] -eq "YES"
            }
            elseif ($line -match "UserPrincipalName\s*:\s*(.+)") {
                $status.UserPrincipalName = $matches[1].Trim()
            }
            elseif ($line -match "DeviceId\s*:\s*(.+)") {
                $status.DeviceId = $matches[1].Trim()
            }
            elseif ($line -match "TenantId\s*:\s*(.+)") {
                $status.TenantId = $matches[1].Trim()
            }
        }

        return $status
    }
    catch {
        Write-LogMessage "Failed to get Azure AD join status: $_" -Level Error
        return $null
    }
}

<#
.SYNOPSIS
    Monitors Azure AD join status with timeout

.PARAMETER TimeoutMinutes
    Maximum time to wait for join completion

.PARAMETER PollIntervalSeconds
    Interval between status checks
#>
function Wait-AzureADJoinCompletion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$TimeoutMinutes = 30,

        [Parameter(Mandatory = $false)]
        [int]$PollIntervalSeconds = 10
    )

    Write-LogMessage "Monitoring Azure AD join status (timeout: ${TimeoutMinutes} minutes)..." -Level Info

    $startTime = Get-Date
    $timeout = $startTime.AddMinutes($TimeoutMinutes)

    do {
        $status = Get-AzureADJoinStatus

        if ($status.IsAzureADJoined) {
            Write-LogMessage "✅ Azure AD join completed successfully" -Level Info
            return $true
        }

        Write-LogMessage "Waiting for Azure AD join completion... (AzureAdJoined: $($status.IsAzureADJoined))" -Level Info

        if ((Get-Date) -gt $timeout) {
            Write-LogMessage "❌ Azure AD join timeout after ${TimeoutMinutes} minutes" -Level Error
            return $false
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    } while ($true)
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-MigrationModule',
    'Write-LogMessage',
    'Test-PreflightChecks',
    'Export-BitLockerKeys',
    'New-TemporaryAdminAccount',
    'Remove-TemporaryAdminAccount',
    'Get-AzureADJoinStatus',
    'Wait-AzureADJoinCompletion'
)
