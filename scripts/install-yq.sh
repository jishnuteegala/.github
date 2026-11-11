#!/usr/bin/env bash
# Installs the pinned yq into $RUNNER_TEMP/bin, ahead of the runner's own yq on the job's PATH.
set -euo pipefail

version=4.54.3
sha256=129534601871538efe0ba4c5e62a34fb1d5f469bcb975c4fddeb467d82974973
bin="$RUNNER_TEMP/bin"

mkdir -p "$bin"
curl -fsSLo "$bin/yq" "https://github.com/mikefarah/yq/releases/download/v${version}/yq_linux_amd64"
echo "${sha256}  $bin/yq" | sha256sum --check
chmod +x "$bin/yq"
echo "$bin" >> "$GITHUB_PATH"
