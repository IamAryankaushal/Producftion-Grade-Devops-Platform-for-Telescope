#!/usr/bin/env bash
SERVICE="${1:-}"
cd "$(dirname "$0")/../telescope"
if [ -z "$SERVICE" ]; then
  docker compose --env-file .env logs -f --tail=50
else
  docker compose --env-file .env logs -f --tail=100 "$SERVICE"
fi
