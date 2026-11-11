# Общие функции локальных скриптов; подключается через source.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SSH_KEY=${SSH_KEY:-$HOME/.ssh/yalab_ed25519}
KNOWN_HOSTS=$ROOT/.known_hosts
S3_ENDPOINT=https://storage.yandexcloud.net

# IAM-токен пользователя; yc иногда отвечает с задержкой, поэтому с повторами.
yc_token() {
  local token
  for _ in 1 2 3 4 5; do
    token=$(yc iam create-token 2>/dev/null | grep -E '^t1\.' | head -1) || true
    if [ -n "$token" ]; then
      echo "$token"
      return 0
    fi
    sleep 3
  done
  echo "не удалось получить IAM-токен: проверьте yc config list" >&2
  return 1
}

# Без файла состояния Terraform не знает о созданном кластере и стал бы создавать его заново.
require_state() {
  if ! terraform -chdir="$ROOT/terraform" state list 2> /dev/null | grep -q '^yandex_compute_instance.node'; then
    echo "нет состояния Terraform (terraform/terraform.tfstate) с кластером: перенесите папку проекта целиком" >&2
    exit 1
  fi
}

tf_output() {
  terraform -chdir="$ROOT/terraform" output -raw "$1"
}

# Команда на главной ВМ от имени yc-user (имя admin в образе Ubuntu занято одноимённой группой).
master_ssh() {
  ssh -i "$SSH_KEY" -p "$(tf_output ssh_port)" -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$KNOWN_HOSTS" -o LogLevel=ERROR -o ConnectTimeout=10 \
    "yc-user@$(tf_output master_public_ip)" "$@"
}
