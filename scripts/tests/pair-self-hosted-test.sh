#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${PAIR_FIXTURE:?}"
EOF
chmod +x "$TMP/curl"

run_script() {
  PATH="$TMP:$PATH" PAIR_FIXTURE="$1" bash "$ROOT/scripts/pair-self-hosted.sh" "${2:-wss://relay.planet-corp.cn}"
}

fixture='{"accountId":"acct-123","daemonPub":"daemon_pub-456","ticket":"ticket_secret-789","code":"123456","ttlSec":120,"relay":"wss://relay.planet-corp.cn"}'
output="$(run_script "$fixture")"
expected='ccpocket://pair?relay=wss://relay.planet-corp.cn&acct=acct-123&dpk=daemon_pub-456&ticket=ticket_secret-789'
grep -Fxq "$expected" <<<"$output" || {
  echo "FAIL: full custom-relay pairing link missing" >&2
  printf '%s\n' "$output" >&2
  exit 1
}
grep -Fq 'expires in 120s' <<<"$output" || {
  echo "FAIL: ticket expiry missing" >&2
  exit 1
}

set +e
mismatch="$(run_script "$fixture" 'wss://other.example.com' 2>&1)"
code=$?
set -e
[[ $code -ne 0 ]] || {
  echo "FAIL: relay mismatch was accepted" >&2
  exit 1
}
grep -Fq 'daemon is connected to wss://relay.planet-corp.cn' <<<"$mismatch" || {
  echo "FAIL: relay mismatch diagnostic missing" >&2
  exit 1
}
if grep -Fq 'ticket_secret-789' <<<"$mismatch"; then
  echo "FAIL: mismatch leaked the one-time ticket" >&2
  exit 1
fi

set +e
malformed="$(run_script '{"error":"relay_offline"}' 2>&1)"
code=$?
set -e
[[ $code -ne 0 ]] || {
  echo "FAIL: malformed loopback response was accepted" >&2
  exit 1
}
grep -Fq 'could not read pairing fields' <<<"$malformed" || {
  echo "FAIL: malformed-response diagnostic missing" >&2
  exit 1
}

echo "PASS: self-hosted pairing helper"
