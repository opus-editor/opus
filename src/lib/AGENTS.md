# src/lib/

The "lib/" half of a Rails-style `app/` vs `lib/` split: generic
infrastructure, independent of Opus's own domain concepts.

- `global-css.vala` (`GlobalCss`) — loads a `.css` file by GResource path.
  Loading CSS isn't an Opus concept, it's a generic GTK technique.
- `logger.vala` (`Logger`) — stderr logger gated behind `-v`/`--verbose`,
  compiling to a true no-op in a release build (see its own doc comment).
  A plain process concept, nothing Opus-specific about it.
- `dev-server/` (`Opus.Dev.DevServer`/`IDevServer`) — the debug-only D-Bus control
  surface (see its own doc comment). Dev tooling, not editor logic.
- `lua-sandbox.vala` (`LuaSandbox`) — a Lua 5.4 state to run a transform
  script in: standard libraries minus everything that reaches outside the
  process, an `opus` table of Unicode-aware string helpers, an instruction
  limit. Strings and offsets in, strings out; nothing of Opus's own.
- `host-command.vala` (`HostCommand`) — the argv for a command that must
  run with the user's own tools: untouched natively, routed through
  `flatpak-spawn --host` inside a Flatpak sandbox (see its own doc
  comment). Every `git` spawn goes through it. Process plumbing, not an
  Opus concept.
- `crash-handler.vala` (`CrashHandler`) — SIGSEGV/SIGABRT/… handler that
  shells out to `gdb` for a real backtrace on crash (see its own doc
  comment). Not itself debug-only, unlike `Logger`/`DevServer` above:
  main.vala only ever calls `install()` inside its own `#if DEBUG`.
