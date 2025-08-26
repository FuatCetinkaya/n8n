#!/bin/bash
set -e

mkdir -p ~/n8n-docker
cd ~/n8n-docker

# Self-signed sertifika oluştur
mkdir -p certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certs/selfsigned.key \
  -out certs/selfsigned.crt \
  -subj "/CN=localhost"


cat > docker-compose.yml << 'EOF'
version: "3.8"

services:
  postgres:
    image: postgres:15
    restart: always
    environment:
      POSTGRES_USER: n8n
      POSTGRES_PASSWORD: n8npassword
      POSTGRES_DB: n8n
    volumes:
      - ./postgres-data:/var/lib/postgresql/data

  n8n:
    image: n8nio/n8n:latest
    restart: always
    ports:
      - "5678:5678"   # HTTP
      - "5679:5679"   # HTTPS
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=n8npassword
      - N8N_HOST=$(curl -s ifconfig.me)
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - N8N_SSL_KEY=/certs/selfsigned.key
      - N8N_SSL_CERT=/certs/selfsigned.crt
      - N8N_PORT_HTTPS=5679
    depends_on:
      - postgres
    volumes:
      - ./n8n-data:/home/node/.n8n
      - ./certs:/certs
EOF


#docker compose up -d
