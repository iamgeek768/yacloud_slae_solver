#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_state

ip=$(curl -s -m 15 -A 'Mozilla/5.0' https://ip.mail.ru | grep -oE 'IP: [0-9.]+' | head -1 | cut -d' ' -f2 || true)
if [ -z "$ip" ]; then
  echo "не удалось узнать внешний адрес; впишите его в admin_cidrs в terraform/terraform.tfvars вручную" >&2
  exit 1
fi

tfvars=$ROOT/terraform/terraform.tfvars
echo "Разрешаю SSH с адреса $ip..."
sed -i "s|^admin_cidrs = .*|admin_cidrs = [\"$ip/32\"]|" "$tfvars"
"$ROOT/scripts/tf.sh" apply -auto-approve -input=false -target=yandex_vpc_security_group.ssh > /dev/null
echo "Готово: SSH на главную ВМ разрешён с $ip"
