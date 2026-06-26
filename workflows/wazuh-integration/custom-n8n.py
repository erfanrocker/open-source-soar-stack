#!/usr/bin/env python3
import json, sys, requests, logging

# Konfigurasi
N8N_WEBHOOK = "http://<IP_HOST_SERVER>:5678/webhook/wazuh-alert" # Setup.sh bisa replace ini jika perlu
logging.basicConfig(filename='/var/ossec/logs/integration-n8n.log', level=logging.INFO)

try:
    alert_data = sys.stdin.read()
    requests.post(N8N_WEBHOOK, json=json.loads(alert_data), timeout=10)
    logging.info(f"Alert forwarded to n8n")
except Exception as e:
    logging.error(f"Failed: {e}")