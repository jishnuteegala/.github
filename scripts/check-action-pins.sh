#!/usr/bin/env bash
# Usage: check-action-pins.sh <file or directory>...
# Fails unless every action `uses:` in the YAML files ends in @<40 lowercase hex commit SHA>.
set -euo pipefail

files=$(find "$@" -type f \( -name '*.yml' -o -name '*.yaml' \))
[[ -n "$files" ]] || { echo "::error::no YAML files in $*"; exit 1; }
# Every mapping with a `uses` key, whatever its YAML style, tag or aliasing.
refs_of='explode(.) | .. | select(kind == "map" and has("uses")) | .uses | [line, (if kind == "scalar" and (tostring | test("^[^\t\n\"]*$")) then . else "<not a plain string>" end)] | @tsv'
status=0
count=0
while IFS= read -r file; do
  refs=$(yq --yaml-fix-merge-anchor-to-spec -N "$refs_of" "$file")
  [[ -n "$refs" ]] || continue
  while IFS=$'\t' read -r line ref; do
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
  done <<< "$refs"
done <<< "$files"
echo "Checked $count action references."
exit "$status"
