#!/usr/bin/env bash
# Скачивает результаты запуска из Object Storage в results/<run_id>/.
# Использование: scripts/fetch_results.sh <run_id>
set -euo pipefail
source "$(dirname "$0")/lib.sh"

run_id=${1:?укажите run_id (его печатает запуск расчёта)}
bucket=$(tf_output bucket)
token=$(yc_token)
dir=$ROOT/results/$run_id
mkdir -p "$dir"

for f in result.json solver.log x.bin; do
  if curl -sf --retry 3 -H "Authorization: Bearer $token" -o "$dir/$f" \
    "$S3_ENDPOINT/$bucket/results/$run_id/$f"; then
    echo "$dir/$f"
  else
    echo "нет объекта results/$run_id/$f" >&2
  fi
done
