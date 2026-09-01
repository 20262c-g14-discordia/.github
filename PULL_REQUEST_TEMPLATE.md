<!--
Title: `type(scope): summary`, e.g. `feat(messaging): send a DM`. It becomes the squash
commit on main. `linear issue pr` prefixes the issue ID; that is fine.

Body: keep the `Ref DIS-n` line, the PR check fails without it. Use `Closes DIS-n` when
this PR finishes the issue. Every section stays; write "none" rather than deleting one.
-->

Ref DIS-

## Why

<!-- The story, task or decision this serves. Link the ADR when one drove it. -->

## What changes

<!-- One logical change. Tell the reviewer where to look first. -->

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
- [ ] README / CLAUDE.md updated where behaviour or commands changed
- [ ] No secrets, and nothing committed that belongs in the environment
