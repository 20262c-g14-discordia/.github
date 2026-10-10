# CLAUDE.md

Organization defaults for `20262c-g14-discordia`: the PR template and the reusable
PR-convention workflow that every repository in the org inherits. `README.md` says what
each file does and how a repository opts in.

The rules these files enforce belong to
[`meta/CONTRIBUTING.md`](https://github.com/20262c-g14-discordia/meta/blob/main/CONTRIBUTING.md).
Do not change a rule here without changing it there; do not add a rule here that `meta`
does not state. Read `meta/CLAUDE.md` for the project itself.

Anything that leaves this machine (push, PRs, merges, repository or organization
settings) needs the user to ask for it, every time. Never `git add -A` or `git add .`.

## Rules and what enforces them

| Rule | Enforced by |
|---|---|
| PR titles are `type(scope): summary` | `pr-checks.yml`, title step: fails the run |
| Every PR references a Linear issue | `pr-checks.yml`, body step: warns only, by the team's choice in `meta/CONTRIBUTING.md` |
| A PR closes its Linear issue, or says which criteria stay open | Nothing, by the team's choice: a check costs Actions minutes on every PR and cannot judge the criteria anyway. The template's `Closes DIS-` line and `## Still open` section, and each repo's agent instructions, carry it |
