#!/usr/bin/env bash
# Mint a full pairing link for a daemon connected to a self-hosted relay.
# A six-digit code is resolved by the official relay, so it is not suitable here.
set -euo pipefail

EXPECTED_RELAY="${1:-wss://relay.planet-corp.cn}"
PAIR_PORT="${PAIR_PORT:-8799}"

case "$EXPECTED_RELAY" in
  wss://*) ;;
  *) echo "ERROR: relay must start with wss://" >&2; exit 2 ;;
esac

if ! pair_json="$(curl -fsS --max-time 15 -X POST "http://127.0.0.1:$PAIR_PORT/pair")"; then
  echo "ERROR: could not reach the cc-pocket daemon on 127.0.0.1:$PAIR_PORT" >&2
  echo "inspect: cc-pocket-daemon status" >&2
  exit 1
fi

json_string() {
  printf '%s' "$pair_json" | sed -nE "s/.*\"$1\":\"([^\"]*)\".*/\1/p"
}

account_id="$(json_string accountId)"
daemon_pub="$(json_string daemonPub)"
ticket="$(json_string ticket)"
relay="$(json_string relay)"
ttl="$(printf '%s' "$pair_json" | sed -nE 's/.*"ttlSec":([0-9]+).*/\1/p')"

if [[ -z "$account_id" || -z "$daemon_pub" || -z "$ticket" || -z "$relay" || -z "$ttl" ]]; then
  echo "ERROR: could not read pairing fields from the daemon response" >&2
  echo "inspect: cc-pocket-daemon status" >&2
  exit 1
fi

if [[ "$relay" != "$EXPECTED_RELAY" ]]; then
  echo "ERROR: daemon is connected to $relay, expected $EXPECTED_RELAY" >&2
  echo "reconfigure: cc-pocket-daemon service-install --apply --relay $EXPECTED_RELAY" >&2
  exit 1
fi

echo "Pairing link (single-use, expires in ${ttl}s):"
echo "ccpocket://pair?relay=$relay&acct=$account_id&dpk=$daemon_pub&ticket=$ticket"
echo "Paste this link into CC Pocket immediately. Do not use the six-digit code for a self-hosted relay."
