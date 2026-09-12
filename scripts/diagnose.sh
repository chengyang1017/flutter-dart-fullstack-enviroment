#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/infra/docker-compose.yml"
ENV_FILE="$REPO_ROOT/.env"

compose=(docker compose -f "$COMPOSE_FILE")
if [ -f "$ENV_FILE" ]; then
  compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
fi

"${compose[@]}" ps

echo
echo "Workbench health:"
curl -fsS "http://localhost:${APP_PORT:-8080}/health" || true

echo
echo "Runner health:"
curl -fsS "http://localhost:${RUNNER_PORT:-8787}/health" || true

echo
echo "Recent logs:"
"${compose[@]}" logs --tail=80 flutter-app flutter-runner
