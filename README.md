# .github

Organization-wide defaults for `20262c-g14-discordia`. GitHub applies the files here to
every repository in the org that does not carry its own copy.

| File | What it does |
|---|---|
| `PULL_REQUEST_TEMPLATE.md` | The PR body every repo gets. Sections and the definition-of-done checklist mirror `meta/CONTRIBUTING.md`. |
| `.github/workflows/pr-checks.yml` | Reusable workflow that fails a PR whose title is not `type(scope): summary` or whose body has no `Ref DIS-n` / `Closes DIS-n` line. |
| `.github/workflows/release-please.yml` | Reusable release workflow: release-please turns the Conventional Commits on `main` into a release PR, and that PR's merge into a version bump, `CHANGELOG.md`, a `vX.Y.Z` tag and a GitHub release. |

## Opting a repository in

The PR template needs nothing: delete any per-repo `PULL_REQUEST_TEMPLATE.md` so the org
default applies. The check needs one caller workflow, `.github/workflows/pr.yml`:

```yaml
name: PR

on:
  pull_request:
    types: [opened, edited, reopened, synchronize]

permissions:
  contents: read

jobs:
  conventions:
    uses: 20262c-g14-discordia/.github/.github/workflows/pr-checks.yml@main
```

The `edited` trigger re-runs the check when someone fixes the title or body, so a red
check never needs a new commit.

## Releases

Every repository that produces an artifact (clients, services) calls the release workflow
on push to `main`; `meta` does not, there is nothing to version. Two files at the repo root
drive it:

```json
// release-please-config.json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "release-type": "node",
  "bump-minor-pre-major": true,
  "bump-patch-for-minor-pre-major": true,
  "packages": { ".": {} }
}
```

```json
// .release-please-manifest.json
{ ".": "0.0.0" }
```

`release-type` is `node` for the clients, `go` or `python` for the services (it decides
which version file gets bumped). The two `pre-major` flags keep the version below 1.0
until the team decides otherwise: a `feat` bumps the minor, a `fix` the patch, and a
breaking change does not jump to 1.0. The caller workflow is shown at the top of
`release-please.yml`.

A release is one squash-merged PR titled `chore(main): release X.Y.Z`. Merging it is the
release; nothing deploys from it yet. With the default workflow token, GitHub does not run
CI on that PR (it refuses to trigger workflows from events the token creates). If that
matters, add a fine-grained personal access token as the org secret `RELEASE_PLEASE_TOKEN`
and the workflow uses it instead.

## Changing the conventions

The rules themselves live in [`meta/CONTRIBUTING.md`](https://github.com/20262c-g14-discordia/meta/blob/main/CONTRIBUTING.md).
Change the rule there first, then the template or the check here, in one PR each. This
repo takes PRs like any other: squash only, `Ref DIS-n` in the body.
