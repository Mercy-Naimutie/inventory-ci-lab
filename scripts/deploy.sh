#!/usr/bin/env bash
# Challenge 3 (option a): deploy with automatic rollback.
#
# Usage: bash scripts/deploy.sh <image:tag>
#
# 1. The current live container is stopped and kept as "inventory-live-previous".
# 2. The new image is started as "inventory-live" on 127.0.0.1:5050.
# 3. Post-deployment validation polls /health (and /api/items).
# 4. If validation fails, the new container is removed and the previous
#    container is restored and re-validated. The script exits non-zero so
#    Jenkins marks the build as FAILED even though the service was recovered.
set -euo pipefail

NEW_IMAGE="${1:?usage: deploy.sh <image:tag>}"
LIVE="${LIVE:-inventory-live}"
PREV="${PREV:-inventory-live-previous}"
PORT="${PORT:-5050}"
TRIES="${TRIES:-20}"

log() { echo "[deploy] $*"; }

validate() {
  for _ in $(seq 1 "$TRIES"); do
    if curl -fsS "http://127.0.0.1:${PORT}/health" 2>/dev/null | grep -q '"status":"ok"'; then
      curl -fsS "http://127.0.0.1:${PORT}/api/items" >/dev/null && return 0
    fi
    sleep 1
  done
  return 1
}

exists() { docker inspect "$1" >/dev/null 2>&1; }

# Only one backup generation is kept.
docker rm -f "$PREV" >/dev/null 2>&1 || true

if exists "$LIVE"; then
  log "Preserving current container ($(docker inspect -f '{{.Config.Image}}' "$LIVE")) as $PREV"
  docker stop -t 10 "$LIVE" >/dev/null       # SIGTERM -> gunicorn finishes in-flight requests
  docker rename "$LIVE" "$PREV"
fi

log "Starting $NEW_IMAGE as $LIVE on 127.0.0.1:${PORT}"
if docker run -d --name "$LIVE" --restart unless-stopped \
      -e APP_VERSION="${NEW_IMAGE##*:}" \
      -p "127.0.0.1:${PORT}:5000" "$NEW_IMAGE" >/dev/null && validate; then
  log "Post-deployment validation PASSED - $NEW_IMAGE is live"
  exists "$PREV" && log "Previous version kept (stopped) as $PREV for manual rollback"
  exit 0
fi

log "Post-deployment validation FAILED for $NEW_IMAGE - rolling back"
docker logs --tail 30 "$LIVE" 2>&1 || true
docker rm -f "$LIVE" >/dev/null 2>&1 || true

if exists "$PREV"; then
  docker rename "$PREV" "$LIVE"
  docker start "$LIVE" >/dev/null
  if validate; then
    log "ROLLBACK OK - restored $(docker inspect -f '{{.Config.Image}}' "$LIVE")"
  else
    log "ROLLBACK FAILED - previous version is not healthy either"
  fi
else
  log "No previous container to restore (first deployment)"
fi
exit 1
