#!/usr/bin/env bash
set -euo pipefail

# ---- Ayarlar (istersen değiştir) ----
N8N_VERSION="latest"                    # istersen sabitle: örn "1.72.0"
POSTGRES_IMAGE="postgres:15"
APP_DIR="${HOME}/n8n-docker"
N8N_HTTP_PORT=5678
DB_NAME="n8n"
DB_USER="n8n"
DB_PASS="n8npassword"
# -------------------------------------

echo "[1/6] Ortam hazırlanıyor..."
mkdir -p "${APP_DIR}"
cd "${APP_DIR}"

# Eski compose dosyasını varsa kaldıralım (aynı dizinde koşmuşsan)
if [ -f docker-compose.yml ]; then
  echo "  - Var olan compose kapatılıyor..."
  docker compose down -v || true
fi

echo "[2/6] docker-compose.yml yazılıyor..."
cat > docker-compose.yml <<'EOF'
version: "3.8"

services:
  postgres:
    image: POSTGRES_IMAGE_PLACEHOLDER
    restart: always
    environment:
      POSTGRES_USER: DB_USER_PLACEHOLDER
      POSTGRES_PASSWORD: DB_PASS_PLACEHOLDER
      POSTGRES_DB: DB_NAME_PLACEHOLDER
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U DB_USER_PLACEHOLDER -d DB_NAME_PLACEHOLDER"]
      interval: 5s
      timeout: 3s
      retries: 20

  n8n:
    image: n8nio/n8n:N8N_VERSION_PLACEHOLDER
    restart: always
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "N8N_HTTP_PORT_PLACEHOLDER:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=DB_NAME_PLACEHOLDER
      - DB_POSTGRESDB_USER=DB_USER_PLACEHOLDER
      - DB_POSTGRESDB_PASSWORD=DB_PASS_PLACEHOLDER
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
    volumes:
      - ./n8n-data:/home/node/.n8n
EOF

# Yer tutucuları doldur
sed -i "s|POSTGRES_IMAGE_PLACEHOLDER|${POSTGRES_IMAGE}|g" docker-compose.yml
sed -i "s|N8N_VERSION_PLACEHOLDER|${N8N_VERSION}|g" docker-compose.yml
sed -i "s|N8N_HTTP_PORT_PLACEHOLDER|${N8N_HTTP_PORT}|g" docker-compose.yml
sed -i "s|DB_NAME_PLACEHOLDER|${DB_NAME}|g" docker-compose.yml
sed -i "s|DB_USER_PLACEHOLDER|${DB_USER}|g" docker-compose.yml
sed -i "s|DB_PASS_PLACEHOLDER|${DB_PASS}|g" docker-compose.yml

echo "[3/6] Klasör izinleri ayarlanıyor..."
mkdir -p n8n-data postgres-data
# n8n konteyneri 'node' (1000:1000) ile çalışır
chown -R 1000:1000 n8n-data || true

echo "[4/6] Docker ve compose kontrol ediliyor..."
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker yok, kurulum yapılıyor..."
  curl -fsSL https://get.docker.com | sh
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin yok, kurulum yapılıyor..."
  apt-get update -y && apt-get install -y docker-compose-plugin
fi

echo "[5/6] İmajlar çekiliyor..."
docker compose pull

echo "[6/6] Servisler ayağa kalkıyor..."
docker compose up -d

echo ""
echo "✅ n8n çalışıyor olmalı."
echo "   HTTP:  http://$(curl -s ifconfig.me 2>/dev/null || echo 'SUNUCU_IPINIZ'):${N8N_HTTP_PORT}"
echo ""
echo "Kontrol için:"
echo "  docker ps"
echo "  docker logs -f n8n-docker-n8n-1"
