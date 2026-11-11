#!/usr/bin/env bash
# Запускает расчёт на кластере.
# Использование: scripts/cluster_run.sh [NP] [THREADS] [аргументы решателя...]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

master_ssh sudo -iu mpi /opt/slae/bin/run_solver.sh "$@"
