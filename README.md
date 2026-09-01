# .github

Organization-wide defaults for `20262c-g14-discordia`. GitHub applies the files here to
every repository in the org that does not carry its own copy.

| File | What it does |
|---|---|
| `PULL_REQUEST_TEMPLATE.md` | The PR body every repo gets. Sections and the definition-of-done checklist mirror `meta/CONTRIBUTING.md`. |
| `.github/workflows/pr-checks.yml` | Reusable workflow that fails a PR whose title is not `type(scope): summary` or whose body has no `Ref DIS-n` / `Closes DIS-n` line. |

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

## Changing the conventions

The rules themselves live in [`meta/CONTRIBUTING.md`](https://github.com/20262c-g14-discordia/meta/blob/main/CONTRIBUTING.md).
Change the rule there first, then the template or the check here, in one PR each. This
repo takes PRs like any other: squash only, `Ref DIS-n` in the body.
