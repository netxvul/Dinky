#!/usr/bin/env bash
# Copies the debug binary and fuzz.py into the Tart VM `kex`, restarts the app there from that binary,
# runs the fuzzer over ssh and prints its output. Usage: scripts/vm-fuzz.sh <seed> <steps> [--switching]
set -uo pipefail
cd "$(dirname "$0")/.."

IP="${KEX_VM_IP:-$(tart ip kex)}"
SSH_OPTS=(-i ~/.ssh/id_rsa -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/kex-known-hosts)

ssh "${SSH_OPTS[@]}" "admin@$IP" 'pkill -f "[d]inky.app"; pkill -f "[d]inky[-a-z0-9]* app"; pkill -x TextEdit; pkill -x Safari; sleep 1'
scp -q "${SSH_OPTS[@]}" .build/debug/kex "admin@$IP:kex-fuzz"
scp -q "${SSH_OPTS[@]}" scripts/fuzz.py "admin@$IP:fuzz.py"
ssh "${SSH_OPTS[@]}" "admin@$IP" 'nohup ~/kex-fuzz app > /tmp/kex-fuzz.log 2>&1 < /dev/null & sleep 3'
ssh "${SSH_OPTS[@]}" "admin@$IP" "python3 -u ~/fuzz.py --seed $1 --steps $2 --kex ~/kex-fuzz ${3:-}"
status=$?
ssh "${SSH_OPTS[@]}" "admin@$IP" 'pkill -f "[d]inky-fuzz app"; echo "app log: /tmp/kex-fuzz.log in the guest"'
exit $status
