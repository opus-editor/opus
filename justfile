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
# startup, unable to find io.github.nowaos.Opus's own schema at all.
run *ARGS: build
    GSETTINGS_SCHEMA_DIR=builddir/data ./builddir/src/opus {{ARGS}}

# Remove the build directory.
clean:
    rm -rf builddir
