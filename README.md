# .github

Organization-wide defaults for `20262c-g14-discordia`. GitHub applies the files here to
every repository in the org that does not carry its own copy.

| File | What it does |
|---|---|
| `PULL_REQUEST_TEMPLATE.md` | The PR body every repo gets. Sections and the definition-of-done checklist mirror `meta/CONTRIBUTING.md`. |
| `.github/workflows/pr-checks.yml` | Reusable workflow that fails a PR whose title is not `type(scope): summary`, and warns when its body has no `Ref DIS-n` / `Closes DIS-n` line. |
| `.github/workflows/release-please.yml` | Reusable release workflow: release-please turns the Conventional Commits on `main` into a release PR, and that PR's merge into a version bump, `CHANGELOG.md`, a `<component>-vX.Y.Z` tag and a GitHub release. |

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

A release is one squash-merged PR titled `chore(main): release <component> X.Y.Z`, where
the component is the package name. Merging it is the release; nothing deploys from it yet.
The tag it produces carries that component, `discordia-web-v0.1.0`, which keeps tags
unambiguous across the org's repositories. Set `"include-component-in-tag": false` in the
config if a repository wants a bare `v0.1.0` instead.

### Monorepo callers

release-please sets `release_created` and `tag_name` only for the root path `.`. A
repository with several packages reads two other outputs instead: `paths_released`, the
JSON array of the paths released by this run, and `all`, every output of the action as a
JSON object, where each path's keys carry it as a prefix (`apps/web--tag_name`,
`apps/web--release_created`, …).

```yaml
jobs:
  release:
    uses: 20262c-g14-discordia/.github/.github/workflows/release-please.yml@main
    secrets: inherit
  deploy-web:
    needs: release
    if: contains(fromJSON(needs.release.outputs.paths_released || '[]'), 'apps/web')
    uses: ./.github/workflows/deploy-web.yml
    with:
      tag: ${{ fromJSON(needs.release.outputs.all)['apps/web--tag_name'] }}
```

### The release token

With the default workflow token GitHub does not run CI on the release PR: it refuses to
trigger workflows from events that token creates. A fine-grained personal access token
stored as `RELEASE_PLEASE_TOKEN` is used instead when present, and the release PR then
gets the full CI run.

**Store it as a repository secret, not an organization secret.** The org is on the free
plan, where organization secrets are not available to private repositories: the workflow
reads an empty value and silently falls back to the workflow token. The symptom is a
release PR authored by `github-actions` with no checks on it; when the token is picked up,
the author is the token's owner and CI runs. The token needs Contents, Pull requests and
Issues at read and write on the repositories it covers.

## Changing the conventions

The rules themselves live in [`meta/CONTRIBUTING.md`](https://github.com/20262c-g14-discordia/meta/blob/main/CONTRIBUTING.md).
Change the rule there first, then the template or the check here, in one PR each. This
repo takes PRs like any other: squash only, `Ref DIS-n` in the body.

## Deploy actions

Composite actions a service repository's `deploy.yml` calls to publish a release to ECS.
The design, and why each step exists, is in
[`meta`'s continuous-deployment spec](https://github.com/20262c-g14-discordia/meta/blob/main/docs/superpowers/specs/2026-09-22-continuous-deployment-of-the-services-design.md).

| Action | Does |
|---|---|
| `actions/build-push` | Refuses anything but a release tag, builds, pushes `discordia/<image>:<tag>` to ECR, and records `…@sha256:…` in `/discordia/prd/<image>/image`, the version the platform runs |
| `actions/register-revision` | Registers a revision of the service's task definition with only one container's image changed |
| `actions/run-once` | Runs one task of a revision on the service's own network, with a command and environment override, and fails unless the container exits 0; the exit code and the stop reason go to the job summary |
| `actions/roll-service` | Rolls the service to an image or a revision and fails if the circuit breaker rolls it back, restoring the version `build-push` replaced |

With the platform down, `register-revision`, `run-once` and `roll-service` change nothing and
pass: the recorded image is what the next `make up` starts. An error that means "cannot
tell", such as a denied permission, fails instead.

```yaml
      - id: identity
        uses: 20262c-g14-discordia/.github/actions/build-push@v1
        with: { image: identity, context: ., tag: "${{ inputs.ref }}" }
      - uses: 20262c-g14-discordia/.github/actions/roll-service@v1
        with:
          service: identity
          image: ${{ steps.identity.outputs.image }}
          previous: ${{ steps.identity.outputs.previous }}
```

A service with a migration registers one revision, runs the migration from it, then rolls
to it, so both run the same digest. `run-once` borrows the service's subnets, security
groups and launch type, so it can reach whatever the service can. `environment` is added to
the container's own environment and wins over it. Anything the command needs to know from
AWS, such as a database task's address, is looked up by an earlier step in the caller and
passed in. The action does not look anything up.

```yaml
      - id: revision
        uses: 20262c-g14-discordia/.github/actions/register-revision@v1
        with: { service: messaging, image: "${{ steps.app.outputs.image }}" }
      - uses: 20262c-g14-discordia/.github/actions/run-once@v1
        with:
          service: messaging
          task-definition: ${{ steps.revision.outputs.arn }}
          command: '["/messaging", "migrate", "up"]'
          environment: '{"MONGO_URI": "${{ steps.mongo.outputs.uri }}"}'
      - uses: 20262c-g14-discordia/.github/actions/roll-service@v1
        with: { service: messaging, task-definition: "${{ steps.revision.outputs.arn }}" }
```

The deploy role needs `ecs:RunTask` on its task definitions, `ecs:DescribeTasks` (the wait
polls it) and `iam:PassRole` on the task's roles. `infrastructure`'s `service-deploy-role`
grants all three. The wait gives up after 10 minutes and fails the step, but the task may
still be running.

The logic is bash in `actions/lib/ecs.sh` and one script per action, tested with bats against
a fake `aws` (`test/stub/aws`): `mise install`, then `mise run test` and `mise run lint`.
Releases are the moving tag `v1`; a breaking change to an input or output is `v2`.
