#!/usr/bin/env bash
# Applies the standard repository settings and rulesets to one app repository.
# Usage: scripts/apply-repo-settings.sh REPO   (e.g. scripts/apply-repo-settings.sh cronsense)
set -euo pipefail

REPO="jishnuteegala/${1:?usage: apply-repo-settings.sh REPO}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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
  name=$(node -e "console.log(require('$ROOT/rulesets/$ruleset.json').name)")
  existing=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$name\") | .id")
  if [ -n "$existing" ]; then
    gh api --method PUT "repos/$REPO/rulesets/$existing" --input "$ROOT/rulesets/$ruleset.json" > /dev/null
    echo "  updated $name ($existing)"
  else
    gh api --method POST "repos/$REPO/rulesets" --input "$ROOT/rulesets/$ruleset.json" > /dev/null
    echo "  created $name"
  fi
done

echo "Done. Classic branch protection (if any) is left untouched; remove it once the"
echo "App main ruleset is verified, so required checks are not enforced twice:"
echo "  gh api --method DELETE repos/$REPO/branches/main/protection"
