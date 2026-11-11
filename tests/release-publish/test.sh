#!/usr/bin/env bash
# Runs the "Publish complete release" step of release-please.yml against a gh
# shim and checks the arguments it records for a stable and a prerelease tag.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

yq -e '.jobs.release.steps[] | select(.name == "Publish complete release") | .run' \
  "$root/.github/workflows/release-please.yml" > "$work/step.sh"

mkdir "$work/bin"
cat > "$work/bin/gh" <<'SHIM'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_LOG"
SHIM
chmod +x "$work/bin/gh"
[[ "$(PATH="$work/bin:$PATH" command -v gh)" == "$work/bin/gh" ]] || exit 99

status=0
expect() {
  : > "$work/gh.log"
  PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" TAG_NAME="$1" bash -e "$work/step.sh"
  actual=$(cat "$work/gh.log")
  if [[ "$actual" == "$2" ]]; then
    echo "$1: $actual"
  else
    echo "::error::$1: expected '$2', got '$actual'"
    status=1
  fi
}

expect v1.2.3 "gh release edit v1.2.3 --draft=false"
expect v0.4.0 "gh release edit v0.4.0 --draft=false"
expect v1.2.3-rc.1 "gh release edit v1.2.3-rc.1 --draft=false --prerelease --latest=false"
expect v0.4.0-beta "gh release edit v0.4.0-beta --draft=false --prerelease --latest=false"
exit "$status"
