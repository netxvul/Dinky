build:
    swift build

test:
    swift test

bundle *flags:
    scripts/bundle.sh {{flags}}

# Debug bundle, replace any running kex, and run attached so logs stream here (fut's run extension uses this).
run: kill
    scripts/bundle.sh --debug
    ./build/Kex.app/Contents/MacOS/kex

kill:
    pkill -f "Kex.app/Contents/MacOS/kex" || true

vm-install: bundle
    scripts/vm-install.sh

# Symlink the bundled CLI into ~/.local/bin so `kex <command>` works from any shell.
install: bundle
    mkdir -p ~/.local/bin
    ln -sf "$PWD/build/Kex.app/Contents/MacOS/kex" ~/.local/bin/kex
    ls -l ~/.local/bin/kex

# Fuzz the debug build in the Tart VM: random actions, layout invariants checked after each. See scripts/fuzz.py.
fuzz seed="1" steps="150": build
    scripts/vm-fuzz.sh {{seed}} {{steps}}

# Build, sign with Developer ID, notarize and staple into dist/, without publishing.
package version:
    scripts/package-release.sh {{quote(version)}}

# Prepare, test, package, tag and publish a GitHub release from a clean, pushed main. The version defaults
# to the latest tag plus 0.1.
release version="":
    scripts/release.sh {{quote(version)}}
