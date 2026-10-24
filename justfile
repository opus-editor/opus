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
# OPUS_APP_ID gives this build its own id on the session bus — under the
# real one, GApplication's single-instance rule would hand the launch
# off to an installed Opus that happens to be open, and this tree's
# binary would never run at all.
# GSETTINGS_SCHEMA_DIR points GLib.Settings at the schema data/meson.build
# already compiles into the build dir (gnome.compile_schemas), so this
# works without `ninja install` — GLib.Settings would otherwise abort at
# startup, unable to find io.github.opus_editor.Opus's own schema at all.
# The others do the same for the bundled languages and themes: packages
# and themes straight from the source tree, grammars from the build dir.
run *ARGS: build
    OPUS_APP_ID=io.github.opus_editor.Opus.Devel GSETTINGS_SCHEMA_DIR=out/native/data OPUS_LANGUAGES_DIR=languages OPUS_GRAMMARS_DIR=out/native/languages OPUS_THEMES_DIR=src/themes OPUS_FUNCTIONS_DIR=src/functions ./out/native/src/opus {{ARGS}}

# Opens the app sized to exactly match the window in assets/preview.png
# (1080x720 — the image itself is 1202x842, padded by its drop shadow),
# so a plain window screenshot drops straight into README.md's Preview
# section without cropping or resizing. Restores whatever window size
# was set before, once the window closes — window-width/window-height
# are saved dconf state (src/views/main/main-window/index.vala), shared
# with every other launch, not something this should leave changed.
run-preview-setup: build
    #!/usr/bin/env bash
    set -euo pipefail
    schema=io.github.opus_editor.Opus
    export GSETTINGS_SCHEMA_DIR=out/native/data
    width="$(gsettings get "$schema" window-width)"
    height="$(gsettings get "$schema" window-height)"
    trap 'gsettings set "$schema" window-width "$width"; gsettings set "$schema" window-height "$height"' EXIT
    gsettings set "$schema" window-width 1080
    gsettings set "$schema" window-height 720
    just run

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

# Takes the version from the branch name and refuses any other branch,
# or a head `just ci` hasn't signed. Puts the version into meson.build,
# the metainfo and the README as one more commit, signed without a
# second run of the suite: the recipe checks that nothing but those
# three files changed since the tested commit. main is advanced by
# pushing the branch straight onto it, so the server's own fast-forward
# check decides — a main someone moved meanwhile refuses the push and
# nothing has been touched yet. Then the tag, which GitHub builds the
# Flatpak off, and the branch goes. Run again after a failure and the
# version bump is kept, not redone.
# Ship the version the branch is named for: from release/X.Y.Z, after `just ci`.
release:
    #!/usr/bin/env bash
    set -euo pipefail
    branch="$(git branch --show-current)"
    [[ "$branch" =~ ^release/([0-9]+\.[0-9]+\.[0-9]+)$ ]] || { echo "release: run from a release/X.Y.Z branch, not '$branch'" >&2; exit 1; }
    v="${BASH_REMATCH[1]}"
    files=(meson.build data/io.github.opus_editor.Opus.metainfo.xml README.md)
    [ -z "$(git status --porcelain)" ] || { echo "release: the tree must be clean" >&2; exit 1; }
    git fetch -q origin
    ! git rev-parse -q --verify "refs/tags/v$v" >/dev/null || { echo "release: tag v$v already exists" >&2; exit 1; }
    [ "$(git merge-base origin/main HEAD)" = "$(git rev-parse origin/main)" ] || { echo "release: $branch is behind main — rebase it first" >&2; exit 1; }
    if [ "$(git log -1 --format=%s)" = "chore: release $v" ]; then
      tested="$(git rev-parse HEAD~1)"
    else
      tested="$(git rev-parse HEAD)"
      git branch -r --contains "$tested" | grep -q . || { echo "release: push first — just ci signs the commit at GitHub" >&2; exit 1; }
      sed -i "s/^  version: '[^']*',/  version: '$v',/" meson.build
      sed -i "s|<releases>|<releases>\n    <release version=\"$v\" date=\"$(date -I)\"/>|" data/io.github.opus_editor.Opus.metainfo.xml
      sed -i -E "s|(<b id=\"app-version\">)[^<]*(</b>)|\\1$v\\2|" README.md
      git add "${files[@]}"
      git commit -q -m "chore: release $v"
    fi
    gh signoff status --commit "$tested" | grep -q '✓' || { echo "release: run just ci first — $tested isn't signed" >&2; exit 1; }
    [ "$(git diff --name-only "$tested" HEAD | sort | tr '\n' ' ')" = "$(printf '%s\n' "${files[@]}" | sort | tr '\n' ' ')" ] || { echo "release: more than the version changed since the tested commit $tested" >&2; exit 1; }
    git push -q -u origin "$branch"
    gh signoff
    git push -q origin "$branch:main" || { echo "release: main moved while this ran — rebase $branch onto it, just ci, and run again" >&2; exit 1; }
    git tag "v$v"
    git push -q origin "v$v"
    git checkout -q main
    git pull -q --ff-only
    git branch -q -d "$branch"
    git push -q origin --delete "$branch"
    echo "v$v tagged — GitHub is building the release: https://github.com/opus-editor/opus/actions"

# Remove every generated file.
clean:
    rm -rf out
