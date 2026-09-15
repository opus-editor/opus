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
run *ARGS: build
    ./builddir/src/codi-gtk {{ARGS}}

# Remove the build directory.
clean:
    rm -rf builddir
