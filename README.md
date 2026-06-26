# 🛡️ Open Source SOAR Stack (AI-Driven)

SOAR (Security Orchestration, Automation, and Response) 100% Gratis & Open Source menggunakan **n8n**, **Wazuh**, **Ollama (Local LLM)**, dan **Mattermost**. Stack ini dirancang untuk mendeteksi ancaman, menganalisis risiko menggunakan AI lokal, dan merespons secara otomatis (misal: blokir IP di Firewall).

> **Privasi Data**: Semua pemrosesan AI dan data log dilakukan secara *self-hosted*. Tidak ada data yang dikirim ke pihak ketiga.

## 🏗️ Arsitektur
```
[Host: Wazuh] ──(Python Webhook)──▶ [Docker: n8n] ──(Internal)──▶ [Docker: Ollama AI]
                                       │                                │
                                       ▼                                ▼
                               [Docker: Mattermost]            [Analisis Threat Lokal]
                                       ▲
                                       │
                                [Nginx Reverse Proxy]
                                (HTTPS, Routing, SSL)
```

## 🚀 Quick Start

### 1. Clone Repositori
```bash
git clone https://github.com/USERNAME/open-source-soar-stack.git
cd open-source-soar-stack
```

### 2. Jalankan Installer
Skrip ini akan meminta domain Anda dan generate konfigurasi secara otomatis.
```bash
chmod +x setup.sh
./setup.sh
```

### 3. Generate SSL (Let's Encrypt)
```bash
sudo apt install certbot -y
source .env
sudo certbot certonly --standalone -d  $ DOMAIN_N8N -d  $ DOMAIN_CHAT --agree-tos --email  $ EMAIL_ADMIN
```

### 4. Deploy Stack
```bash
docker compose up -d
```

## 🛡️ Integrasi Wazuh
Karena Wazuh berjalan di Host (bukan Docker), lakukan langkah berikut di server Wazuh:

1. Copy skrip integrasi:
   ```bash
   sudo cp wazuh-integration/custom-n8n.py /var/ossec/integrations/
   sudo chown wazuh:wazuh /var/ossec/integrations/custom-n8n.py
   sudo chmod +x /var/ossec/integrations/custom-n8n.py
   ```
2. Daftarkan di `/var/ossec/etc/ossec.conf`:
   ```xml
   <integration>
     <name>custom-n8n.py</name>
     <rule_id>5712,5710,1002,5502,5503</rule_id>
     <level>6</level>
     <alert_format>json</alert_format>
   </integration>
   ```
3. Restart Wazuh: `sudo systemctl restart wazuh-manager`

## 🤖 Import Workflow n8n
1. Buka `https://<DOMAIN_N8N>`
2. Buat akun admin.
3. Import file `workflows/soar-ai-analyzer.json`.
4. Tambahkan Credential **HTTP Basic Auth** untuk Wazuh API (`wazuh-wui`).
5. Aktifkan workflow.

## 🔒 Keamanan
- Jangan expose port `11434` (Ollama) ke publik.
- Gunakan firewall (UFW) untuk membatasi akses hanya ke port `80` dan `443`.
- Backup volume Docker secara berkala.