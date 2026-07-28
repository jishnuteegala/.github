#!/usr/bin/env bash
# One-time npm trusted publishing bootstrap for one or more package names.
#
# npm requires one direct publish of a package name before a trusted
# publisher can be configured for it. This script publishes throwaway
# 0.0.0 stubs under the "bootstrap" dist-tag with provenance disabled,
# configures trusted publishing for a GitHub Actions workflow, and locks
# each package to 2FA-only (tokens disallowed; OIDC unaffected).
#
# Phases are separate and resumable: re-running a phase skips work that
# is already done (publish checks for an existing 0.0.0) or simply
# reapplies idempotent settings (trust, lock).
#
# Prerequisites:
#   - a logged-in npm session (`npm whoami` works); no token needed
#   - npm 11.5.1+ for trusted publishing, and a version that has
#     `npm trust` (11.18+) for the trust phase
#
# Usage:
#   ./npm-oidc-bootstrap.sh publish|trust|lock|verify|all \
#     --repo OWNER/REPO \
#     --workflow release-please.yml \
#     PACKAGE [PACKAGE...]
#
# Or list packages one per line in a file:
#   ./npm-oidc-bootstrap.sh all --repo OWNER/REPO --packages-file names.txt
#
# Example:
#   ./npm-oidc-bootstrap.sh all --repo jishnuteegala/my-tool \
#     my-tool my-tool-linux-x64 my-tool-darwin-arm64
set -euo pipefail

phase="${1:?usage: npm-oidc-bootstrap.sh publish|trust|lock|verify|all --repo OWNER/REPO [--workflow FILE] [--packages-file FILE] [PACKAGE...]}"
shift

repo=""
workflow="release-please.yml"
packages=()

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:?--repo needs OWNER/REPO}"; shift 2 ;;
    --workflow) workflow="${2:?--workflow needs a filename}"; shift 2 ;;
    --packages-file)
      file="${2:?--packages-file needs a path}"
      while IFS= read -r line; do
        line="${line%%#*}"
        line="$(echo "$line" | tr -d '[:space:]')"
        [ -n "$line" ] && packages+=("$line")
      done < "$file"
      shift 2 ;;
    *) packages+=("$1"); shift ;;
  esac
done

[ -n "$repo" ] || { echo "error: --repo OWNER/REPO is required" >&2; exit 1; }
[ "${#packages[@]}" -gt 0 ] || { echo "error: no packages given" >&2; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

publish() {
  npm whoami >/dev/null
  for name in "${packages[@]}"; do
    if npm view "$name@0.0.0" version >/dev/null 2>&1; then
      echo "skip: $name@0.0.0 already exists"
      continue
    fi
    dir="$stage/$name"
    mkdir -p "$dir"
    cat > "$dir/package.json" <<JSON
{
  "name": "$name",
  "version": "0.0.0",
  "description": "Bootstrap placeholder. Do not install; use the latest release.",
  "repository": "github:$repo",
  "license": "MIT"
}
JSON
    printf '# %s\n\nBootstrap placeholder. Do not install; use the latest release.\n' "$name" > "$dir/README.md"
    ok=0
    for attempt in 1 2 3 4 5 6; do
      if npm publish "$dir" --access public --tag bootstrap --provenance=false; then
        ok=1
        break
      fi
      echo "retrying $name in 30s (attempt $attempt failed, likely 409 while the registry settles)"
      sleep 30
    done
    if [ "$ok" -ne 1 ]; then
      echo "giving up on $name after 6 attempts" >&2
      exit 1
    fi
    echo "published: $name@0.0.0 (tag: bootstrap)"
    sleep 2
  done
}

trust() {
  for name in "${packages[@]}"; do
    npm trust github "$name" \
      --file "$workflow" \
      --repo "$repo" \
      --allow-publish \
      --yes
    echo "trusted publisher configured: $name -> $repo / $workflow"
    sleep 2
  done
}

lock() {
  for name in "${packages[@]}"; do
    npm access set mfa=publish "$name"
    echo "locked (2FA required, tokens disallowed): $name"
    sleep 2
  done
}

verify() {
  for name in "${packages[@]}"; do
    echo "== $name"
    npm view "$name" dist-tags --json
    npm trust list "$name" || true
  done
}

all() {
  publish
  trust
  lock
  verify
}

case "$phase" in
  publish|trust|lock|verify|all) "$phase" ;;
  *) echo "error: unknown phase '$phase' (use publish|trust|lock|verify|all)" >&2; exit 1 ;;
esac
