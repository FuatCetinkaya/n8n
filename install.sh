#!/usr/bin/env bash
set -euo pipefail

# -------------------------
# CONFIG (dilersen değiştir)
# -------------------------
APP_DIR="${HOME}/n8n-https"
N8N_VERSION="latest"           # istersen sabitle: "1.72.0"
POSTGRES_IMAGE="postgres:15"
DB_NAME="n8n"
DB_USER="n8n"
DB_PASS="n8npassword"
CERT_DAYS=365
# -------------------------

echo "==> Başlıyor: n8n (self-signed HTTPS + nginx proxy) kurulumu"

# root kontrolü tavsiye edilir (port 80/443 için)
if [ "$(id -u)" -ne 0 ]; then
  echo "UYARI: script'i root olarak çalıştırman önerilir (port 80/443 izinleri için). Yine de devam ediyorum."
fi

# 1) Public IP tespit et (kullanıcı isterse elle değiştirilebilir)
PUBLIC_IP="$(curl -s https://ifconfig.me || true)"
if [ -z "$PUBLIC_IP" ]; then
  # fallback: kullanıcıya sor
  read -r -p "Sunucu genel IP'si tespit edilemedi. Lütfen IP gir (örn: 45.155.124.82): " PUBLIC_IP
fi
echo "  - Public IP: ${PUBLIC_IP}"

# 2) port kontrol (80 veya 443 doluysa uyar)
check_port() {
  if ss -ltn "( sport = :$1 )" | grep -q LISTEN; then
    echo "HATA: Port $1 zaten kullanımda. Önce kapat veya farklı port kullan."
    exit 1
  fi
}
check_port 80 || true
check_port 443 || true

# 3) Klasör yapısı
mkdir -p "${APP_DIR}"
cd "${APP_DIR}"
mkdir -p certs nginx/conf.d n8n-data postgres-data

# 4) Self-signed sertifika (SAN ile IP)
echo "  - Self-signed sertifika oluşturuluyor (CN ve SAN = ${PUBLIC_IP})..."
OPENSSL_CNF="${APP_DIR}/certs/openssl.cnf"
cat > "${OPENSSL_CNF}" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = ${PUBLIC_IP}

[v3_req]
subjectAltName = @alt_names

[alt_names]
IP.1 = ${PUBLIC_IP}
EOF

openssl req -x509 -nodes -days "${CERT_DAYS}" \
  -newkey rsa:2048 \
  -keyout "${APP_DIR}/certs/server.key" \
  -out "${APP_DIR}/certs/server.crt" \
  -config "${OPENSSL_CNF}" \
  -extensions v3_req \
  -subj "/CN=${PUBLIC_IP}"

chmod 600 "${APP_DIR}/certs/server.key"
echo "  - Sertifika: ${APP_DIR}/certs/server.crt"
echo "  - Private key: ${APP_DIR}/certs/server.key"

# 5) nginx conf
cat > nginx/conf.d/default.conf <<'NGINXCONF'
server {
    listen 80;
    server_name _;

    # Redirect all HTTP to HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name _;

    ssl_certificate /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    # Security headers (minimal)
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    location / {
        proxy_pass http://n8n:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 90;
    }
}
NGINXCONF

# 6) docker-compose.yml oluştur
cat > docker-compose.yml <<EOF
version: "3.8"

services:
  postgres:
    image: ${POSTGRES_IMAGE}
    restart: always
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASS}
      POSTGRES_DB: ${DB_NAME}
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 5s
      timeout: 3s
      retries: 20

  n8n:
    image: n8nio/n8n:${N8N_VERSION}
    restart: always
    depends_on:
      - postgres
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${DB_NAME}
      - DB_POSTGRESDB_USER=${DB_USER}
      - DB_POSTGRESDB_PASSWORD=${DB_PASS}
      - N8N_HOST=${PUBLIC_IP}
      - N8N_PORT=443
      - N8N_PROTOCOL=https
      - N8N_SECURE_COOKIE=true
      - NODE_ENV=production
    volumes:
      - ./n8n-data:/home/node/.n8n

  nginx:
    image: nginx:stable-alpine
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./certs:/etc/nginx/certs:ro
    depends_on:
      - n8n
EOF

# 7) İzinler
chown -R 1000:1000 n8n-data || true
chmod -R 755 nginx || true

# 8) Docker kontrolleri & başlat
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker bulunamadı. Kurulum deneniyor..."
  curl -fsSL https://get.docker.com | sh
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin bulunamadı. apt paket ile kuruluyor..."
  apt-get update -y
  apt-get install -y docker-compose-plugin
fi

# Eğer daha önce aynı dizinde çalıştıysanız, kapat ve temizle
docker compose down -v || true

echo "  - İmajlar çekiliyor..."
docker compose pull --ignore-pull-failures

echo "  - Servisler başlatılıyor..."
docker compose up -d

# 9) Servislerin ayağa kalkmasını bekle (max 120s)
echo "  - Servislerin hazır olmasını bekliyorum (HTTPS kontrol edilecek)..."
TRIES=0
MAX_TRIES=60
SLEEP=2
until curl -ksI --max-time 5 "https://${PUBLIC_IP}" >/dev/null 2>&1 || [ $TRIES -ge $MAX_TRIES ]; do
  TRIES=$((TRIES+1))
  sleep "$SLEEP"
done

if [ $TRIES -ge $MAX_TRIES ]; then
  echo "UYARI: HTTPS üzerinde n8n erişilemedi (zaman aşımı). 'docker compose ps' ve 'docker compose logs' kontrol et."
  echo "  docker compose ps"
  echo "  docker compose logs -f"
  exit 1
fi

echo ""
echo "✅ Kurulum tamam. n8n artık HTTPS üzerinden erişilebilir (self-signed sertifika)."
echo "   URL: https://${PUBLIC_IP}"
echo ""
echo "Notlar:"
echo " - Tarayıcın sertifikayı güvenilir kabul etmeyecektir (self-signed)."
echo "   Kendi bilgisayarında uyarıyı kaldırmak için server.crt dosyasını güvenilen kök sertifika deposuna ekle."
echo " - n8n backend: http://n8n:5678 (nginx reverse proxy aracılığıyla sunulur)."
echo ""
echo "Kontroller:"
echo "  docker compose ps"
echo "  docker compose logs -f"
