#!/usr/bin/env bash

set -euo pipefail

token=$(curl -sf --retry 5 -H 'Metadata-Flavor: Google' \
  http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token | jq -er .access_token)
install -d -m 0755 /var/lib/slae
printf '%s' "$token" > /var/lib/slae/iam_token.new
chmod 0644 /var/lib/slae/iam_token.new

mv /var/lib/slae/iam_token.new /var/lib/slae/iam_token
