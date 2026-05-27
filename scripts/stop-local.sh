#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TELESCOPE_DIR="$ROOT_DIR/telescope"

echo "==> Stopping monitoring overlay..."
cd "$ROOT_DIR"
docker compose -f docker/docker-compose.override.yml down 2>/dev/null || true

echo "==> Stopping Telescope core stack..."
cd "$TELESCOPE_DIR"
docker compose --env-file .env down

echo "==> Done. Volumes preserved. Use --volumes to also delete data."
