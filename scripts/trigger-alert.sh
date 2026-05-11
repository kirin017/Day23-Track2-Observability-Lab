#!/usr/bin/env bash
## Trigger the ServiceDown alert by stopping the app, wait for it to fire,
## then restore the app and wait specifically for ServiceDown to resolve.
## Other alerts (for example SLO burn alerts) are ignored.

set -euo pipefail

service_down_count() {
  curl -fsS http://localhost:9093/api/v2/alerts 2>/dev/null \
    | grep '"alertname":"ServiceDown"' \
    | grep -c '"state":"active"' || true
}

echo "Step 1: kill app container"
docker stop day23-app >/dev/null

echo "Step 2: wait for ServiceDown alert to fire"
for i in {1..30}; do
  sleep 5
  alerts=$(service_down_count)
  if [ "$alerts" -gt 0 ]; then
    echo "  ServiceDown fired (after ${i}*5s)"
    break
  fi
  echo "  ServiceDown not active yet (${i}*5s)"
done

echo "Step 3: restart app"
docker start day23-app >/dev/null

echo "Step 4: wait for ServiceDown to resolve"
for i in {1..24}; do
  sleep 5
  alerts=$(service_down_count)
  if [ "$alerts" -eq 0 ]; then
    echo "  ServiceDown resolved"
    exit 0
  fi
  echo "  ServiceDown still active (${i}*5s)"
done

echo "ServiceDown did not resolve within 120s" >&2
exit 1
