---
id: din-qdtu
status: closed
deps: []
links: []
created: 2026-09-26T21:36:18Z
type: feature
priority: 1
assignee: Mikkel Malmberg
tags: [release]
---
# Sparkle updates


## Notes

**2026-09-26T21:41:12Z**

Sparkle 2.9.6 via SwiftPM, rpath @executable_path/../Frameworks via unsafeFlags linker setting; framework copied and signed inside out in bundle.sh; EdDSA key in Keychain account com.brnbw.kex (public jif/E57Xw8xCo7BwHnOeASD+nbQc462aQTYOuvoH/io=); package-release signs zip and writes dist/appcast.xml via scripts/appcast.py; release.sh uploads appcast. Verified: just package 0.1.0 notarized Accepted, deep codesign and spctl pass; VM run loads Sparkle from the bundle and shows Check for Updates… in the status menu.
