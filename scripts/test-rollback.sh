#!/usr/bin/env bash
# Challenge 3 evidence: prove that a bad release is rolled back automatically.
# Run AFTER at least one successful Jenkins deployment (inventory-live exists).
#
# Usage: bash scripts/test-rollback.sh
set -euo pipefail

LIVE=inventory-live
BROKEN=inventory-api:broken

GOOD_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$LIVE")"
echo "== Currently live: $GOOD_IMAGE"
curl -fsS http://127.0.0.1:5050/ ; echo

echo "== Building a deliberately broken release (process exits immediately)"
printf 'FROM %s\nHEALTHCHECK NONE\nCMD ["python", "-c", "import sys; sys.exit(1)"]\n' "$GOOD_IMAGE" \
  | docker build -q -t "$BROKEN" -

echo "== Deploying the broken release (expected to FAIL and roll back)"
if TRIES=8 bash "$(dirname "$0")/deploy.sh" "$BROKEN"; then
  echo "UNEXPECTED: broken release passed validation"; exit 1
fi

echo "== After rollback"
NOW="$(docker inspect -f '{{.Config.Image}}' "$LIVE")"
docker ps --filter "name=inventory-live" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
curl -fsS -i http://127.0.0.1:5050/health
echo
if [ "$NOW" = "$GOOD_IMAGE" ]; then
  echo "RESULT: PASS - $GOOD_IMAGE was restored and is healthy"
else
  echo "RESULT: FAIL - live image is $NOW"; exit 1
fi
docker rmi "$BROKEN" >/dev/null 2>&1 || true
