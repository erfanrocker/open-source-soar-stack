#!/bin/bash
# SOAR Stack Deployment Script
# Run on Linux server (Ubuntu 22.04+ / Debian 12+)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] $*${NC}"; exit 1; }

# Check root
if [ "$EUID" -ne 0 ]; then
  error "Run as root"
fi

# Config
STACK_DIR="/opt/soar-stack"
DOMAIN="${DOMAIN:-yourdomain.com}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@yourdomain.com}"

log "=== SOAR Stack Deployment ==="
log "Domain: $DOMAIN"
log "Stack directory: $STACK_DIR"

# 1. Install dependencies
log "Installing dependencies..."
apt-get update && apt-get install -y \
  docker.io docker-compose-plugin \
  curl jq htpasswd \
  nvidia-container-toolkit 2>/dev/null || true

systemctl enable --now docker

# 2. Create docker network
log "Creating docker network..."
docker network create soar-net 2>/dev/null || true

# 3. Setup directory structure
log "Setting up directories..."
mkdir -p "$STACK_DIR"/{traefik,ollama,wazuh,misp,zammad,mattermost,n8n,openclaw}
mkdir -p "$STACK_DIR"/traefik/letsencrypt
mkdir -p "$STACK_DIR"/wazuh/{config,active-response}
mkdir -p "$STACK_DIR"/n8n/{custom-nodes,workflows}

# 4. Generate passwords if .env doesn't exist
if [ ! -f "$STACK_DIR/.env" ]; then
  log "Generating .env file..."
  cat > "$STACK_DIR/.env" <<EOF
# Generated $(date)
DOMAIN=$DOMAIN
ADMIN_EMAIL=$ADMIN_EMAIL

# Traefik
TRAEFIK_DASHBOARD_AUTH=$(htpasswd -nb admin "$(openssl rand -base64 16)" | sed 's/\$/\$\$/g')

# n8n
N8N_DB_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
N8N_BASIC_AUTH_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)
N8N_ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)

# MISP
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
MISP_DB_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
MISP_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
MISP_GPG_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)

# Zammad
ZAMMAD_DB_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
ZAMMAD_RAILS_MASTER_KEY=$(openssl rand -base64 64 | tr -d '/+=' | cut -c1-64)

# Mattermost
MATTERMOST_DB_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)

# Wazuh
WAZUH_INDEXER_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
WAZUH_MANAGER_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
WAZUH_API_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
WAZUH_REGISTRATION_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
WAZUH_DASHBOARD_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)

# OPNsense (configure manually in OPNsense UI)
OPNSENSE_API_KEY=CHANGE_ME
OPNSENSE_API_SECRET=CHANGE_ME
OPNSENSE_HOST=firewall.$DOMAIN

# SMTP (configure for your environment)
SMTP_HOST=smtp.$DOMAIN
SMTP_PORT=587
SMTP_USER=noreply@$DOMAIN
SMTP_PASSWORD=CHANGE_ME
EOF
  chmod 600 "$STACK_DIR/.env"
  warn "Generated .env at $STACK_DIR/.env - REVIEW AND UPDATE VALUES!"
fi

# 5. Copy config files (assumes they're in current dir)
log "Copying configuration files..."
cp -r traefik/* "$STACK_DIR/traefik/"
cp -r ollama/* "$STACK_DIR/ollama/"
cp -r wazuh/* "$STACK_DIR/wazuh/"
cp -r misp/* "$STACK_DIR/misp/"
cp -r zammad/* "$STACK_DIR/zammad/"
cp -r mattermost/* "$STACK_DIR/mattermost/"
cp -r n8n/* "$STACK_DIR/n8n/"

# Make active response scripts executable
chmod +x "$STACK_DIR/wazuh/active-response"/*

# 6. Deploy in order
log "Deploying Traefik (reverse proxy)..."
cd "$STACK_DIR/traefik" && docker compose up -d

log "Deploying Ollama + OpenClaw..."
cd "$STACK_DIR/ollama" && docker compose up -d
sleep 30
docker exec soar-ollama ollama pull llama3:70b || true
docker exec soar-ollama ollama pull mistral:7b || true

log "Deploying Wazuh..."
cd "$STACK_DIR/wazuh" && docker compose up -d

log "Deploying MISP..."
cd "$STACK_DIR/misp" && docker compose up -d

log "Deploying Zammad..."
cd "$STACK_DIR/zammad" && docker compose up -d

log "Deploying Mattermost..."
cd "$STACK_DIR/mattermost" && docker compose up -d

log "Deploying n8n..."
cd "$STACK_DIR/n8n" && docker compose up -d

# 7. Wait for services
log "Waiting for services to stabilize..."
sleep 60

# 8. Initialize MISP
log "Initializing MISP..."
docker exec soar-misp /init.sh 2>/dev/null || true

# 9. Initialize Zammad
log "Initializing Zammad..."
docker exec soar-zammad-init zammad init 2>/dev/null || true

# 10. Import n8n workflows
log "Importing n8n workflows..."
sleep 10
for wf in "$STACK_DIR/n8n/workflows"/*.json; do
  docker exec soar-n8n n8n import:workflow --input="$wf" 2>/dev/null || true
done

# 11. Activate workflows
docker exec soar-n8n n8n update:workflow --id=1 --active=true 2>/dev/null || true
docker exec soar-n8n n8n update:workflow --id=2 --active=true 2>/dev/null || true

log "=== Deployment Complete ==="
echo ""
echo "Access URLs:"
echo "  Traefik Dashboard: https://traefik.$DOMAIN"
echo "  n8n:               https://n8n.$DOMAIN"
echo "  Wazuh:             https://wazuh.$DOMAIN"
echo "  MISP:              https://misp.$DOMAIN"
echo "  Zammad:            https://zammad.$DOMAIN"
echo "  Mattermost:        https://chat.$DOMAIN"
echo "  Ollama API:        https://ollama.$DOMAIN"
echo "  OpenClaw:          https://ai.$DOMAIN"
echo ""
echo "Credentials stored in: $STACK_DIR/.env"
echo ""
warn "NEXT STEPS:"
echo "1. Update DNS: Point all subdomains to this server IP"
echo "2. Configure OPNsense API credentials in .env"
echo "3. Configure SMTP settings in .env"
echo "4. Install Wazuh agents on endpoints"
echo "5. Configure MISP feeds (CIRCL, AlienVault, etc.)"
echo "6. Test end-to-end: trigger Wazuh alert -> verify ticket + Mattermost"
echo "7. Set up backups (see backup.sh)"