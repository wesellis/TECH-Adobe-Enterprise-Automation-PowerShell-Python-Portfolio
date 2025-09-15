#!/bin/bash

# Adobe Automation Backup Script
# Creates comprehensive backup of all system components

set -e

# Configuration
BACKUP_DIR="/backup/adobe-automation"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="adobe_automation_backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create backup directory
echo -e "${GREEN}Starting Adobe Automation Backup...${NC}"
mkdir -p "${BACKUP_PATH}"

# Function to check command success
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1 failed${NC}"
        exit 1
    fi
}

# 1. Backup Database
echo -e "${YELLOW}Backing up database...${NC}"
docker exec adobe-automation-db /opt/mssql-tools/bin/sqlcmd \
    -S localhost -U SA -P "${DB_PASSWORD}" \
    -Q "BACKUP DATABASE [AdobeAutomation] TO DISK = N'/var/opt/mssql/backup/${BACKUP_NAME}.bak' WITH FORMAT, INIT, COMPRESSION"
docker cp adobe-automation-db:/var/opt/mssql/backup/${BACKUP_NAME}.bak ${BACKUP_PATH}/database.bak
check_status "Database backup"

# 2. Backup Configuration Files
echo -e "${YELLOW}Backing up configuration...${NC}"
cp -r config/ ${BACKUP_PATH}/config
cp .env ${BACKUP_PATH}/.env 2>/dev/null || true
cp docker-compose.yml ${BACKUP_PATH}/
check_status "Configuration backup"

# 3. Backup Scripts
echo -e "${YELLOW}Backing up scripts...${NC}"
cp -r creative-cloud/ ${BACKUP_PATH}/creative-cloud
cp -r python-automation/ ${BACKUP_PATH}/python-automation
check_status "Scripts backup"

# 4. Backup Certificates
echo -e "${YELLOW}Backing up certificates...${NC}"
if [ -d "/etc/adobe-certs" ]; then
    cp -r /etc/adobe-certs ${BACKUP_PATH}/certificates
    check_status "Certificates backup"
fi

# 5. Backup Redis Data
echo -e "${YELLOW}Backing up Redis cache...${NC}"
docker exec adobe-automation-redis redis-cli BGSAVE
sleep 5
docker cp adobe-automation-redis:/data/dump.rdb ${BACKUP_PATH}/redis.rdb
check_status "Redis backup"

# 6. Backup Logs
echo -e "${YELLOW}Backing up logs...${NC}"
cp -r logs/ ${BACKUP_PATH}/logs
check_status "Logs backup"

# 7. Backup Prometheus Data
echo -e "${YELLOW}Backing up metrics data...${NC}"
docker run --rm -v adobe-automation_prometheus-data:/data -v ${BACKUP_PATH}:/backup \
    busybox tar czf /backup/prometheus-data.tar.gz /data
check_status "Prometheus backup"

# 8. Backup Grafana Dashboards
echo -e "${YELLOW}Backing up Grafana dashboards...${NC}"
docker exec adobe-automation-grafana grafana-cli admin export-dashboard-json > ${BACKUP_PATH}/grafana-dashboards.json
check_status "Grafana backup"

# 9. Create backup manifest
echo -e "${YELLOW}Creating backup manifest...${NC}"
cat > ${BACKUP_PATH}/manifest.json <<EOF
{
    "backup_date": "$(date -Iseconds)",
    "backup_name": "${BACKUP_NAME}",
    "system_version": "$(git describe --tags --always)",
    "components": {
        "database": "database.bak",
        "configuration": "config/",
        "scripts": ["creative-cloud/", "python-automation/"],
        "redis": "redis.rdb",
        "prometheus": "prometheus-data.tar.gz",
        "grafana": "grafana-dashboards.json",
        "logs": "logs/"
    },
    "size": "$(du -sh ${BACKUP_PATH} | cut -f1)",
    "checksum": ""
}
EOF

# 10. Create checksum
echo -e "${YELLOW}Creating integrity checksum...${NC}"
CHECKSUM=$(find ${BACKUP_PATH} -type f -exec sha256sum {} \; | sha256sum | cut -d' ' -f1)
sed -i "s/\"checksum\": \"\"/\"checksum\": \"${CHECKSUM}\"/" ${BACKUP_PATH}/manifest.json
check_status "Checksum creation"

# 11. Compress backup
echo -e "${YELLOW}Compressing backup...${NC}"
cd ${BACKUP_DIR}
tar czf ${BACKUP_NAME}.tar.gz ${BACKUP_NAME}/
check_status "Backup compression"

# 12. Encrypt backup (optional)
if [ ! -z "${BACKUP_ENCRYPTION_KEY}" ]; then
    echo -e "${YELLOW}Encrypting backup...${NC}"
    openssl enc -aes-256-cbc -salt -in ${BACKUP_NAME}.tar.gz -out ${BACKUP_NAME}.tar.gz.enc -k "${BACKUP_ENCRYPTION_KEY}"
    rm ${BACKUP_NAME}.tar.gz
    check_status "Backup encryption"
fi

# 13. Upload to cloud storage (optional)
if [ ! -z "${AZURE_STORAGE_ACCOUNT}" ]; then
    echo -e "${YELLOW}Uploading to Azure Storage...${NC}"
    az storage blob upload \
        --account-name ${AZURE_STORAGE_ACCOUNT} \
        --container-name backups \
        --name ${BACKUP_NAME}.tar.gz.enc \
        --file ${BACKUP_NAME}.tar.gz.enc
    check_status "Cloud upload"
fi

# 14. Cleanup old backups (keep last 30 days)
echo -e "${YELLOW}Cleaning up old backups...${NC}"
find ${BACKUP_DIR} -name "adobe_automation_backup_*.tar.gz*" -mtime +30 -delete
check_status "Cleanup"

# 15. Send notification
if [ ! -z "${WEBHOOK_URL}" ]; then
    curl -X POST ${WEBHOOK_URL} \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"Backup completed successfully: ${BACKUP_NAME}\"}"
fi

# Final summary
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Backup completed successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Backup Name: ${BACKUP_NAME}"
echo "Location: ${BACKUP_PATH}"
echo "Size: $(du -sh ${BACKUP_PATH}.tar.gz* | cut -f1)"
echo "Checksum: ${CHECKSUM}"

# Clean up temporary backup directory
rm -rf ${BACKUP_PATH}

exit 0