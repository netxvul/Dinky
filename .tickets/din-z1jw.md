---
id: din-z1jw
status: closed
deps: []
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eqz3
tags: [foundation, app]
---
# App bundle, signing, Accessibility onboarding, launch at login

Turn the bare executable into Kex.app: Info.plist with LSUIElement, stable signing identity so the Accessibility grant survives rebuilds, first-run flow that explains and opens the Accessibility pane, SMAppService launch at login. Onboarding also offers to turn off the native 'switch to a Space with open windows' setting, with the reason.

## Acceptance Criteria

A rebuilt app keeps its Accessibility grant. First launch shows onboarding until permission is granted. Launch at login works and can be turned off in config.


## Notes

**2026-09-25T10:04:24Z**

Built: scripts/bundle.sh (+ --debug), scripts/vm-install.sh, Resources/Info.plist, Justfile (build/test/bundle/run/vm-install), Sources/kex/Onboarding.swift, App.swift runs applyStartAtLogin + onboarding before the tap/follower/status item. Signed with 'Apple Development: Mikkel Malmberg (VAW8MWER4W)', no hardened runtime, no entitlements; two consecutive bundles give the same designated requirement (identifier com.brnbw.kex + leaf CN). VM: untrusted launch shows Accessibility step; after TCC insert a running instance did NOT flip (direct DB insert does not notify the process; toggling in Settings should), relaunch went straight to step 2 and the status item. Leave It and Turn It Off both verified via System Events (Turn It Off restarted the Dock, set workspaces-auto-swoosh false). SMAppService register -> BTM disposition enabled; start-at-login=false -> disabled. Open: start-at-login still read from UserDefaults (TODO(din-jf9s)); grant survival across rebuilds inferred from identical DR, not tested on host with SIP on.

**2026-09-25T10:25:03Z**

Bundle, onboarding and launch at login done and verified in the VM. start-at-login must read Config once din-g6bk wires config into the app; add that there. Host check that the Accessibility grant survives a rebuild belongs to din-drei. Closing.
