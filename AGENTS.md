# Opus

Native GTK4 + Libadwaita source code editor, written in Vala. See
[README.md](README.md) for the pitch.

## Building

```shell
meson setup out/native
ninja -C out/native
./out/native/src/opus
```

- Reconfigure after adding/removing a `.vala` file: `meson setup
  --reconfigure out/native` (Meson doesn't glob sources).
- After adding a bundled language or changing its `grammar` pin, run
  `tools/sync-grammars.py`: it regenerates the wraps, `languages/meson.build`
  and the Flatpak's grammar sources from `languages/*/language.json`.
- Or via `justfile`: `just build`, `just test`, `just run [folder]`,
  `just clean`.
- Toolchain: Vala 0.56, Meson 1.7, GTK4 4.18, Libadwaita 1.7.

## Testing

```shell
meson test -C out/native
```

One test binary per Model. Views are currently untested — see
`src/views/AGENTS.md`.

One test binary per bundled language too (`tests/languages/<name>-test.vala`):
what that package's own queries make the editor do — colors, indentation,
embedded languages — against its real grammar. A language's behaviour is
tested there, never in a Model's test: `tests/models/syntax/` uses small
made-up queries over the JSON grammar, so it only ever fails for the
Model's own reasons.

## Logging

- `Logger.warn`/`Logger.info` (`src/lib/logger.vala`) print to stderr,
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

Debug builds expose `io.github.opus_editor.Opus.Dev` (`src/lib/dev-server/`)
on the app's own D-Bus connection:

```shell
gdbus call --session --dest io.github.opus_editor.Opus --object-path /io/github/opus_editor/Opus/Dev --method io.github.opus_editor.Opus.Dev.OpenTab /path/to/file
```

`gdbus introspect` lists every method; same `--define=DEBUG` gate as
Logging.

## Structure

```
src/
  main.vala   entry point: constructs App and hands it argv via run()
  App.vala    the Adw.Application — reads argv (command_line()), owns every
              open MainWindow, GLib.Settings, DevServer
  models/     see src/models/AGENTS.md
  lib/        generic infra, independent of Opus's own domain — see src/lib/AGENTS.md
  plugins/    libpeas plugins, one directory each — see src/plugins/AGENTS.md
  styles/     .css loaded by resource — see src/views/AGENTS.md
  views/      see src/views/AGENTS.md
data/         .desktop file, GResource XML, icons
themes/       bundled editor themes, one JSON file each — the same file a
              user drops in their own themes directory
languages/    bundled language packages, one directory each: language.json
              + queries/*.scm — the same shape a user's own package has
              (see docs/LANGUAGE_PACKAGES.md)
subprojects/  tree-sitter and one pinned grammar per .wrap
vapi/         hand-written bindings (tree-sitter)
```

## Architecture

See `docs/ARCHITECTURE.md` for the rules. Read the directory-local
`AGENTS.md` before touching a layer.
