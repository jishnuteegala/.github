#!/usr/bin/env bash
# Applies the standard repository settings and rulesets to one app repository.
# Usage: scripts/apply-repo-settings.sh REPO CHECK_CONTEXT...
# Example:
#   scripts/apply-repo-settings.sh jq-pointer \
#     "check / Conventional commits" "check / App checks (ubuntu-latest)"
# Read the exact context names from a run of the migrated CI workflow:
#   gh pr checks PR -R jishnuteegala/REPO --json name
set -euo pipefail

REPO="jishnuteegala/${1:?usage: apply-repo-settings.sh REPO CHECK_CONTEXT...}"
shift
if [ "$#" -eq 0 ]; then
  echo "At least one required check context is needed." >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if command -v cygpath > /dev/null 2>&1; then
  ROOT="$(cygpath -m "$ROOT")"
fi

CONTEXTS_JSON=$(printf '%s\n' "$@" | node -e "
const lines = require('fs').readFileSync(0, 'utf8').split('\n').filter(Boolean);
console.log(JSON.stringify(lines.map((context) => ({ context }))));
")

echo "Merge and branch settings"
gh api --method PATCH "repos/$REPO" \
  --field allow_squash_merge=true \
  --field allow_merge_commit=false \
  --field allow_rebase_merge=false \
  --field delete_branch_on_merge=true \
  --field security_and_analysis[secret_scanning][status]=enabled \
  --field security_and_analysis[secret_scanning_push_protection][status]=enabled \
  > /dev/null

echo "Actions: allowlist and read-only workflow token"
gh api --method PUT "repos/$REPO/actions/permissions" \
  --field enabled=true --field allowed_actions=selected > /dev/null
gh api --method PUT "repos/$REPO/actions/permissions/selected-actions" \
  --field github_owned_allowed=true \
  --field verified_allowed=false \
  --field 'patterns_allowed[]=pnpm/action-setup@*' \
  --field 'patterns_allowed[]=googleapis/release-please-action@*' \
  > /dev/null
gh api --method PUT "repos/$REPO/actions/permissions/workflow" \
  --field default_workflow_permissions=read \
  --field can_approve_pull_request_reviews=false > /dev/null

echo "CodeQL default setup"
gh api --method PATCH "repos/$REPO/code-scanning/default-setup" \
  --field state=configured > /dev/null || echo "  (already configured or unavailable)"

echo "Rulesets"
for ruleset in conventional-commits app-main protect-release-tags; do
  payload="$ROOT/rulesets/$ruleset.json"
  if [ "$ruleset" = "app-main" ]; then
    payload=$(mktemp)
    CONTEXTS_JSON="$CONTEXTS_JSON" node -e "
const config = require('$ROOT/rulesets/app-main.json');
const rule = config.rules.find((entry) => entry.type === 'required_status_checks');
rule.parameters.required_status_checks = JSON.parse(process.env.CONTEXTS_JSON);
console.log(JSON.stringify(config, null, 2));
" > "$payload"
  fi
  name=$(node -e "console.log(require('$ROOT/rulesets/$ruleset.json').name)")
  existing=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$name\") | .id")
  if [ -n "$existing" ]; then
    gh api --method PUT "repos/$REPO/rulesets/$existing" --input "$payload" > /dev/null
    echo "  updated $name ($existing)"
  elif gh api --method POST "repos/$REPO/rulesets" --input "$payload" > /dev/null 2>&1; then
    echo "  created $name"
  elif [ "$ruleset" = "conventional-commits" ]; then
    echo "  skipped $name (commit_message_pattern rules need an organization; the CI job enforces this instead)"
  else
    echo "  FAILED to create $name" >&2
    exit 1
  fi
done

echo "Done. Classic branch protection (if any) is left untouched; remove it once the"
echo "App main ruleset is verified, so required checks are not enforced twice:"
echo "  gh api --method DELETE repos/$REPO/branches/main/protection"
