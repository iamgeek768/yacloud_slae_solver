#!/usr/bin/env bash
# Отправка логов узла в Monium Logs: ставит OpenTelemetry Collector Contrib
# с конфигурацией из /etc/slae/otelcol.yaml.
set -euo pipefail
source /etc/slae/env

if [ "${ENABLE_LOGGING:-0}" != 1 ]; then
  echo "отправка логов выключена"
  exit 0
fi

VERSION=0.163.2
SHA256=5a175c93c5a560368c1bdbf0ec25fdc06e7b7d852f424bf7dbc36da6fd495db7
deb="otelcol-contrib_${VERSION}_linux_amd64.deb"

curl -sfL --retry 5 -o "/tmp/$deb" \
  "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v$VERSION/$deb"
echo "$SHA256  /tmp/$deb" | sha256sum -c -
dpkg -i "/tmp/$deb"
rm -f "/tmp/$deb"

install -d -o otelcol-contrib -g otelcol-contrib -m 0750 /var/lib/otelcol /var/lib/otelcol/file_storage
install -m 0644 /etc/slae/otelcol.yaml /etc/otelcol-contrib/config.yaml
systemctl enable otelcol-contrib
systemctl restart otelcol-contrib
