#!/usr/bin/env bash
set -euo pipefail

BASE="http://localhost"
SERVICES=(
  "posts|${BASE}/v1/posts"
  "search|${BASE}/v1/search"
  "image|${BASE}/v1/image"
  "status|${BASE}/v1/status"
  "feed-discovery|${BASE}/v1/feed-discovery"
)

echo "==> Telescope service health check"
echo ""
for item in "${SERVICES[@]}"; do
  name="${item%%|*}"
  url="${item##*|}"
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
  if [[ "$code" =~ ^(200|201|301|302|404)$ ]]; then
    echo "  ✓  ${name} (HTTP ${code})"
  else
    echo "  ✗  ${name} (HTTP ${code}) — ${url}"
  fi
done

echo ""
echo "  Traefik dashboard: $(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null || echo '000')"
echo "  Prometheus:        $(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/-/ready 2>/dev/null || echo '000')"
echo "  Grafana:           $(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/api/health 2>/dev/null || echo '000')"
