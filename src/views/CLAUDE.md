# src/views/

The only directory allowed to import `Gtk`/`Adw`. A View is a facade that
owns real widgets internally and exposes plain methods + signals to its
Controller — never a `Gtk.Widget` subclass passed around directly.

## Layout

Each view gets its own `views/<name>/`:

- `index.vala` — the facade class
- `index.blp` — its Blueprint template, if it has one (some views, like
  `file-tree/` and `tab-bar/`, are built entirely in code and have none)

A sub-widget used only by its owning view lives alongside it with a leading
underscore instead of getting its own top-level directory: `file-tree/
_row.{vala,blp}` for `FileTreeRow`, `tab-bar/_pill.{vala,blp}` for `TabPill`.

Load a compiled template via `Gtk.Builder.from_resource (...)` in the
constructor, not a `[GtkTemplate]` composite-template subclass — some Gtk
types (`Gtk.ScrolledWindow`, `Gtk.Label`, …) are `final` and can't be
subclassed at all, so templating consistently through `Gtk.Builder` avoids
hitting that wall on a future view.

## Signal connections don't keep an object alive

A `this`-capturing closure connects through `g_signal_connect_object`,
which only guarantees a clean disconnect if the connected object dies — it
never keeps that object alive itself. Anything with its own signal
handlers (a Controller, a View) needs an explicit owner for as long as it
should react to events; see `Session` in `main.vala` for how the app's
Controllers/Views are kept alive.
