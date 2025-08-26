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
      # HTTP
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      # HTTPS
      - N8N_SSL_KEY=/certs/selfsigned.key
      - N8N_SSL_CERT=/certs/selfsigned.crt
      - N8N_PORT_HTTPS=5679
    depends_on:
      - postgres
    volumes:
      - ./n8n-data:/home/node/.n8n
      - ./certs:/certs
