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

## Repository settings and rulesets

GitHub Free does not support user-level rulesets, so apply everything per repository:

```sh
scripts/apply-repo-settings.sh REPO
```

That script sets squash-only merges with branch deletion, secret scanning with push protection, an Actions allowlist (GitHub-owned plus `pnpm/action-setup` and `googleapis/release-please-action`), a read-only default workflow token that cannot approve pull requests, CodeQL default setup, and three rulesets:

- `conventional-commits.json` rejects non-conforming commit subjects on push.
- `app-main.json` protects the default branch: pull requests required, squash merges only, linear history, resolved review threads, and the shared CI checks passing with the strict up-to-date policy.
- `protect-release-tags.json` blocks deleting or moving `v*` tags, which Release Please and the self-hosting checksum instructions rely on.

Repositories that still carry classic branch protection on `main` should drop it after the `App main` ruleset is in place, since the shared CI check contexts (`check / Conventional commits`, `check / App checks`) replace the old per-repo contexts.

Dependabot in this repository keeps the SHA-pinned third-party actions inside the reusable workflows current; consuming repositories reference only `@v1` and never see the pins.

## Not covered

`git-chunks` keeps its own multi-channel release pipeline (GoReleaser, npm trusted publishing, Homebrew, Scoop, Winget, AUR, Chocolatey); it is genuinely repository-specific and documented in its own `PUBLISHING-SETUP.md`.
