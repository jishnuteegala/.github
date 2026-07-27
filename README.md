# Shared repository automation

Reusable GitHub Actions workflows, repository rulesets, and release configuration for my app repositories (jq-pointer, glasspick, cronsense, and future ones).

App repositories keep small caller workflows that reference the reusable implementations here through the moving `v1` tag. Fixes land once in this repository and propagate everywhere; move the `v1` tag only after validating a change against one pilot repository.

## Workflows

| Reusable workflow | What it does |
|---|---|
| `.github/workflows/app-ci.yml` | Validates commit subjects against Conventional Commits, then runs `pnpm check` (each repo defines its own `check` script). Accepts an `os` matrix and `node-version` input. |
| `.github/workflows/release-please.yml` | Runs Release Please with the default changelog renderer, then builds the tagged source, packages a checksummed reproducible dist archive via the repo's `scripts/package_release.py`, attaches it, and publishes the draft release. Supports draft recovery through the `recover-tag` input. |

Copy the callers from `callers/` into an app repository's `.github/workflows/`. The release caller expects the repository to own `release-please-config.json` (start from `templates/release-please-config.json`), `.release-please-manifest.json`, and `scripts/package_release.py`.

## Conventions baked in

- Conventional Commit subjects with types `build chore ci docs feat fix perf refactor revert style test`; scopes and `!` markers supported.
- The default Release Please changelog renderer, because squash-merged PRs carry extra Conventional Commit messages in the body and the default renderer expands them into separate changelog entries. `changelog-type: "github"` discards that expansion (see googleapis/release-please#2758), and on a solo repository its PR attribution adds nothing.
- Plain `GITHUB_TOKEN`; no personal access tokens. Draft-first releases published only after the checksummed archive uploads.
- Node 24 and pnpm via each repository's `packageManager` field; actions pinned to full commit SHAs.

## Rulesets

GitHub Free does not support user-level rulesets, so apply these per repository:

```sh
gh api --method POST repos/jishnuteegala/REPO/rulesets --input rulesets/conventional-commits.json
gh api --method POST repos/jishnuteegala/REPO/rulesets --input rulesets/app-main.json
```

`conventional-commits.json` rejects non-conforming commit subjects on push. `app-main.json` protects the default branch: pull requests required, squash merges only, linear history, resolved review threads, and the shared CI checks passing.

## Not covered

`git-chunks` keeps its own multi-channel release pipeline (GoReleaser, npm trusted publishing, Homebrew, Scoop, Winget, AUR, Chocolatey); it is genuinely repository-specific and documented in its own `PUBLISHING-SETUP.md`.
