---
id: din-jf9s
status: closed
deps: []
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eqz3
tags: [foundation, config]
---
# Config: TOML schema, loading, validation, auto reload

~/.config/kex/kex.toml parsed with TOMLDecoder into a typed Config. Keys per PLAN.md config draft. Unknown keys and bad values produce a readable error shown in the menu bar and the log, and the previous config stays active. Watch the file and reload; also reload-config command.

## Acceptance Criteria

The draft config in PLAN.md loads. A typo in a key name is reported with the line. Editing the file applies within a second without restart.


## Notes

**2026-09-25T10:08:49Z**

KexConfig done: Config.parse/load, strict key checks (unknown keys name path + line), KeyCombo (AeroSpace key names), Color, Config.defaultTOML/Config.default, ConfigWatcher (debounced DispatchSource, survives atomic saves). 16 tests pass. Walks TOMLTable directly: TOMLDecoder 0.4.4's Decodable layer crashes on custom CodingKeys and TOMLTable.string(forKey:) crashes on one-digit integers (guarded). Remaining for this ticket: app wiring (start ConfigWatcher on ~/.config/kex/kex.toml, keep previous config on error, show error in menu bar + log, reload-config command).

**2026-09-25T10:25:02Z**

Library complete with 16 tests. App wiring (start watcher, keep previous config on error, show error in menu bar, reload-config command) moves to din-g6bk (command dispatcher). Closing.
