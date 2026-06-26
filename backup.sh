#!/bin/bash
# SOAR Stack Backup Script
# Run daily via cron: 0 3 * * * /opt/soar-stack/backup.sh

set -euo pipefail

STACK_DIR="/opt/soar-stack"
BACKUP_DIR="/mnt/backups/soar-stack/$(date +%Y-%m-%d)"
RETENTION_DAYS=30

mkdir -p "$BACKUP_DIR"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "Starting backup to $BACKUP_DIR"

# Load env
source "$STACK_DIR/.env"

# 1. Backup databases
log "Backing up databases..."

# n8n postgres
docker exec soar-n8n-postgres pg_dump -U n8n n8n | gzip > "$BACKUP_DIR/n8n_postgres.sql.gz"

# MISP mariadb
docker exec soar-misp-db mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" misp | gzip > "$BACKUP_DIR/misp_mariadb.sql.gz"

# Zammad postgres
docker exec soar-zammad-postgres pg_dump -U zammad zammad | gzip > "$BACKUP_DIR/zammad_postgres.sql.gz"

# Mattermost postgres
docker exec soar-mattermost-postgres pg_dump -U mmuser mattermost | gzip > "$BACKUP_DIR/mattermost_postgres.sql.gz"

# 2. Backup volumes
log "Backing up volumes..."

# n8n data
docker run --rm -v soar_n8n-data:/data -v "$BACKUP_DIR":/backup alpine tar czf /backup/n8n_data.tar.gz -C /data .

# MISP data
docker run --rm -v soar_misp-data:/data -v "$BACKUP_DIR":/backup alpine tar czf /backup/misp_data.tar.gz -C /data .

# Zammad data
docker run --rm -v soar_zammad-data:/data -v "$BACKUP_DIR":/backup alpine tar czf /backup/zammad_data.tar.gz -C /data .

# Mattermost data
docker run --rm -v soar_mattermost-data:/data -v "$BACKUP_DIR":/backup alpine tar czf /backup/mattermost_data.tar.gz -C /data .

# Wazuh data
docker run --rm -v soar_wazuh-manager-data:/data -v "$BACKUP_DIR":/backup alpine tar czf /backup/wazuh_manager_data.tar.gz -C /data .
docker run --rm -v soar_wazuh-indexer-data:/data -v "$BACKUP_DIR":/backup alpine tar czf /backup/wazuh_indexer_data.tar.gz -C /data .

# 3. Backup configs
log "Backing up configurations..."
tar czf "$BACKUP_DIR/configs.tar.gz" -C "$STACK_DIR" \
  traefik/ ollama/ wazuh/config/ misp/ zammad/ mattermost/ n8n/ .env

# 4. Cleanup old backups
log "Cleaning up backups older than $RETENTION_DAYS days..."
find /mnt/backups/soar-stack -type d -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true

log "Backup completed: $BACKUP_DIR"
du -sh "$BACKUP_DIR"