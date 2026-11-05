#!/usr/bin/env bash
# Copies build/Kex.app into the Tart VM `kex` and launches it there.
set -euo pipefail
cd "$(dirname "$0")/.."

IP="$(tart ip kex)"
SSH_OPTS=(-i ~/.ssh/id_rsa -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/kex-known-hosts)

ssh "${SSH_OPTS[@]}" "admin@$IP" 'pkill -f Kex.app; mkdir -p ~/Applications && rm -rf ~/Applications/Kex.app'
scp -rq "${SSH_OPTS[@]}" build/Kex.app "admin@$IP:Applications/"
ssh "${SSH_OPTS[@]}" "admin@$IP" 'open ~/Applications/Kex.app'
echo "launched Kex.app in the VM at $IP"
