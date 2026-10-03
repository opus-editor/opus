# Set up (or reconfigure, if it already exists) the Meson build directory.
# Needed once, and again after adding/removing a .vala file.
setup:
    @[ -d out/native ] && meson setup --reconfigure out/native || meson setup out/native

# Build the project, setting up out/native first if it doesn't exist yet.
build:
    @[ -d out/native ] || meson setup out/native
    ninja -C out/native

# Run the test suite.
test: build
    meson test -C out/native

# Run the app, optionally against a folder: `just run ~/some/project`.
# GSETTINGS_SCHEMA_DIR points GLib.Settings at the schema data/meson.build
# already compiles into the build dir (gnome.compile_schemas), so this
# works without `ninja install` — GLib.Settings would otherwise abort at
# startup, unable to find io.github.opus_editor.Opus's own schema at all.
run *ARGS: build
    GSETTINGS_SCHEMA_DIR=out/native/data ./out/native/src/opus {{ARGS}}

# Build the Flatpak from build/'s manifest and install it for the
# current user, so `flatpak run io.github.opus_editor.Opus` runs this
# working tree. Needs org.flatpak.Builder from Flathub (itself a
# Flatpak). --repo keeps a local OSTree repo for `just bundle`.
# Build the Flatpak from build/'s manifest and install it for your user.
flatpak:
    flatpak run org.flatpak.Builder --user --install --force-clean --ccache \
      --state-dir=out/flatpak/state --repo=out/flatpak/repo out/flatpak/app build/io.github.opus_editor.Opus.json

# Export the last `just flatpak` build as a single-file bundle — what a
# release attaches, and what install.sh installs.
# Export the last `just flatpak` build as out/flatpak/Opus.flatpak.
bundle:
    flatpak build-bundle out/flatpak/repo out/flatpak/Opus.flatpak io.github.opus_editor.Opus

# The CI — see docs/DEVELOPMENT_WORKFLOW.md. Runs the suite natively,
# then again inside a flatpak-builder build of the manifest (the Sdk's
# own toolchain, a bare environment like a release machine), and signs
# HEAD on GitHub when both pass. Refuses to sign anything that isn't
# exactly what was tested: a clean tree, already pushed.
# Run the whole suite natively and inside flatpak-builder, then `gh signoff` HEAD.
ci:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -z "$(git status --porcelain)" ] || { echo "ci: commit or stash your changes first — only what is committed gets tested and signed" >&2; exit 1; }
    git fetch -q origin
    git branch -r --contains HEAD | grep -q . || { echo "ci: push first — the signoff is recorded on the commit at GitHub" >&2; exit 1; }
    just test
    # The manifest, as a debug build with the tests on: the D-Bus surface
    # the system tests drive is #if DEBUG, and they need a session bus.
    # Derived here so the real manifest stays a plain release build.
    jq '.modules[-1]["config-opts"] = ["--buildtype=debug"]
        | .modules[-1]["run-tests"] = true
        | .modules[-1]["test-rule"] = ""
        | .modules[-1]["test-commands"] = ["dbus-run-session -- meson test -C /run/build/opus/_flatpak_build --print-errorlogs"]' \
      build/io.github.opus_editor.Opus.json > build/.ci.json
    trap 'rm -f build/.ci.json' EXIT
    # Without the desktop session's variables, as on a CI runner: with
    # them GIO picks different backends (proxy resolver, …) and hides
    # what a bare machine would hit.
    env -u XDG_CURRENT_DESKTOP -u DESKTOP_SESSION -u GNOME_DESKTOP_SESSION_ID \
      flatpak run org.flatpak.Builder --force-clean --ccache --state-dir=out/flatpak/state out/flatpak/app-ci build/.ci.json
    gh signoff

# Cuts version X.Y.Z from main — see docs/DEVELOPMENT_WORKFLOW.md. Bumps
# meson.build and the metainfo on a release branch, runs `just ci` on
# it, fast-forwards main, and pushes the tag that makes GitHub build
# and attach Opus.flatpak.
# Cut version X.Y.Z: bump, `just ci`, fast-forward main, push the tag.
release version:
    #!/usr/bin/env bash
    set -euo pipefail
    v='{{version}}'
    [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "release: version must be X.Y.Z, got '$v'" >&2; exit 1; }
    [ "$(git branch --show-current)" = main ] || { echo "release: run from main" >&2; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "release: the tree must be clean" >&2; exit 1; }
    git fetch -q origin
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "release: main is not in sync with origin/main" >&2; exit 1; }
    ! git rev-parse -q --verify "refs/tags/v$v" >/dev/null || { echo "release: tag v$v already exists" >&2; exit 1; }
    git checkout -q -b "release/$v"
    sed -i "s/^  version: '[^']*',/  version: '$v',/" meson.build
    sed -i "s|<releases>|<releases>\n    <release version=\"$v\" date=\"$(date -I)\"/>|" data/io.github.opus_editor.Opus.metainfo.xml
    git add meson.build data/io.github.opus_editor.Opus.metainfo.xml
    git commit -q -m "chore: release $v"
    git push -q -u origin "release/$v"
    just ci
    git checkout -q main
    git merge -q --ff-only "release/$v"
    git push -q
    git tag "v$v"
    git push -q origin "v$v"
    git branch -q -d "release/$v"
    git push -q origin --delete "release/$v"
    echo "v$v tagged — GitHub is building the release: https://github.com/opus-editor/opus/actions"

# Remove every generated file.
clean:
    rm -rf out
