#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TELESCOPE_DIR="$ROOT_DIR/telescope"

echo "==> Telescope DevOps — Local Docker Compose startup"

# Use upstream env.development as base, fix Linux-specific values
cp "$TELESCOPE_DIR/config/env.development" "$TELESCOPE_DIR/.env"

# Fix path separator (Windows uses ; Linux uses :)
sed -i 's/COMPOSE_PATH_SEPARATOR=;/COMPOSE_PATH_SEPARATOR=:/' "$TELESCOPE_DIR/.env"

# Fix compose file list separator
sed -i 's/docker-compose.yml;docker/docker-compose.yml:docker/g' "$TELESCOPE_DIR/.env"
sed -i 's/development.yml;docker/development.yml:docker/g' "$TELESCOPE_DIR/.env"
sed -i 's/docker-compose.yml;docker\/supabase/docker-compose.yml:docker\/supabase/g' "$TELESCOPE_DIR/.env"

# Fix service URLs to use container names instead of 127.0.0.1
sed -i 's|REDIS_URL=redis://127.0.0.1|REDIS_URL=redis://redis:6379|' "$TELESCOPE_DIR/.env"
sed -i 's|ELASTIC_URL=http://127.0.0.1|ELASTIC_URL=http://elasticsearch|' "$TELESCOPE_DIR/.env"

echo "    [✓] .env prepared from config/env.development"

cd "$TELESCOPE_DIR"

echo "==> Installing Node dependencies..."
pnpm install

echo "==> Starting Telescope core stack..."
docker compose --env-file .env up -d --build \
  redis \
  elasticsearch \
  traefik \
  posts \
  search \
  image \
  feed-discovery \
  status \
  sso \
  parser \
  login \
  rss-bridge

echo ""
echo "==> Waiting 30s for Elasticsearch to initialize..."
sleep 30

echo ""
echo "==> Starting monitoring overlay..."
cd "$ROOT_DIR"

# Get the actual network name Docker created
NETWORK_NAME=$(docker network ls --format '{{.Name}}' | grep -i telescope | head -1)
echo "    [✓] Found network: $NETWORK_NAME"

# Update the override file with the correct network name
sed -i "s/name: telescope_telescope_default/name: $NETWORK_NAME/" \
  "$ROOT_DIR/docker/docker-compose.override.yml"

docker compose \
  -f docker/docker-compose.override.yml \
  up -d

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Telescope is running locally                        ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  API Gateway (Traefik) →  http://localhost:80        ║"
echo "║  Traefik Dashboard     →  http://localhost:8080      ║"
echo "║  Posts API             →  http://localhost/v1/posts  ║"
echo "║  Status API            →  http://localhost/v1/status ║"
echo "║  Prometheus            →  http://localhost:9090      ║"
echo "║  Grafana               →  http://localhost:3001      ║"
echo "║                           admin / telescope123       ║"
echo "╚══════════════════════════════════════════════════════╝"
