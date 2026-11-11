#!/usr/bin/env bash
# Мониторинг узла: node_exporter на каждом узле; на главной ВМ — Prometheus,
# который опрашивает все узлы и пишет метрики в Managed Service for Prometheus.
set -euo pipefail
source /etc/slae/env

if [ -z "${PROMETHEUS_WORKSPACE_ID:-}" ]; then
  echo "мониторинг выключен: не задан PROMETHEUS_WORKSPACE_ID"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get install -y -q prometheus-node-exporter
systemctl enable --now prometheus-node-exporter

[ "${IS_MASTER:-0}" = 1 ] || exit 0

apt-get install -y -q prometheus

install -m 0644 /etc/slae/prometheus.yml /etc/prometheus/prometheus.yml
install -m 0644 /etc/slae/prometheus-rules.yml /etc/prometheus/slae_rules.yml
# Метрики хранятся в Monium, локально достаточно короткого буфера.
echo 'ARGS="--storage.tsdb.retention.time=2h"' > /etc/default/prometheus

systemctl enable prometheus
systemctl restart prometheus
