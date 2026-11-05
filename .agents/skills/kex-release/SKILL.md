---
name: kex-release
description: Review kex changes, docs, and changelog notes since the last release, then publish with `just release`.
---

# kex release

`RELEASING.md` is the canonical release procedure; read it before publishing.

## Readiness

Review the delta from the newest `v*` tag:

```bash
git log --format='%h %s%n%b' "$(git tag --list 'v*' --sort=-v:refname | head -1)"..origin/main
git diff --stat "$(git tag --list 'v*' --sort=-v:refname | head -1)"..origin/main
```

Include local commits that are not yet pushed, and ask before pushing them.

Review the documentation against the delta, not just the changelog. For every changed behavior,
command, flag, config key, default, and error, search `docs/index.md`, `docs/commands.md`,
`docs/configuration.md`, and `README.md`, and fix stale pages before release. Config changes must also
update `docs/schemas/kex.json` and agree with `Sources/KexConfig/DefaultConfig.swift`. Removed or
renamed config must be documented with what to write instead.

Docs come before the changelog and before approval: don't draft release notes for a change the manual
doesn't describe yet. Commit doc fixes along with the changelog, and in the approval question list
each doc page you checked and what you changed on it (or "no change needed"), so the review is visible.

Run `just test`. For risky window, Space, or display changes, the Tart VM fuzz (`just fuzz`) and a
manual smoke check are optional tools, not publication requirements.

## Changelog

`CHANGELOG.md` must have an accurate `## Unreleased` section for the delta. Write it as end-user
release notes: user-visible effects from the user's viewpoint, no implementation details, nothing
purely internal (release tooling, refactors, tests, manual reorganizations). Bullets may accumulate
during development; before approval, consolidate them into short, direct `###` sections grouped by
user-facing area, with fixes last under `### Fixes`. Put a plain upgrade warning first when existing
configs, hooks, or scripts may break, saying exactly what to change.

## Approval

Show the final `## Unreleased` section verbatim with the version it will ship as, and get approval for
that concrete release unless it was already given in this conversation for the same version and notes.
Ask again only if the version or notes materially change. Put the notes in the approval question itself
(the question text or an option's preview), since text before the question may not be visible while the
user answers. A readiness review alone does not authorize
publication.

## Publish

```bash
just release          # latest tag + 0.1
just release 1.0      # explicit version
```

Start from a clean local `main` that exactly matches `origin/main`. The command tests, turns
`## Unreleased` into `## X.Y`, sets `version:` in `docs/_config.yml`, commits and pushes
`Release X.Y`, then packages, notarizes, tags, publishes the GitHub release with that changelog
section as its notes, and updates the Homebrew tap. After a failure, rerun the same command without
adding commits; it reuses the prepared commit. Signing and notarization need the local keychain, so
run it on the release Mac.
