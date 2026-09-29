# Opus

Native GTK4 + Libadwaita source code editor, written in Vala. See
[README.md](README.md) for the pitch.

## Building

```shell
meson setup builddir
ninja -C builddir
./builddir/src/opus
```

- Reconfigure after adding/removing a `.vala` file: `meson setup
  --reconfigure builddir` (Meson doesn't glob sources).
- Or via `justfile`: `just build`, `just test`, `just run [folder]`,
  `just clean`.
- Toolchain: Vala 0.56, Meson 1.7, GTK4 4.18, Libadwaita 1.7.

## Testing

```shell
meson test -C builddir
```

One test binary per Model. Views are currently untested — see
`src/views/CLAUDE.md`.

## Logging

- `Logger.warn`/`Logger.info` (`src/models/logger.vala`) print to stderr,
  gated by `-v`/`--verbose` (`just run -v`).
- Debug builds run them for real; release builds compile the whole
  namespace to no-ops — leave the calls in place after debugging.
- Use sparingly: real points of interest only, never routine narration.

## Comments

Keep them short, and only add one when the code can't carry the reason
on its own. A comment explains WHY, never WHAT or HOW — and never the
history of how the code got here (tried X, reverted, discussed); that
belongs in git history/PR descriptions and rots as the code moves on.

## Dev D-Bus control surface

Debug builds expose `io.github.nowaos.Opus.Dev` (`src/lib/dev-server/`)
on the app's own D-Bus connection:

```shell
gdbus call --session --dest io.github.nowaos.Opus --object-path /io/github/nowaos/Opus/Dev --method io.github.nowaos.Opus.Dev.OpenTab /path/to/file
```

`gdbus introspect` lists every method; same `--define=DEBUG` gate as
Logging.

## Structure

```
src/
  main.vala   entry point: reads argv/GLib.Settings, constructs App
  App.vala    the Adw.Application — owns every open MainWindow, settings, DevServer
  models/     see src/models/CLAUDE.md
  lib/        generic infra, independent of Opus's own domain — see src/lib/CLAUDE.md
  styles/     .css loaded by resource — see src/views/CLAUDE.md
  views/      see src/views/CLAUDE.md
data/         .desktop file, GResource XML, icons
```

## Architecture

- No Controller layer — a View absorbs whatever mediation a Controller
  used to do from outside it. See `src/views/CLAUDE.md`.
- A View is a facade: owns real widgets internally, exposes plain
  methods + signals — never a `Gtk.Widget` subclass passed around.
- Models never import `Gtk`/`Adw` — only `views/` does (`src/lib/` is
  the exception, generic infra that needs it for its own task — see
  `src/lib/CLAUDE.md`).
- Read the directory-local `CLAUDE.md` before touching a layer.
