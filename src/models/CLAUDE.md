# src/models/

Plain Vala objects: state and pure logic only.

- Never import `Gtk`/`Adw` — that's what keeps a Model testable with no
  display, and reusable if the UI layer is ever swapped.
- One test binary per Model (`tests/models/<name>-test.vala`), run via
  `meson test -C builddir`.
- `Logger` lives here too — a plain stderr utility, not UI, same "no
  Gtk" rule as everything else in this directory.
