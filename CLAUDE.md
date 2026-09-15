# Opus

Native GTK4 + Libadwaita source code editor, written in Vala. See
[README.md](README.md) for the pitch.

## Building

```shell
meson setup builddir
ninja -C builddir
./builddir/src/opus
```

Rebuild after adding/removing a `.vala` file: `meson setup --reconfigure
builddir` (Meson doesn't glob sources — every file must be listed in the
nearest `meson.build`).

Or via the `justfile` (`just --list` for the full set): `just build`,
`just test`, `just run [folder]`, `just clean`.

Toolchain this was written against: Vala 0.56, Meson 1.7, GTK4 4.18,
Libadwaita 1.7.

## Testing

```shell
meson test -C builddir
```

One test binary per Model. Controllers and Views are currently untested —
see `src/controllers/CLAUDE.md` and `src/views/CLAUDE.md`.

## Logging

`Logger.warn`/`Logger.info` (`src/models/logger.vala`) print to stderr, gated
by a runtime `-v`/`--verbose` flag (`just run -v`). In a `debug` buildtype
(the default), Meson passes `--define=DEBUG` to valac and these calls do
real work; in a `release` build the whole namespace body compiles to empty
functions — calls stay in the source, but the logging is gone from the
binary, not just silenced. Leave `Logger.warn (...)` calls in place rather
than deleting them after debugging.

Use sparingly: only at real points of interest (a signal crossing a
Controller/View boundary, a decision branch worth tracing), never scattered
across every function — it's a diagnostic tool, not routine narration.

## Structure

```
src/
  main.vala        entry point: builds Models, Views, Controllers and wires them together
  models/          see src/models/CLAUDE.md
  controllers/     see src/controllers/CLAUDE.md
  views/           see src/views/CLAUDE.md
data/              .desktop file, GResource XML, icons
```

## Architecture

MVC. A **View is not a window or widget** — it's a facade that owns one (or
several) internally and exposes plain methods + signals. Models and
Controllers never import `Gtk`/`Adw` — only `views/` does. Read the
directory-local `CLAUDE.md` for each layer's specifics before touching it.
