# Releases

Versions are `X.Y`, bumped by 0.1 each release (0.9 is followed by 0.10 unless you ask for 1.0). User-visible changes go in `CHANGELOG.md` under `## Unreleased` as they land, written for users; the `kex-release` skill in `.agents/skills` reviews the delta, the manual and those notes before a release.

Run `just release` from a clean `main` that matches `origin/main` (or `just release 1.0` to pick the version). It runs the tests, renames `## Unreleased` to `## 0.4`, sets `version:` in `docs/_config.yml` (the manual's front page shows it), commits and pushes `Release 0.4`, builds an arm64 release bundle, signs it with your Developer ID Application identity with the hardened runtime, notarizes and staples it using the `TunaNotary` keychain profile, zips it to `dist/Kex.app.zip`, signs the zip for Sparkle and writes `dist/appcast.xml` with the `## 0.4` section of the changelog, rendered by GitHub, as the notes the update window shows, writes `dist/kex.rb` from `scripts/kex.rb.template`, tags `v0.4`, creates a draft GitHub release whose notes are the `## 0.4` section of the changelog, uploads the zip, the appcast and the cask, publishes it as latest, and pushes the cask to [mikker/homebrew-tap](https://github.com/mikker/homebrew-tap) through a temporary clone. Running it again without adding commits reuses the `Release 0.4` commit and retries a failed release or tap update; a published version is never replaced.

`just package 0.4` does everything up to and including the zip, appcast and cask without publishing. Override `NOTARYTOOL_PROFILE` or `DEVELOPER_ID_APPLICATION` when needed. The build number is the commit count plus 100. macOS 27 runs on Apple silicon only, so releases are not universal.

## Updates

Kex updates itself with [Sparkle](https://sparkle-project.org) (SwiftPM package, `Sparkle.framework` in `Contents/Frameworks`, signed inside out by `scripts/bundle.sh`). The feed, `SUFeedURL` in `Resources/Info.plist`, is https://github.com/mikker/Dinky/releases/latest/download/appcast.xml: the `appcast.xml` asset of the latest release, so publishing a release is what ships the update. `scripts/appcast.py` writes it from the built app and the zip.

Updates are signed with an EdDSA key whose private half lives in the login Keychain under the account `com.brnbw.kex`; `sign_update --account com.brnbw.kex` uses it during packaging. The public key, `SUPublicEDKey`, is `jif/E57Xw8xCo7BwHnOeASD+nbQc462aQTYOuvoH/io=`. Losing the private key means installed copies can no longer update, so keep a backup somewhere safe:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x kex-sparkle-key --account com.brnbw.kex
```

Import it on another Mac with `generate_keys -f kex-sparkle-key --account com.brnbw.kex`.
