#!/usr/bin/env bash
# Usage: check-action-pins.sh <file or directory>...
# Fails unless every action `uses:` in the YAML files ends in @<40 lowercase hex commit SHA>.
set -euo pipefail

uses=$(grep -rnHE --include='*.yml' --include='*.yaml' '^[[:space:]]*(-[[:space:]]+)?uses:' "$@")
status=0
count=0
while IFS=: read -r file line text; do
  ref=$(sed -E 's/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*//; s/[[:space:]].*//' <<< "$text" | tr -d "\"'")
  case "$ref" in
    # The callers reference this repository's reusable workflows at @v1 by
    # design; GitHub's SHA-pinning policy does not cover reusable workflows.
    ./* | docker://* | jishnuteegala/.github/.github/workflows/*) continue ;;
  esac
  count=$((count + 1))
  if [[ ! "$ref" =~ @[0-9a-f]{40}$ ]]; then
    echo "::error file=$file,line=$line::$ref is not pinned to a full commit SHA"
    status=1
  fi
done <<< "$uses"
echo "Checked $count action references."
exit "$status"
