#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "relay image publish check failed: $*" >&2
  exit 1
}

WORKFLOW=.github/workflows/relay-image.yml
DOCKERFILE=Dockerfile.relay
DEPLOY_DOC=deploy/zeabur/README.md

[[ -f "$WORKFLOW" ]] || fail "$WORKFLOW is missing"
grep -Fq "relay-v*" "$WORKFLOW" || fail "workflow must trigger only from relay-v* tags"
grep -Fq "bash scripts/check-relay-image-publish.sh" "$WORKFLOW" || fail "workflow must validate its image publication contract"
grep -Fq "./gradlew :protocol:jvmTest :relay:test" "$WORKFLOW" || fail "workflow must run relay compatibility tests"
grep -Fq "file: Dockerfile.relay" "$WORKFLOW" || fail "workflow must build Dockerfile.relay"
grep -Fq "platforms: linux/amd64" "$WORKFLOW" || fail "workflow must publish linux/amd64"
grep -Fq '4fterlook/cc-pocket-relay' "$WORKFLOW" || fail "workflow must publish the private relay repository"
grep -Fq 'secrets.DOCKERHUB_USERNAME' "$WORKFLOW" || fail "workflow must read the Docker Hub username from GitHub secrets"
grep -Fq 'secrets.DOCKERHUB_TOKEN' "$WORKFLOW" || fail "workflow must read the Docker Hub token from GitHub secrets"
if grep -Fq 'cc-pocket-relay:latest' "$WORKFLOW"; then
  fail "workflow must not publish a mutable latest tag"
fi

grep -Fq 'COPY LICENSE /licenses/cc-pocket/LICENSE' "$DOCKERFILE" || fail "runtime image must contain the MIT license"
grep -Fq 'org.opencontainers.image.source' "$DOCKERFILE" || fail "runtime image must declare its source repository"

grep -Fq '4fterlook/cc-pocket-relay:<version>' "$DEPLOY_DOC" || fail "Zeabur guide must document the version-pinned private image"
grep -Fq 'DOCKERHUB_TOKEN' "$DEPLOY_DOC" || fail "Zeabur guide must document private registry credentials"
grep -Fq '/data' "$DEPLOY_DOC" || fail "Zeabur guide must retain the persistent relay volume"

echo "relay image publish configuration OK"
