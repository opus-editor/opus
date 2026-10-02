# Set up (or reconfigure, if it already exists) the Meson build directory.
# Needed once, and again after adding/removing a .vala file.
setup:
    @[ -d builddir ] && meson setup --reconfigure builddir || meson setup builddir

# Build the project, setting up builddir first if it doesn't exist yet.
build:
    @[ -d builddir ] || meson setup builddir
    ninja -C builddir

# Run the test suite.
test: build
    meson test -C builddir

# Run the app, optionally against a folder: `just run ~/some/project`.
# GSETTINGS_SCHEMA_DIR points GLib.Settings at the schema data/meson.build
# already compiles into the build dir (gnome.compile_schemas), so this
# works without `ninja install` — GLib.Settings would otherwise abort at
# startup, unable to find io.github.opus_editor.Opus's own schema at all.
run *ARGS: build
    GSETTINGS_SCHEMA_DIR=builddir/data ./builddir/src/opus {{ARGS}}

# Build the Flatpak from build-aux/'s manifest and install it for the
# current user, so `flatpak run io.github.opus_editor.Opus` runs this
# working tree. Needs org.flatpak.Builder from Flathub (itself a
# Flatpak). --repo keeps a local OSTree repo for `just bundle`.
flatpak:
    flatpak run org.flatpak.Builder --user --install --force-clean --ccache \
      --repo=flatpak-repo flatpak-build build-aux/io.github.opus_editor.Opus.json

# Export the last `just flatpak` build as a single-file bundle — what a
# release attaches, and what install.sh installs.
bundle:
    flatpak build-bundle flatpak-repo Opus.flatpak io.github.opus_editor.Opus

# Remove the build directory.
clean:
    rm -rf builddir flatpak-build flatpak-repo .flatpak-builder Opus.flatpak
