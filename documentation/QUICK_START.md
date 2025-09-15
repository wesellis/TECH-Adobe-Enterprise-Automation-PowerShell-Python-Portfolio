# Quick Start Guide

## 5-Minute Setup

### 1. Prerequisites Check (30 seconds)
```powershell
# Windows PowerShell
$PSVersionTable.PSVersion
python --version
```

### 2. Clone & Setup (1 minute)
```bash
git clone https://github.com/wesellis/adobe-enterprise-automation.git
cd adobe-enterprise-automation
python -m venv venv
.\venv\Scripts\activate
pip install -r requirements.txt
```

### 3. Configure Credentials (2 minutes)
Create `config.json`:
```json
{
    "adobe": {
        "org_id": "YOUR_ORG@AdobeOrg",
        "client_id": "YOUR_CLIENT_ID",
        "client_secret": "YOUR_SECRET"
    }
}
```

### 4. Test Connection (30 seconds)
```powershell
.\Test-AdobeConnection.ps1
```

### 5. First Automation (1 minute)
```powershell
# Provision a user
.\New-AdobeUser.ps1 -Email "user@company.com" -Products "Creative Cloud"

# Check licenses
.\Get-LicenseReport.ps1
```

## Common Tasks

### User Management
```powershell
# Add user
.\Add-AdobeUser.ps1 -Email "user@company.com"

# Remove user
.\Remove-AdobeUser.ps1 -Email "user@company.com"

# Bulk import
.\Import-UsersFromCSV.ps1 -Path "users.csv"
```

### License Management
```powershell
# View usage
.\Get-LicenseUsage.ps1

# Optimize licenses
.\Optimize-Licenses.ps1 -ReclaimInactive

# Generate report
.\Export-LicenseReport.ps1 -Format Excel
```

### Deployment
```powershell
# Deploy to single machine
.\Deploy-CreativeCloud.ps1 -ComputerName "PC001"

# Deploy to multiple
.\Deploy-CreativeCloud.ps1 -ComputerList "computers.txt"

# Silent install
.\Install-AdobeCC.ps1 -Silent -NoRestart
```

## Troubleshooting

### Connection Issues
```powershell
# Test API connection
.\Test-Connection.ps1 -Verbose

# Verify credentials
.\Validate-Credentials.ps1
```

### Common Errors
- **401 Unauthorized**: Check API credentials
- **403 Forbidden**: Verify permissions
- **429 Too Many Requests**: Implement rate limiting
- **500 Server Error**: Retry with exponential backoff

## Next Steps
- Read [Implementation Guide](IMPLEMENTATION_GUIDE.md)
- Explore [API Reference](API_REFERENCE.md)
- Join our [Community](https://github.com/wesellis/adobe-enterprise-automation/discussions)