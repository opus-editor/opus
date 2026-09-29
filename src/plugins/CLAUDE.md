# src/plugins/

One directory per plugin, each owning its own manifest, entry point, and
`meson.build`. See `GIT_STATUS_PLUGIN_PLAN.md` for the architecture this
tree implements (`libpeas` in embedded mode — compiled into the `opus`
binary, but structurally the same shape a real loadable `.so` plugin
would be).

- A plugin's own code is Model-grade by default: no `Gtk`/`Adw`, same
  rule as `src/models/`. A plugin that needs widgets puts them in its own
  `views/` subdirectory, following `src/views/CLAUDE.md`.
- Only `plugin.vala` (the manifest's own `Embedded=` entry point) may
  import `Peas` — every other file in a plugin, including its own
  provider classes, only ever touches the plain `I*` interfaces and
  `WorkspaceContext` under `src/models/`. This keeps a plugin's real
  logic testable without linking libpeas at all (see e.g.
  `git-status/meson.build`'s split between `git-status.vala`/
  `provider.vala` and `plugin.vala`).
- A plugin talks to the host exclusively through `WorkspaceContext` and
  whichever extension-point interface(s) it implements — never by
  importing a View.
- One (or more, split by concern — see `git-status/test/`) test binary
  per plugin, under its own `test/` subdirectory, not the top-level
  `tests/` tree: `src/plugins/CLAUDE.md`'s own "one binary per Model"
  cousin rule in `src/models/CLAUDE.md` doesn't bind a plugin package,
  since a plugin isn't a Model.

## Interface declaration order matters

A Vala class implementing an interface that itself has another interface
as a prerequisite (e.g. `FileDecoration.IProvider : Object,
IWorkspaceExtension`) must list that prerequisite *before* the dependent
interface in its own declaration — `Object, IWorkspaceExtension,
FileDecoration.IProvider`, not the reverse. Getting the order backwards
compiles cleanly but aborts at runtime (`GLib-GObject-FATAL-CRITICAL:
... does not conform to prerequisite ...`), confirmed live while building
this plugin's own tests.
