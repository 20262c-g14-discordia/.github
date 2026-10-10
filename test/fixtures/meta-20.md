Ref DIS-67

Research has all landed here so far, including investigations only one client acts on, and prototypes have lived on throwaway branches away from the findings they produced. Two rules.

## Research lives in the repository whose ADRs depend on it

The test is **how many repositories' ADRs turn on the answer**, not where the resulting code lands.

Most of it stays here, including questions that look like they belong to a single client: `discordia-web` and `discordia-mobile` are both TypeScript and both consume the same five OpenAPI contracts, so how those contracts become clients is a `meta` question even though the web client asked it first. `discordia-web` gains [its own `docs/research/`](https://github.com/20262c-g14-discordia/discordia-web/pull/11) for what is genuinely its alone.

When in doubt it goes here — moving research after an ADR cites it breaks the citation.

## A prototype is part of the research and travels with it

In `prototype/` inside the effort directory, in whichever repository that effort lives in. Never on a throwaway branch, and never split from its write-up: a prototype that has drifted from its findings is worse than none, because it still looks authoritative.

**This repository is still documentation and coordination.** A prototype committed here is a dated record of what was executed — not built, tested or linted by anything here, carrying its own `README.md` and its own manifest and lockfile so its dependencies never become ours, and not refactored after its effort closes.

## One new rule for research

**Executed beats read.** Where an effort ran something, the finding says so and names the command; a claim taken from documentation and never run is marked as such. Four claims in the OpenAPI generator research were wrong precisely because they were quoted rather than run — see #16.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01WuXcjW7f9nGc1C5pKBK8Em

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

* **Documentation**
  * Expanded research documentation guidance to cover prototypes, repository ownership, cross-repository ADR scope, and research procedures.
  * Documented requirements for storing and running throwaway prototype code, including isolation and reproducibility.
  * Clarified the distinction between executed research findings and documentation-only claims.

<!-- end of auto-generated comment: release notes by coderabbit.ai -->
