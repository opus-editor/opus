# src/lib/

Small, cross-cutting helpers that aren't Models (no plain state/business
logic that would belong in `models/`) and aren't Views (no widgets, no
Blueprint template) — just plain functions/objects any layer can call
into.

`Gdk` is fine here — the actual boundary is `Gtk`/`Adw`, which stays
`views/`-only (see `CursorController`'s own `Gdk.Key`/`Gdk.ModifierType`
use for the same distinction outside `views/`). If something in here ever
needs `Gtk`/`Adw`, it belongs in `views/lib/` instead, not here.

Untested for now — nothing here has its own test binary yet; if one's
needed, `tests/lib/<name>-test.vala`, same one-binary-per-file pattern as
`models/`.
