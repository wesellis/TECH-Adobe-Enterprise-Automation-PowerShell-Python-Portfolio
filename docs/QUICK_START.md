# Adobe Enterprise Automation - Quick Start Guide

## 🚀 Get Started in 15 Minutes

This guide will help you quickly deploy and test the Adobe Enterprise Automation solutions.

## Prerequisites

### System Requirements
- **Windows Server 2016+** or **Windows 10/11**
- **PowerShell 5.1+** (PowerShell 7.x recommended)
- **Python 3.8+** (for batch processing components)
- **Active Directory** access (read/write permissions)
- **Adobe Admin Console** access with API credentials

### Required Permissions
- Local Administrator rights on target machines
- Active Directory user management permissions
- Adobe Admin Console System Administrator role
- Azure AD Application Administrator (if using Azure AD integration)

## Step 1: Initial Setup (5 minutes)

### Clone the Repository
```powershell
git clone https://github.com/your-org/adobe-enterprise-automation.git
cd adobe-enterprise-automation
```

### Install PowerShell Dependencies
```powershell
# Install required PowerShell modules
Install-Module -Name ActiveDirectory -Force
Install-Module -Name AzureAD -Force
Install-Module -Name Microsoft.Graph -Force

# Verify installations
Get-Module -ListAvailable | Where-Object {$_.Name -like "*Adobe*" -or $_.Name -like "*Azure*"}
```

### Install Python Dependencies
```bash
# Create virtual environment
python -m venv venv
.\venv\Scripts\activate  # Windows
# source venv/bin/activate  # Linux/macOS

# Install required packages
pip install -r python-automation/requirements.txt
```

## Step 2: Configuration (5 minutes)

### Setup Adobe API Configuration
```powershell
# Copy template configuration
copy-item "config\adobe-config.template.json" "config\adobe-config.json"

# Edit configuration with your values
notepad "config\adobe-config.json"
```

**Replace these values in the config file:**
```json
{
  "adobe": {
    "client_id": "YOUR_ADOBE_CLIENT_ID",
    "client_secret": "YOUR_ADOBE_CLIENT_SECRET", 
    "org_id": "YOUR_ADOBE_ORG_ID",
    "technical_account_id": "YOUR_TECH_ACCOUNT_ID"
  }
}
```

### Setup Environment Variables (Recommended)
```powershell
# Set environment variables for security
$env:ADOBE_CLIENT_ID = "your_client_id_here"
$env:ADOBE_CLIENT_SECRET = "your_client_secret_here"
$env:ADOBE_ORG_ID = "your_org_id_here"
```

## Step 3: Test Basic Functionality (5 minutes)

### Test 1: Adobe API Connectivity
```powershell
# Navigate to user provisioning directory
cd "creative-cloud\user-provisioning"

# Run provisioning script in test mode
.\Invoke-AdobeUserProvisioning.ps1 -TestMode
```

**Expected Output:**
```
✓ Configuration loaded successfully
✓ Adobe API authentication successful
TEST MODE: Simulating Adobe authentication
Found 0 users pending Adobe provisioning
```

### Test 2: License Management
```powershell
# Navigate to license management directory  
cd "..\license-management"

# Run license audit in test mode
.\Optimize-AdobeLicenses.ps1 -Operation Audit -TestMode
```

**Expected Output:**
```
=== Adobe License Management Started - Operation: Audit ===
Found 1000 optimization opportunities
Audit complete. Report: .\reports\License-Optimization-Report-20240315.html
```

### Test 3: Software Deployment Check
```powershell
# Navigate to software deployment directory
cd "..\software-deployment"

# Run deployment inventory
.\Deploy-CreativeCloud.ps1 -Operation Inventory -TestMode
```

**Expected Output:**
```
=== Adobe Creative Cloud Enterprise Deployment Started ===
Found 5 active target computers
Inventory complete: Computer01 - 3 Adobe products found
```

## Step 4: Run Your First Automation

### Scenario: Provision a Test User

1. **Create a test user in Active Directory:**
```powershell
# Create test user (replace with your domain)
New-ADUser -Name "Test Adobe User" -GivenName "Test" -Surname "User" -UserPrincipalName "testuser@yourdomain.com" -Department "Creative" -Enabled $true
```

2. **Run user provisioning:**
```powershell
cd "creative-cloud\user-provisioning"
.\Invoke-AdobeUserProvisioning.ps1 -TestMode
```

3. **Check the results:**
- Review the log file in `logs\provisioning-[date].log`
- Check the provisioning metrics in the console output

### Scenario: Optimize License Usage

1. **Run license optimization:**
```powershell
cd "creative-cloud\license-management"
.\Optimize-AdobeLicenses.ps1 -Operation Optimize -TestMode
```

2. **Review the report:**
- Open the generated HTML report in your browser
- Review cost savings opportunities
- Check utilization metrics

## Troubleshooting

### Common Issues & Solutions

**Issue: "Adobe API authentication failed"**
```
Solution: Verify your API credentials in the config file
Check: Adobe Admin Console → Integrations → Your App
```

**Issue: "Failed to retrieve pending users"**
```
Solution: Verify Active Directory permissions
Check: Get-ADUser cmdlet works correctly
```

**Issue: "PowerShell execution policy restriction"**
```powershell
# Fix: Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Issue: "Python module not found"**
```bash
# Fix: Ensure virtual environment is activated
.\venv\Scripts\activate
pip list  # Verify packages are installed
```

### Log Locations
- **PowerShell logs**: `logs\provisioning-[date].log`
- **Python logs**: `logs\processing-[date].log`
- **System logs**: Windows Event Viewer → Applications and Services Logs

### Getting Help

1. **Check Documentation**: Review files in `documentation\` folder
2. **Enable Debug Logging**: Add `-Verbose` parameter to PowerShell commands
3. **Test Mode**: Always use `-TestMode` for safe testing
4. **Community Support**: Check README.md for community resources

## Next Steps

Once you've verified basic functionality:

1. **Review Implementation Guide** - `documentation\IMPLEMENTATION_GUIDE.md`
2. **Explore API Reference** - `documentation\API_REFERENCE.md`
3. **Configure Production Settings** - Update config files for your environment
4. **Setup Monitoring** - Configure alerts and dashboards
5. **Schedule Automation** - Setup Windows Task Scheduler jobs

## Production Deployment Checklist

- [ ] API credentials configured and tested
- [ ] Service accounts created with proper permissions
- [ ] Backup procedures in place
- [ ] Monitoring and alerting configured
- [ ] Documentation reviewed and customized
- [ ] Stakeholder training completed
- [ ] Rollback procedures documented
- [ ] Security review completed

## Sample Commands Reference

```powershell
# User Provisioning
.\Invoke-AdobeUserProvisioning.ps1 -TestMode
.\Invoke-AdobeUserProvisioning.ps1 -ConfigPath "custom-config.json"

# License Management  
.\Optimize-AdobeLicenses.ps1 -Operation Audit
.\Optimize-AdobeLicenses.ps1 -Operation Reallocate -TestMode

# Software Deployment
.\Deploy-CreativeCloud.ps1 -Operation Deploy -TargetComputers "OU=Workstations"
.\Deploy-CreativeCloud.ps1 -Operation Inventory

# Python Batch Processing
python adobe_batch_processor.py --operation convert --input-dir ".\input" --output-dir ".\output"
```

---

🎉 **Congratulations!** You're now ready to leverage Adobe Enterprise Automation to streamline your organization's Adobe ecosystem management.