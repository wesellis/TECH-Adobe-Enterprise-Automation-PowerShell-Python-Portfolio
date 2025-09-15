# Configuration Management for Adobe Enterprise Automation

## Configuration Files

### Adobe API Configuration
- `adobe-config.json` - Adobe API credentials and endpoints
- `adobe-config.template.json` - Template with placeholder values

### PowerShell Module Configuration
- `powershell-config.json` - PowerShell execution policies and module settings
- `ad-integration-config.json` - Active Directory integration settings

### Python Environment Configuration
- `python-requirements.txt` - Python package dependencies
- `logging-config.json` - Logging configuration for Python scripts

## Security Notes

⚠️ **IMPORTANT**: Never commit actual API keys or secrets to version control.

Use environment variables or secure credential management systems:
- Azure Key Vault
- Windows Credential Manager
- Environment variables with `.env` files (excluded from git)

## Sample Configuration Structure

```json
{
  "adobe": {
    "client_id": "${ADOBE_CLIENT_ID}",
    "client_secret": "${ADOBE_CLIENT_SECRET}",
    "org_id": "${ADOBE_ORG_ID}",
    "technical_account_id": "${ADOBE_TECH_ACCOUNT_ID}",
    "private_key_path": "${ADOBE_PRIVATE_KEY_PATH}"
  },
  "active_directory": {
    "domain": "corp.company.com",
    "ou_path": "OU=Users,DC=corp,DC=company,DC=com"
  },
  "processing": {
    "max_concurrent_jobs": 20,
    "batch_size": 100,
    "timeout_seconds": 300
  }
}
```