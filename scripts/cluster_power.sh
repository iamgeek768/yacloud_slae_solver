#!/usr/bin/env bash
# Включает или выключает ВМ кластера, не пересоздавая их.
# Использование: scripts/cluster_power.sh start | stop
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_state

action=${1:-}
case "$action" in
  start) want=RUNNING ;;
  stop) want=STOPPED ;;
  *) echo "использование: $0 start | stop" >&2; exit 1 ;;
esac

mapfile -t nodes < <(terraform -chdir="$ROOT/terraform" output -json nodes | jq -r 'keys[]')
for node in "${nodes[@]}"; do
  echo "$action $node"
  yc compute instance "$action" "$node" --async > /dev/null 2>&1 || echo "  $node: команда не прошла (возможно, ВМ уже в нужном состоянии)"
done

echo "Жду, пока все ВМ перейдут в состояние $want..."
for _ in $(seq 1 60); do
  states=$(for node in "${nodes[@]}"; do yc compute instance get "$node" --format json 2> /dev/null | jq -r .status; done | sort -u | tr '\n' ' ')
  [ "$states" = "$want " ] && break
  sleep 5
done
echo "Состояние ВМ: $states"

if [ "$action" = start ]; then
  "$ROOT/scripts/allow_my_ip.sh"
  # После запуска у главной ВМ новый публичный адрес — обновляем его в состоянии Terraform.
  "$ROOT/scripts/tf.sh" apply -refresh-only -auto-approve -input=false > /dev/null
  echo "Публичный адрес главной ВМ: $(tf_output master_public_ip)"
  "$ROOT/scripts/wait_cluster.sh"
fi
