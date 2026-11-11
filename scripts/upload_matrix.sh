#!/usr/bin/env bash
# Загружает матрицу в Object Storage как input/matrix.bin.
# Использование: scripts/upload_matrix.sh [файл]   (по умолчанию data/matrix.bin)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

file=${1:-$ROOT/data/matrix.bin}
[ -f "$file" ] || { echo "нет файла $file" >&2; exit 1; }

bucket=$(tf_output bucket)
token=$(yc_token)
echo "Загружаю $file ($(stat -c %s "$file") байт) в $bucket/input/matrix.bin..."
curl -f --retry 3 -H "Authorization: Bearer $token" --upload-file "$file" \
  "$S3_ENDPOINT/$bucket/input/matrix.bin" -o /dev/null -w 'готово за %{time_total} с\n' -sS
