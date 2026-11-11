#!/usr/bin/env bash
# Обёртка над terraform: подставляет свежий IAM-токен в YC_TOKEN.
# Использование: scripts/tf.sh plan | apply | destroy | ...
set -euo pipefail
source "$(dirname "$0")/lib.sh"

YC_TOKEN=$(yc_token)
export YC_TOKEN

PARALLELISM=${TF_PARALLELISM:-4}
export TF_CLI_ARGS_plan="-parallelism=$PARALLELISM"
export TF_CLI_ARGS_apply="-parallelism=$PARALLELISM"
export TF_CLI_ARGS_destroy="-parallelism=$PARALLELISM"
exec terraform -chdir="$ROOT/terraform" "$@"
