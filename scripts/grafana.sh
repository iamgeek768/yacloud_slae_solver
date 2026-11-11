#!/usr/bin/env bash
# Локальная Grafana с дашбордом кластера (данные — из Managed Service for Prometheus).
# Использование: scripts/grafana.sh [up|down]
# IAM-токен действует 12 часов: когда графики перестанут грузиться, запустите скрипт снова.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

cd "$ROOT/monitoring"
if [ "${1:-up}" = down ]; then
  docker compose down
  exit 0
fi

workspace=$(tf_output prometheus_workspace_id)
[ -n "$workspace" ] || { echo "в terraform.tfvars не задан prometheus_workspace_id" >&2; exit 1; }

umask 077
printf 'YC_IAM_TOKEN=%s\nPROMETHEUS_WORKSPACE_ID=%s\n' "$(yc_token)" "$workspace" > .env
docker compose up -d --force-recreate
echo "Grafana: http://localhost:3000/d/slae-cluster"
