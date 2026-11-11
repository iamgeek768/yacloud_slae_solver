#!/usr/bin/env bash
# Запуск расчёта на кластере. Выполняется на главной ВМ от пользователя mpi.
# Использование: run_solver.sh [NP] [THREADS] [аргументы решателя...]
#   NP      — число MPI-процессов (по умолчанию — число узлов, по одному на узел)
#   THREADS — число потоков OpenMP на процесс (по умолчанию — число ядер узла)
set -euo pipefail
source /etc/slae/env

HOSTFILE=/opt/slae/hostfile
NP=${1:-$(grep -c . "$HOSTFILE")}
THREADS=${2:-$NODE_CORES}
EXTRA=("${@:3}")

export SLAE_RUN_ID=${SLAE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}
export OMP_NUM_THREADS=$THREADS

S3="https://storage.yandexcloud.net/$BUCKET"
OUT=/opt/slae/out/$SLAE_RUN_ID
LOG=/var/log/slae/solver.log
mkdir -p "$OUT"

log() {
  printf '{"ts":"%s","level":"%s","run_id":"%s","host":"%s","msg":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$1" "$SLAE_RUN_ID" "$NODE_NAME" "$2" | tee -a "$LOG" "$OUT/solver.log"
}

log INFO "run started: np=$NP threads=$THREADS"

# Все узлы подтягивают свежие исходники и матрицу — новая матрица не требует перезагрузки ВМ.
pids=()
while read -r host _; do
  ssh -n "$host" /opt/slae/bin/fetch_data.sh &
  pids+=($!)
done < "$HOSTFILE"
for pid in "${pids[@]}"; do
  wait "$pid" || { log ERROR "data refresh failed on one of the nodes, see /var/log/slae/node.log there"; exit 1; }
done
[ -f /opt/slae/data/matrix.bin ] || { log ERROR "no matrix: upload input/matrix.bin to the bucket first"; exit 1; }

set +e
mpirun --hostfile "$HOSTFILE" -np "$NP" --map-by node --bind-to none \
  --mca btl tcp,self --mca btl_tcp_if_include "$NETWORK_CIDR" --mca oob_tcp_if_include "$NETWORK_CIDR" \
  -x OMP_NUM_THREADS -x SLAE_RUN_ID \
  /opt/slae/bin/slae_solver --input /opt/slae/data/matrix.bin \
  --output "$OUT/x.bin" --stats "$OUT/result.json" "${EXTRA[@]}" 2>&1 | tee -a "$LOG" "$OUT/solver.log"
rc=${PIPESTATUS[0]}
set -e

if [ "$rc" -eq 0 ]; then
  log INFO "run finished: solver converged"
else
  log ERROR "run finished: solver exit code $rc"
fi

TOKEN=$(curl -sf -H 'Metadata-Flavor: Google' \
  http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token | jq -er .access_token)
put() { curl -sf --retry 3 -H "Authorization: Bearer $TOKEN" --upload-file "$1" "$S3/$2" > /dev/null; }

for f in x.bin result.json solver.log; do
  if [ -f "$OUT/$f" ]; then
    put "$OUT/$f" "results/$SLAE_RUN_ID/$f"
  fi
done
put /opt/slae/bin/slae_solver bin/slae_solver

echo "RUN_ID=$SLAE_RUN_ID"
exit "$rc"
