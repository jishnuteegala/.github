# Shared repository automation

Reusable GitHub Actions workflows, repository rulesets, and release configuration for my app repositories (jq-pointer, glasspick, cronsense, and future ones).

App repositories keep small caller workflows that reference the reusable implementations here through the moving `v1` tag. Fixes land once in this repository and propagate everywhere; move the `v1` tag only after validating a change against one pilot repository.

## Workflows

| Reusable workflow | What it does |
|---|---|
| `.github/workflows/app-ci.yml` | Validates commit subjects against Conventional Commits, then runs the `check-command` input (default `pnpm check`; each repo defines its own `check` script) on the `os` matrix. On every Linux leg it runs `pnpm build` right after the install, the same sequence as the release build, so the optional `post-check` (Linux only) can read `dist/`; the `ubuntu-latest` leg also uploads the dist manifest (`actions/dist-manifest`). An optional `parallel-command` runs in its own Linux job alongside the check. A final `ci-ok` job needs every other job and fails when any of them failed or was cancelled, so `<caller job> / ci-ok` (for example `check / ci-ok`) is the only check context a ruleset needs. |
| `.github/workflows/release-please.yml` | Runs Release Please with the default changelog renderer, then builds the tagged source, compares its `dist/` with the CI dist manifest of the same source tree, packages a checksummed reproducible dist archive with the tag's own `scripts/package_release.py`, attaches it, and publishes the draft release. A tag containing `-` is published as a prerelease that is not marked latest. Supports draft recovery through the `recover-tag` input. The caller grants `actions: read` so the job can download the CI manifest. |

| Composite action | What it does |
|---|---|
| `actions/conventional-commits` | Validates every commit subject in the push or pull request range against Conventional Commits. Used by `app-ci.yml` and callable directly from bespoke CI (git-chunks): check out with `fetch-depth: 0`, then `uses: jishnuteegala/.github/actions/conventional-commits@<sha> # v1`, where `<sha>` is the full commit SHA that `v1` points to (`git ls-remote https://github.com/jishnuteegala/.github 'refs/tags/v1^{}'`). Pin the SHA rather than `@v1`, and update it when `v1` moves: repositories that require SHA-pinned actions fail every run that references an action by tag. A composite action rather than a reusable workflow so consuming jobs keep their own check-context names. |
| `actions/dist-manifest` | With `mode: write`, writes a sorted SHA-256 manifest of every file under `dist/` and uploads it as the artifact `dist-manifest-<tree>`, named after `git rev-parse HEAD^{tree}`. With `mode: compare` (needs `actions: read`), compares a fresh build with the newest unexpired artifact for the same tree uploaded by a run of the same repository (fork pull request runs are ignored): a mismatch fails, and a missing artifact (expired, or a release pull request merged without CI) is a warning in the job summary. `path` names the checkout that holds `dist/` (default `.`). The manifest is written on `ubuntu-latest` only, the runner of the release build, because a CRLF checkout can change built files and another Linux leg would overwrite the per-tree artifact. |

`.github/workflows/lint.yml` checks this repository on pull requests and pushes to `main`: actionlint over the workflows and caller templates, and `scripts/check-action-pins.sh`, which parses the YAML in `.github/workflows/`, `actions/`, and `callers/` and requires every action `uses:` to be a full commit SHA, whatever the YAML style.
Local `./` actions, `docker://` images, and references to this repository's own reusable workflows (the callers' `@v1`) are exempt; GitHub's SHA-pinning policy does not cover reusable workflows.
The fixtures in `tests/action-pins/` run first: pinned ones must pass and each unpinned one must be rejected.
The `Script tests` job runs the dist manifest fixture tests in `tests/dist-manifest/`, runs the release workflow's `Publish complete release` step against a `gh` shim for stable and prerelease tags, requires `ci-ok` to need every `app-ci.yml` job, and requires every pinned action of this repository (`jishnuteegala/.github/actions/<name>@<sha>`) to match `actions/<name>` in the checked-out tree.
The reusable workflows cannot use `./` for these actions, because `./` resolves in the caller's repository, so a pull request that changes an action adds a second commit that pins the first.
After the squash merge the pinned commit stays reachable through the pull request's ref, and this check keeps its action identical to the one on `main`.
The `Dist manifest action` job runs the action end to end on pushes and same-repository pull requests: an identical build passes, a changed file fails, and a tree without a CI manifest warns.

Copy the callers from `callers/` into an app repository's `.github/workflows/`. The release caller expects the repository to own `release-please-config.json` (start from `templates/release-please-config.json`), `.release-please-manifest.json`, and `scripts/package_release.py`.
Start `.github/dependabot.yml` from `templates/dependabot.yml`.

## Moving `v1`

1. Merge the change to `main` in this repository.
2. In one consumer per affected caller shape, open a draft pull request that points the caller at `app-ci.yml@<new main SHA>`, confirm its CI is green, and close it unmerged.
3. Move the tag as a signed annotated tag and verify the signature: `git tag -fa v1 -m v1 <SHA>`, then `git tag -v v1`.
4. Push it with `git push origin refs/tags/v1 --force`, and confirm `git ls-remote origin refs/tags/v1 'refs/tags/v1^{}'` shows the new commit.
5. Confirm the next CI run in each consumer lists `referenced_workflows` with ref `refs/tags/v1` and the new tag object.
6. If an own-action pin changed, update the callers that pin actions by SHA (see `actions/conventional-commits`).

## Conventions baked in

- Conventional Commit subjects with types `build chore ci docs feat fix perf refactor revert style test`; scopes and `!` markers supported.
- The default Release Please changelog renderer, because squash-merged PRs carry extra Conventional Commit messages in the body and the default renderer expands them into separate changelog entries. `changelog-type: "github"` discards that expansion (see googleapis/release-please#2758), and on a solo repository its PR attribution adds nothing.
- Explicit `changelog-sections` making `docs`, `build`, and `ci` visible alongside the defaults, so those commits are recorded in the changelog. Consequence of Release Please's coupling: any visible-section commit also triggers a release pull request, so docs/build/ci commits produce patch releases. `chore`, `style`, `refactor`, and `test` stay hidden (no changelog entry, no release).
- `GITHUB_TOKEN` by default; an optional `RELEASE_PLEASE_TOKEN` secret is used when configured (the caller template passes no secrets, so a repository that adds the token maps it explicitly under `secrets:`), which makes required CI run automatically on release pull requests. Leaving it unset is safe and matches git-chunks; the fallback expression resolves to the repository token. Draft-first releases published only after the checksummed archive uploads.
- Node from the repository's `.node-version` file when it exists (an exact version, so CI and release builds match), otherwise the `node-version` input (default `24`); pnpm via each repository's `packageManager` field (through Corepack on Windows, where `pnpm/action-setup` is slow, so Windows legs need Node 24 or earlier, the last line that ships Corepack); actions pinned to full commit SHAs.

## Repository settings and rulesets

GitHub Free does not support user-level rulesets, so apply everything per repository:

```sh
scripts/apply-repo-settings.sh REPO "check / ci-ok"
```

The check contexts are positional arguments because they can differ per repository; with `app-ci.yml`, `check / ci-ok` covers every job and matrix leg.
Read the exact names from a CI run of the migrated workflow with `gh pr checks PR -R jishnuteegala/REPO --json name`; the contexts in `rulesets/app-main.json` are placeholders that the script replaces.

That script sets squash-only merges with branch deletion, secret scanning with push protection, an Actions allowlist (GitHub-owned plus `pnpm/action-setup` and `googleapis/release-please-action`), a read-only default workflow token that may create release pull requests, immutable releases (published release assets cannot be edited or deleted), CodeQL default setup, and three rulesets:

- `conventional-commits.json` rejects non-conforming commit subjects on push.
- `app-main.json` protects the default branch: pull requests required, squash merges only, linear history, resolved review threads, and the shared CI checks passing with the strict up-to-date policy.
- `protect-release-tags.json` blocks deleting or moving `v*` tags, which Release Please and the self-hosting checksum instructions rely on.

Repositories that still carry classic branch protection on `main` should drop it after the `App main` ruleset is in place, since the shared CI check context (`check / ci-ok`) replaces the old per-repo contexts.

Dependabot in this repository keeps the SHA-pinned third-party actions inside the reusable workflows and the composite actions current; the app repositories' caller workflows reference only `@v1` and never see the pins.
Dependabot ignores this repository's own actions (`jishnuteegala/.github/actions/*`), because each weekly run would propose the latest `main` commit even when the action did not change.
Update those self-pins by hand when an action's content changes, including a Dependabot bump inside `actions/`; the pin-match check fails until the pinned commit has the current action.

## npm trusted publishing

Repositories that publish to npm do so through trusted publishing (OIDC): the publish job exchanges the workflow's OIDC identity for a single-use credential, so no npm token is stored anywhere. Publishing requires a GitHub-hosted runner, Node 22.14 or newer, npm 11.5.1 or newer, and `id-token: write` on the publish job. Provenance is generated automatically for public packages published from public repositories.

Each package trusts its own repository and the **calling** workflow filename (`release-please.yml`, not any reusable workflow it calls), with `npm publish` as the allowed action and the environment left empty. npm does not validate the configuration when it is saved; a mistake surfaces as a loud failure on the next publish, which is the intended behaviour since there is no token fallback.

### Publish job requirements (learned from redirect-trace 0.1.0)

Repositories with bespoke release workflows (CLIs publishing to npm rather than apps shipping static archives) must follow these rules, none of which PR CI can catch because the release path only executes on pushes to the default branch:

- Start the release-please config from `templates/release-please-config.json`, or at minimum keep `"include-component-in-tag": false`. The `node` release-type otherwise prefixes tags with the package name (`redirect-trace-v0.1.0`), which fails any `v*` tag validation and falls outside the `protect-release-tags.json` ruleset.
- Run the publish job on **Node 24** and pin npm: `npm install --global npm@12.0.1`. Never `npm@latest` - it can outpace the workflow's pinned Node (npm 12 refused Node 22.15.0 with EBADENGINE), and an in-place global upgrade of the running npm can corrupt its own module tree (`MODULE_NOT_FOUND: promise-retry` on Node 22.22.2). Node 24 + pinned npm 12.0.1 is the combination proven by git-chunks.
- Rehearse the failure path before the first release merges: the tag format, action SHA pins, and npm version constraints in a release workflow are all invisible to PR checks. Dry-run what you can (`workflow_dispatch` with a recovery input makes retries cheap) and verify every value that only a main-branch run will exercise.

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
