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
      - "5678:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=n8npassword
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - N8N_HOST=0.0.0.0
      - NODE_ENV=production
    depends_on:
      - postgres
    volumes:
      - ./n8n-data:/home/node/.n8n
