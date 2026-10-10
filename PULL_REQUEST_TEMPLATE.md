<!--
Title: `type(scope): summary`, e.g. `feat(messaging): send a DM`. It becomes the squash
commit on main. `linear issue pr` prefixes the issue ID; that is fine.

Body: the first line links the Linear issue behind this PR. The brief requires it. Before
you write it, read the issue's acceptance criteria: a story's are in meta's
`docs/stories/`, a task's are its "done when". Then pick one:

- `Closes DIS-n` when this PR, with what is already merged, meets every criterion. Linear
  closes the issue only when its last linked PR merges, so a stack can say `Closes` on
  every PR.
- `Ref DIS-n` when a criterion stays unmet. Name it under "Still open".

Check the story above a slice too. If this PR finishes its last open slice, close the
story as well. If the backlog has nothing that fits, replace the line with one sentence
saying so. Every section stays; write "none" rather than deleting one.
-->

Closes DIS-

## Why

<!-- The story, task or decision this serves. Link the ADR when one drove it. -->

## What changes

<!-- One logical change. Tell the reviewer where to look first. -->

## Still open

<!-- For each issue referenced with `Ref`: "- DIS-n: the criteria this PR leaves unmet".
Otherwise "none". -->

## Out of scope

<!-- What this PR deliberately leaves out, with the issue that tracks it (DIS-n), or "none". -->

## How it was verified

<!-- Commands run and their result. Anything CI cannot see: manual checks, screenshots for UI. -->

## Definition of done

<!-- Defined in meta/CONTRIBUTING.md. Tick what applies; strike through what does not and say why. -->

- [ ] Tests cover the change, or the reason they cannot is stated above
- [ ] Screens touched handle loading, error and timeout states (clients)
- [ ] User-facing strings go through i18n (clients)
- [ ] The OpenAPI spec matches the endpoints touched (services)
- [ ] Any architectural choice is in an ADR in `meta`, referenced above
- [ ] README / AGENTS.md updated where behaviour or commands changed
- [ ] No secrets, and nothing committed that belongs in the environment
