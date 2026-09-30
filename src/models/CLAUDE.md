# src/models/

Plain Vala objects: state and pure logic only.

- Never import `Gtk`/`Adw` — that's what keeps a Model testable with no
  display, and reusable if the UI layer is ever swapped.
- One test binary per Model (`tests/models/<name>-test.vala`), run via
  `meson test -C builddir`.
