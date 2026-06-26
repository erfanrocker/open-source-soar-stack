#!/bin/bash
set -e

echo "================================================="
echo "  🛡️ SOAR Open Source Auto-Setup"
echo "================================================="

read -p "🌐 Domain n8n (e.g., soar.mydomain.com): " DOMAIN_N8N
read -p "🌐 Domain Mattermost (e.g., chat.mydomain.com): " DOMAIN_CHAT
read -p "📧 Email Admin: " EMAIL_ADMIN

# Generate Secrets
N8N_KEY=$(openssl rand -hex 32)
DB_PASS=$(openssl rand -base64 16)

# Create .env
cat > .env <<EOL
TZ=Asia/Jakarta
N8N_WEBHOOK_URL=https://${DOMAIN_N8N}/
MM_SITE_URL=https://${DOMAIN_CHAT}
N8N_ENCRYPTION_KEY=${N8N_KEY}
MM_DB_PASSWORD=${DB_PASS}
DOMAIN_N8N=${DOMAIN_N8N}
DOMAIN_CHAT=${DOMAIN_CHAT}
EMAIL_ADMIN=${EMAIL_ADMIN}
EOL

# Create Nginx Config
mkdir -p nginx
cat > nginx/default.conf <<EOL
server {
    listen 80;
    server_name ${DOMAIN_N8N} ${DOMAIN_CHAT};
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN_N8N};
    ssl_certificate /etc/letsencrypt/live/${DOMAIN_N8N}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_N8N}/privkey.pem;
    location / {
        proxy_pass http://n8n:5678;
        proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade";
    }
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN_CHAT};
    ssl_certificate /etc/letsencrypt/live/${DOMAIN_CHAT}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_CHAT}/privkey.pem;
    client_max_body_size 50M;
    location / {
        proxy_pass http://mattermost:8065;
        proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade";
    }
}
EOL

echo "✅ Configuration generated!"
echo "👉 Jalankan 'source .env' lalu gunakan Certbot untuk SSL."