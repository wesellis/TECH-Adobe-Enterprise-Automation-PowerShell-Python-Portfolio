# Logs directory for Adobe automation scripts
# All logs are automatically generated here with timestamps

## Log File Naming Convention
- `provisioning-YYYY-MM-DD.log` - User provisioning logs
- `licensing-YYYY-MM-DD.log` - License management logs  
- `deployment-YYYY-MM-DD.log` - Software deployment logs
- `processing-YYYY-MM-DD.log` - Python batch processing logs

## Log Retention
- Logs are retained for 90 days by default
- Configure retention policy in main config files
- Production environments should implement log rotation

## Security
- Logs may contain sensitive information
- Ensure proper access controls
- Consider log encryption for compliance requirements