#!/bin/bash
set -e

mkdir -p ~/n8n/data
mkdir -p ~/n8n/certs

cd ~/n8n

# 1. Self-signed sertifika üret
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certs/selfsigned.key \
  -out certs/selfsigned.crt \
  -subj "/C=TR/ST=Istanbul/L=Istanbul/O=n8n/OU=Dev/CN=45.155.124.82"

# 2. docker-compose.yml oluştur
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  n8n:
    image: n8nio/n8n
    restart: always
    environment:
      - N8N_HOST=45.155.124.82
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - WEBHOOK_TUNNEL_URL=https://45.155.124.82
      - GENERIC_TIMEZONE=Europe/Istanbul
    networks:
      - n8nnet

  nginx:
    image: nginx:alpine
    restart: always
    ports:
      - "443:443"
    volumes:
      - ./certs:/etc/nginx/certs
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - n8n
    networks:
      - n8nnet

networks:
  n8nnet:
    driver: bridge
EOF

# 3. Nginx config
cat > nginx.conf <<'EOF'
events {}
http {
  server {
    listen 443 ssl;
    server_name 45.155.124.82;

    ssl_certificate     /etc/nginx/certs/selfsigned.crt;
    ssl_certificate_key /etc/nginx/certs/selfsigned.key;

    location / {
      proxy_pass         http://n8n:5678;
      proxy_set_header   Host $host;
      proxy_set_header   X-Real-IP $remote_addr;
      proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header   X-Forwarded-Proto https;
    }
  }
}
EOF

# 4. Servisi ayağa kaldır
docker compose up -d
