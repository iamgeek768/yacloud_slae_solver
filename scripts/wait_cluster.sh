#!/usr/bin/env bash
# Ждёт, пока на всех узлах отработает cloud-init и узлы будут готовы к расчёту.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ip=$(tf_output master_public_ip)
# У пересозданной ВМ новый ключ хоста — старую запись для этого адреса убираем.
touch "$KNOWN_HOSTS"
ssh-keygen -R "$ip" -f "$KNOWN_HOSTS" > /dev/null 2>&1 || true
ssh-keygen -R "[$ip]:$(tf_output ssh_port)" -f "$KNOWN_HOSTS" > /dev/null 2>&1 || true

echo "Жду SSH на главной ВМ $ip..."
for attempt in $(seq 1 60); do
  if master_ssh true 2> /dev/null; then
    break
  fi
  if [ "$attempt" -eq 60 ]; then
    echo "главная ВМ не отвечает по SSH" >&2
    exit 1
  fi
  sleep 5
done

echo "Жду завершения cloud-init на главной ВМ..."
master_ssh "cloud-init status --wait" || true

echo "Проверяю готовность узлов..."
master_ssh "sudo -iu mpi bash -s" << 'EOF'
set -u
failed=0
while read -r host _; do
  ok=0
  for attempt in $(seq 1 90); do
    if ssh -n -o ConnectTimeout=5 "$host" test -f /var/lib/slae/ready 2> /dev/null; then
      ok=1
      break
    fi
    sleep 10
  done
  if [ "$ok" -eq 1 ]; then
    echo "  $host: готов"
  else
    echo "  $host: НЕ готов"
    failed=1
  fi
done < /opt/slae/hostfile
exit "$failed"
EOF
echo "Кластер готов."
