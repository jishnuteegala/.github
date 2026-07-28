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
- `GITHUB_TOKEN` by default; an optional `RELEASE_PLEASE_TOKEN` secret is used when configured (callers pass `secrets: inherit`), which makes required CI run automatically on release pull requests. Leaving it unset is safe and matches git-chunks; the fallback expression resolves to the repository token. Draft-first releases published only after the checksummed archive uploads.
- Node 24 and pnpm via each repository's `packageManager` field; actions pinned to full commit SHAs.

## Repository settings and rulesets

GitHub Free does not support user-level rulesets, so apply everything per repository:

```sh
scripts/apply-repo-settings.sh REPO "check / Conventional commits" "check / App checks (ubuntu-latest)"
```

The check contexts are positional arguments because they differ per repository (glasspick runs a Windows matrix leg, jq-pointer does not). Read the exact names from a CI run of the migrated workflow with `gh pr checks PR -R jishnuteegala/REPO --json name`; the contexts in `rulesets/app-main.json` are placeholders that the script replaces.

That script sets squash-only merges with branch deletion, secret scanning with push protection, an Actions allowlist (GitHub-owned plus `pnpm/action-setup` and `googleapis/release-please-action`), a read-only default workflow token that cannot approve pull requests, CodeQL default setup, and three rulesets:

- `conventional-commits.json` rejects non-conforming commit subjects on push.
- `app-main.json` protects the default branch: pull requests required, squash merges only, linear history, resolved review threads, and the shared CI checks passing with the strict up-to-date policy.
- `protect-release-tags.json` blocks deleting or moving `v*` tags, which Release Please and the self-hosting checksum instructions rely on.

Repositories that still carry classic branch protection on `main` should drop it after the `App main` ruleset is in place, since the shared CI check contexts (`check / Conventional commits`, `check / App checks`) replace the old per-repo contexts.

Dependabot in this repository keeps the SHA-pinned third-party actions inside the reusable workflows current; consuming repositories reference only `@v1` and never see the pins.

## npm trusted publishing

Repositories that publish to npm do so through trusted publishing (OIDC): the publish job exchanges the workflow's OIDC identity for a single-use credential, so no npm token is stored anywhere. Publishing requires a GitHub-hosted runner, Node 22.14 or newer, npm 11.5.1 or newer, and `id-token: write` on the publish job. Provenance is generated automatically for public packages published from public repositories.

Each package trusts its own repository and the **calling** workflow filename (`release-please.yml`, not any reusable workflow it calls), with `npm publish` as the allowed action and the environment left empty. npm does not validate the configuration when it is saved; a mistake surfaces as a loud failure on the next publish, which is the intended behaviour since there is no token fallback.

### Bootstrap for new packages

npm refuses to configure a trusted publisher for a package name that has never been published, so every new package needs one direct publish first. The sequence, from an interactive logged-in npm session (browser 2FA, no token):

1. Publish a throwaway `0.0.0` stub with a minimal `package.json` and README:

   ```sh
   npm publish --access public --tag bootstrap --provenance=false
   ```

   The `bootstrap` dist-tag keeps the stub out of the way, though npm assigns `latest` to a package's first publish regardless; the first real release replaces it. Provenance is disabled because a local publish has no CI identity to attest. Recently recycled names can return `409 Conflict` while the registry settles; retry after a delay.

2. Configure the trusted publisher (this phase needs the interactive session; npm does not accept granular tokens for trust changes):

   ```sh
   npm trust github PACKAGE \
     --file release-please.yml \
     --repo jishnuteegala/REPO \
     --allow-publish
   ```

   On the first browser challenge, select npm's option to skip 2FA for the next five minutes so a batch of packages goes through without a prompt per package. Keep batches under about 80 packages and pause a couple of seconds between calls, as npm recommends.

3. Lock the package to 2FA and disallow tokens (OIDC is unaffected):

   ```sh
   npm access set mfa=publish PACKAGE
   ```

4. If a token was used anywhere in the process, revoke it immediately.

`scripts/npm-oidc-bootstrap.sh` runs the whole sequence for any set of package names, as separate resumable phases with a 409 retry loop on the stub publish:

```sh
scripts/npm-oidc-bootstrap.sh all --repo jishnuteegala/REPO PACKAGE [PACKAGE...]
```

Run `publish`, `trust`, `lock`, or `verify` instead of `all` to execute one phase; re-running skips stubs that already exist and reapplies the idempotent settings.

The bootstrap is once per package name. Real releases then flow entirely through Release Please and OIDC. npm has announced that bypass-2FA tokens stop working for package-management changes in early August 2026 and for direct publishing around January 2027, so the token-free path is also the durable one. When npm ships namespace-wide trusted publishing for new packages, the stub-publish phase can be replaced with that mechanism.

Keep the npm account email set to a publishing alias rather than a personal address: the registry exposes the account email in `maintainers` and freezes it into each directly-published version's `_npmUser`, and version metadata is immutable once published. OIDC-published versions are attributed to `npm-oidc-no-reply@github.com` instead.

## Not covered

`git-chunks` keeps its own multi-channel release pipeline (GoReleaser, npm trusted publishing, Homebrew, Scoop, Winget, AUR, Chocolatey); it is genuinely repository-specific and documented in its own `PUBLISHING-SETUP.md`. The npm trusted publishing and bootstrap steps above apply to it all the same.
