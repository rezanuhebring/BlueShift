# 🔵 BlueShift Migration Tool

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Windows](https://img.shields.io/badge/Windows-10/11-green.svg)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**BlueShift** is a comprehensive PowerShell-based migration tool designed to seamlessly transition Windows devices from Hybrid Active Directory Join to pure Azure Active Directory Join without data loss or device reimaging.

## 🌟 Key Features

- **No Data Loss**: Preserves user profiles, applications, and settings
- **Minimal Downtime**: Hands-on per-device migration with guided workflow
- **Safety First**: Comprehensive preflight checks and rollback capabilities
- **Flexible Options**: Support for both USMT and ForensiT profile migration engines
- **Bilingual Interface**: English and Indonesian language support
- **Dry-Run Mode**: Test migrations without making actual changes
- **BitLocker Support**: Automatic recovery key export and preservation
- **Comprehensive Logging**: Detailed logs and migration manifests

## 📋 System Requirements

### Supported Operating Systems
- Windows 10 version 21H2 or later
- Windows 11 version 22H2 or later

### Prerequisites
- **Administrator Privileges**: Must run as local administrator
- **Azure AD Credentials**: Target user must have Azure AD account
- **Network Access**: Connectivity to Azure AD endpoints required
- **PowerShell 5.1+**: Included with Windows 10/11
- **Disk Space**: Minimum 20GB free space (configurable)

### Optional Components
- **USMT (User State Migration Tool)**: For advanced profile migration
- **ForensiT Profwiz**: Alternative profile migration tool
- **Windows ADK**: Required for USMT installation

## 🚀 Quick Start

### 1. Download and Setup
```bash
# Clone or download the BlueShift repository
git clone <repository-url>
cd BlueShift

# Set execution policy (one-time setup)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 2. Configure Migration Settings
Edit `config/migration.json` to match your environment:
```json
{
  "UserPrincipalName": "user@contoso.onmicrosoft.com",
  "ProfileMigrationEngine": "USMT",
  "BackupRoot": "D:\\UserBackups",
  "Domain": {
    "LeaveDomain": true,
    "CreateTempLocalAdmin": true,
    "TempLocalAdminPassSecretRef": "env:MIGADMIN_PASS"
  }
}
```

### 3. Set Environment Variables
```powershell
# Set temporary admin password (required for domain leave)
$env:MIGADMIN_PASS = "YourSecureTempPassword123!"
```

### 4. Run Migration
```powershell
# CLI Mode (Recommended)
.\Start-Migration.ps1 -ConfigPath .\config\migration.json

# Dry-run mode (test without changes)
.\Start-Migration.ps1 -ConfigPath .\config\migration.json -DryRun

# GUI Mode
.\gui\MigHelper.GUI.ps1
```

## 📖 Detailed Usage

### Command Line Interface (CLI)

The CLI provides full control over the migration process:

```powershell
# Full migration with all steps
.\Start-Migration.ps1 -ConfigPath .\config\migration.json

# Skip specific steps
.\Start-Migration.ps1 -ConfigPath .\config\migration.json -SkipPreflight -SkipBackup

# Dry run for testing
.\Start-Migration.ps1 -ConfigPath .\config\migration.json -DryRun
```

#### CLI Parameters
- `-ConfigPath`: Path to migration configuration file (required)
- `-DryRun`: Enable dry-run mode for testing
- `-SkipPreflight`: Skip preflight validation checks
- `-SkipBackup`: Skip user data backup
- `-SkipBitLocker`: Skip BitLocker key export

### Graphical User Interface (GUI)

For users who prefer a visual interface:

```powershell
# Launch GUI
.\gui\MigHelper.GUI.ps1
```

The GUI provides:
- Step-by-step wizard interface
- Real-time progress indicators
- Indonesian language support
- One-click migration execution

## ⚙️ Configuration

### Migration Configuration File

The `config/migration.json` file controls all aspects of the migration:

```json
{
  "ProfileMigrationEngine": "USMT",
  "UserPrincipalName": "user@contoso.onmicrosoft.com",
  "BackupRoot": "D:\\UserBackups",
  "Safeguards": {
    "MinFreeDiskGB": 20,
    "RequireACPower": true,
    "RequireNetwork": true
  },
  "BitLocker": {
    "ExportRecoveryKey": true,
    "ExportDir": "artifacts/BitLocker"
  },
  "Domain": {
    "LeaveDomain": true,
    "CreateTempLocalAdmin": true,
    "TempLocalAdminName": "MigAdmin"
  }
}
```

### Environment Variables

Required environment variables:
- `MIGADMIN_PASS`: Password for temporary admin account

Optional environment variables:
- `CUSTOM_BACKUP_PATH`: Override default backup location
- `LOG_LEVEL`: Set logging verbosity (Info, Warning, Error)

## 🔄 Migration Process

### Phase 1: Preparation
1. **Preflight Checks**: System validation and safety verification
2. **User Data Backup**: Comprehensive backup using robocopy
3. **BitLocker Export**: Recovery key preservation

### Phase 2: Domain Transition
4. **Domain Leave**: Unjoin from Active Directory
5. **Temporary Admin**: Create local admin for post-migration access

### Phase 3: Azure AD Join
6. **Azure AD Guidance**: Interactive join process with monitoring
7. **Profile Migration**: Transfer user profiles to Azure AD account

### Phase 4: Cleanup
8. **Post-Join Tasks**: Application and cache cleanup
9. **Verification**: Confirm successful migration
10. **Rollback (if needed)**: Restore to previous state

## 🛡️ Safety & Rollback

### Safety Features
- **Dry-Run Mode**: Test all steps without changes
- **Comprehensive Logging**: Detailed operation logs
- **Backup Verification**: Hash-based integrity checking
- **Network Validation**: Azure AD connectivity testing
- **Power Management**: AC power requirement enforcement

### Rollback Process

If migration fails, the tool provides automatic rollback:

```powershell
# Manual rollback execution
.\scripts\Rollback-Restore.ps1 -ConfigPath .\config\migration.json
```

Rollback actions:
- Restore user data from backup
- Rejoin original domain (if possible)
- Remove temporary admin accounts
- Clean up migration artifacts

## 📊 Monitoring & Logging

### Log Files
All operations are logged to:
- `logs/migration_YYYYMMDD_HHMMSS.log`: Main migration log
- `logs/backup_robocopy_YYYYMMDD_HHMMSS.log`: Backup operation details

### Migration Manifest
Each migration creates a JSON manifest at:
- `artifacts/migration-manifest.json`

Contains:
- Migration timestamp and duration
- System information
- Success/failure status
- File counts and sizes
- Error details (if any)

## 🐛 Troubleshooting

### Common Issues

#### "Script must be run as Administrator"
**Solution**: Right-click PowerShell and select "Run as Administrator"

#### "No network connectivity detected"
**Solution**:
- Verify internet connection
- Check firewall settings
- Ensure Azure AD endpoints are accessible

#### "Insufficient disk space"
**Solution**:
- Free up disk space or change backup location
- Modify `MinFreeDiskGB` in configuration
- Use external storage for backups

#### "Azure AD join timeout"
**Solution**:
- Verify Azure AD credentials
- Check network connectivity to Azure AD
- Ensure device meets Azure AD requirements
- Try manual Azure AD join first

### Log Analysis

Check the migration logs for detailed error information:
```powershell
# View recent logs
Get-ChildItem logs\*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 5

# Search for errors
Select-String -Path logs\*.log -Pattern "ERROR|FAILED" -CaseSensitive:$false
```

## 🔒 Security Considerations

### Best Practices
- **Secure Passwords**: Use strong passwords for temporary admin accounts
- **Environment Variables**: Store sensitive data in environment variables
- **Backup Encryption**: Consider encrypting backup files
- **Network Security**: Ensure secure network connections
- **Access Control**: Limit tool access to authorized personnel

### Security Features
- No credentials stored in configuration files
- Temporary admin accounts are automatically removed
- Comprehensive audit logging
- No telemetry or data collection

## 🌏 Bilingual Support (English/Indonesian)

BlueShift includes full Indonesian language support:

### Bahasa Indonesia / Indonesian

**Panduan Cepat:**
```powershell
# Jalankan migrasi
.\Start-Migration.ps1 -ConfigPath .\config\migration.json

# Mode uji coba
.\Start-Migration.ps1 -ConfigPath .\config\migration.json -DryRun
```

**Fitur Utama:**
- ✅ Pemeriksaan awal lulus. Siap migrasi.
- 🔄 Membackup profil & data pengguna...
- ✅ Backup selesai.
- 🔐 Kunci pemulihan BitLocker diekspor.
- 🧩 Siap lepas dari domain on-prem.
- 🪄 Langkah manual diperlukan: Buka Settings > Accounts > Access work or school > Connect > Join this device to Azure Active Directory.
- 👤 Melakukan pemetaan profil ke akun AAD...
- ✅ Profil berhasil dipetakan.
- 🎉 Migrasi selesai. Silakan login dengan akun Azure AD.
- ↩️ Memulai rollback ke kondisi sebelum migrasi...
- ✅ Rollback selesai.

## 📦 Packaging & Deployment

### Single-File Executable
Create a standalone executable using PS2EXE:
```powershell
# Install PS2EXE module
Install-Module -Name ps2exe

# Create executable
ps2exe .\Start-Migration.ps1 .\BlueShift.exe -icon .\assets\icon.ico
```

### PowerShell Module Package
```powershell
# Create module package
New-ModuleManifest -Path .\BlueShift.psd1 -RootModule .\modules\MigHelper\MigHelper.psm1
```

## 🤝 Contributing

We welcome contributions! Please see our contributing guidelines:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### Development Setup
```powershell
# Clone repository
git clone <repository-url>
cd BlueShift

# Install development dependencies
Install-Module -Name Pester, PSScriptAnalyzer

# Run tests
Invoke-Pester

# Run code analysis
Invoke-ScriptAnalyzer -Path .\modules\MigHelper\MigHelper.psm1
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support & Documentation

### Documentation
- [User Guide](docs/user-guide.md)
- [Administrator Guide](docs/admin-guide.md)
- [Troubleshooting](docs/troubleshooting.md)
- [API Reference](docs/api-reference.md)

### Support
- **Issues**: [GitHub Issues](https://github.com/your-org/blueshift/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/blueshift/discussions)
- **Email**: support@blueshift-migration.com

### Community
- Join our [Discord Server](https://discord.gg/blueshift)
- Follow us on [Twitter](https://twitter.com/blueshifttool)

---

**BlueShift** - Seamless Windows Migration to Azure AD 🌟

*Built with ❤️ by IT-Engineering Team*
