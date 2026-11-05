---
id: din-aklv
status: closed
deps: [din-6523]
links: []
created: 2026-09-25T09:32:54Z
type: task
priority: 2
assignee: Mikkel Malmberg
parent: din-7cqx
tags: [release, docs]
---
# README with config and command reference

Install, permissions, config keys with defaults, command list, known limits (SIP-on private APIs, macOS version sensitivity).

## Acceptance Criteria

A new user can install and configure kex from the README alone.


## Notes

**2026-09-25T10:54:06Z**

README.md written: requirements, install (just bundle with IDENTITY), onboarding, how switching works, every config key with code defaults, full default config, all 18 commands from Reference.swift incl. retile, key syntax, CLI and socket protocol, status, known limits, credits. Verified keys against Config.swift/Rules.swift and commands against Reference.swift (swift run was broken mid-edit by other agents). Status section reflects Dispatcher as of now; revisit when resize width/height, layout floating/tiling and restore-on-quit land.
