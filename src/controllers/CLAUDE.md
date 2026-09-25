# src/controllers/

Mediates Model <-> View. Holds a direct reference to a concrete View class
(`EditorView.FileTree`, not an interface) — there's no `I*View` seam anymore, it
was dropped for faster iteration on the UI. What still holds regardless:
a Controller never imports `Gtk`/`Adw` itself, and only ever calls a View's
public methods or connects to its signals.

Untested for now — removing the interfaces removed the fakes that made
these testable without a real display. If that seam comes back, tests go
in `tests/controllers/<name>-test.vala`, one binary per Controller.
