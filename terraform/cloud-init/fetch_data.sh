#!/usr/bin/env bash
# Скачивает из Object Storage исходники решателя и матрицу, собирает решатель.
# Выполняется при каждом запуске ВМ (slae-fetch.service) и перед каждым расчётом.
set -euo pipefail
source /etc/slae/env

S3="https://storage.yandexcloud.net/$BUCKET"
LOG=/var/log/slae/node.log

log() {
  printf '{"ts":"%s","level":"%s","host":"%s","msg":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$1" "$NODE_NAME" "$2" >> "$LOG"
}

# Повторяет команду: сразу после создания ВМ права сервисного аккаунта
# и сеть могут быть ещё не готовы.
retry() {
  local attempts=$1 pause=$2
  shift 2
  for ((i = 1; i <= attempts; i++)); do
    "$@" && return 0
    sleep "$pause"
  done
  return 1
}

# IAM-токен сервисного аккаунта ВМ — из сервиса метаданных, ключей на диске нет.
fetch_token() {
  TOKEN=$(curl -sf -H 'Metadata-Flavor: Google' \
    http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token | jq -er .access_token)
}

get() { curl -sf -H "Authorization: Bearer $TOKEN" -o "$2" "$S3/$1"; }

etag() {
  curl -sfI -H "Authorization: Bearer $TOKEN" "$S3/$1" | tr -d '\r"' | awk 'tolower($1) == "etag:" {print $2}'
}

retry 20 6 fetch_token || { log ERROR "cannot get IAM token from metadata service"; exit 1; }

for f in slae_solver.c Makefile; do
  retry 20 6 get "src/$f" "/opt/slae/src/$f.new" || { log ERROR "cannot download src/$f"; exit 1; }
  if cmp -s "/opt/slae/src/$f.new" "/opt/slae/src/$f"; then
    rm "/opt/slae/src/$f.new"
  else
    mv "/opt/slae/src/$f.new" "/opt/slae/src/$f"
  fi
done

if make -s -C /opt/slae/src SRC=slae_solver.c BUILD=/opt/slae/bin >> "$LOG.build" 2>&1; then
  log INFO "solver is built"
else
  log ERROR "solver build failed, see $LOG.build"
  exit 1
fi

# Отсутствие матрицы — не ошибка: кластер можно поднять раньше, чем загружены данные.
remote_etag=$(etag input/matrix.bin || true)
if [ -z "$remote_etag" ]; then
  log WARN "input/matrix.bin is not in the bucket yet"
elif [ -f /opt/slae/data/matrix.bin ] && [ "$remote_etag" = "$(cat /opt/slae/data/matrix.etag 2>/dev/null)" ]; then
  log INFO "matrix is up to date"
else
  retry 3 5 get input/matrix.bin /opt/slae/data/matrix.bin.part || { log ERROR "cannot download input/matrix.bin"; exit 1; }
  mv /opt/slae/data/matrix.bin.part /opt/slae/data/matrix.bin
  echo "$remote_etag" > /opt/slae/data/matrix.etag
  log INFO "matrix downloaded, $(stat -c %s /opt/slae/data/matrix.bin) bytes"
fi
