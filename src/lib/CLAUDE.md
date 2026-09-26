# src/lib/

The "lib/" half of a Rails-style `app/` vs `lib/` split: generic
infrastructure, independent of Opus's own domain concepts.

- `global-css.vala` (`GlobalCss`) — loads a `.css` file by GResource path.
  Loading CSS isn't an Opus concept, it's a generic GTK technique.
- `dev-server/` (`Opus.Dev.DevServer`/`IDevServer`) — the debug-only D-Bus control
  surface (see its own doc comment). Dev tooling, not editor logic.
