#!/bin/bash
set -e

if ! command -v docker &> /dev/null
then
    echo "Docker bulunamadı. Kuruluyor..."
    curl -fsSL https://get.docker.com | sh
fi

if ! command -v docker compose &> /dev/null
then
    echo "Docker Compose plugin bulunamadı. Kuruluyor..."
    apt-get update && apt-get install -y docker-compose-plugin
fi


mkdir -p ~/n8n && cd ~/n8n


cat > docker-compose.yml <<'EOF'
version: "3.9"
services:
  postgres:
    image: postgres:15
    restart: always
    environment:
      POSTGRES_USER: n8n
      POSTGRES_PASSWORD: n8n
      POSTGRES_DB: n8n
    volumes:
      - ./db:/var/lib/postgresql/data

  n8n:
    image: n8nio/n8n:latest
    restart: always
    ports:
      - "5678:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=n8n
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=admin
      - N8N_HOST=45.155.124.82
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
    depends_on:
      - postgres
    volumes:
      - ./n8n:/home/node/.n8n
      - ./certs:/certs
    command: >
      sh -c "n8n start --tunnel"
EOF

# 4. Self-signed SSL üret (dns yok diye)
mkdir -p certs
openssl req -x509 -newkey rsa:4096 -nodes -keyout certs/server.key -out certs/server.crt -days 365 -subj "/CN=45.155.124.82"

echo "Self-signed sertifika oluşturuldu: ./certs/server.crt ve ./certs/server.key"

# 5. Container’ları ayağa kaldır
docker compose up -d

echo "Kurulum tamam ✅"
echo "👉 HTTP:  http://ipadres:5678"
echo "👉 HTTPS: https://ipadres:5678"
