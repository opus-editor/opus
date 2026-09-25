# src/views/

The only directory allowed to import `Gtk`/`Adw`. A View is a facade that
owns real widgets internally and exposes plain methods + signals to its
Controller — never a `Gtk.Widget` subclass passed around directly.

## Layout

`views/` is organized by domain first, not by widget kind — the same
domains the app itself is split into:

```
views/
  lib/              app-wide supporting code — not itself a widget (below)
    file-drag/
  components/       app-wide reusable Gtk.Widget subclasses (below)
  main/             the window chrome: header, global menu, sidebar toggle
    main-window/
  editor-view/      everything the editor tab owns
    file-tree/
    tab-bar/
    text-editor/
    find-bar/
  git-view/         future — not created until there's a git UI to put there
```

Within any of those, each view gets its own `<domain>/<name>/`:

- `index.vala` — the facade class
- `index.blp` — its Blueprint template, if it has one (some views, like
  `file-tree/` and `tab-bar/`, are built entirely in code and have none)

A sub-widget used only by its owning view lives alongside it with a leading
underscore instead of getting its own directory: `file-tree/
_row.{vala,blp}` for `EditorView.FileTreeRow`, `tab-bar/_pill.{vala,blp}`
for `EditorView.TabBarPill`. A sub-widget joins its owning view's own
namespace (if it has one) the same way the view itself does — it's never
qualified any deeper just for being "only" a sub-widget.

## Naming: no stacked suffixes, and namespace by domain

A view's own class name doesn't repeat "View" (or its directory's own
name) — the location under `views/<domain>/<name>/` already says that.
Two ways this shows up:

- `main/main-window/index.vala` defines a plain `MainWindow`, no
  namespace — `main/` only has this one view in it, nothing to
  disambiguate against.
- `editor-view/` has several sibling views, so its own domain name is a
  real `namespace EditorView { ... }`, reopened once per view (and once
  per sub-widget) inside it: `EditorView.FileTree`/`FileTreeRow`,
  `EditorView.TabBar`/`TabBarPill`/`TabBarGhost`,
  `EditorView.TextEditor`/`TextEditorSourceView`/`TextEditorDragPayload`,
  `EditorView.FindBar`. A sub-widget's own suffix names its owning view,
  not just its own role (`TabBarPill`, not `Pill`) — keeps the type
  readable on its own, away from its file, in a stack trace or a grep
  across the whole codebase.

Code elsewhere always spells the full `EditorView.FileTree` — this
codebase never uses `using` to shorten a namespace (every `Gtk`/`Adw`/
`Gdk` reference is written out in full too), so stay consistent rather
than relying on unqualified lookup working from inside the same
namespace. Code that's *itself* already inside `namespace EditorView`
(another file reopening the same namespace) can and should drop the
prefix — `TabBar` from inside `text-editor/index.vala`, say — since
that's exactly the same-namespace lookup Vala already gives for free.

Vala has no per-file module scope the way JS/ES modules do: every class
not inside a `namespace` lands in one shared root namespace across the
*whole* compiled binary, and two unrelated classes reusing the same bare
name is a hard compile error, not a silent shadow (confirmed directly:
two files each declaring `public class Foo` fail with "The root
namespace already contains a definition for `Foo'"). A domain's own
`namespace` is what actually prevents that for its own views, not just
which directory they happen to live in — `views/lib/`, `views/components/`,
and `main/` all stay unnamespaced today (nothing to disambiguate against
yet), so a name added there is still one global name the same as a
plain top-level Model class — pick one that stays unique on its own.

## `lib/` vs `components/`

Both hold code shared *across* domains (used by more than one of
`main/`/`editor-view/`/a future `git-view/`) — the split is whether it's
itself a `Gtk.Widget`:

- `views/lib/` — supporting code that isn't a widget: plain `Object`
  helper/data classes, interfaces, delegates, or a namespace of pure
  functions (`ContextMenu`, `GlobalPanel`, `EditorColors.desaturate()`,
  the `FileDrag`/`FileDragPayload`/`FileDragCandidate` trio in its own
  `file-drag/` — nested one level since the three are only meaningful
  together, same reasoning as a view's own sub-widget). A domain can
  have its own nested `lib/` too (e.g. a future `editor-view/lib/`) for
  something shared only within that domain's own views, not app-wide.
- `views/components/` — a real, reusable `Gtk.Widget` subclass meant to
  be dropped into more than one view's own template/tree (`SearchInput`,
  today only used by `EditorView.FindBar` but with nothing Find-specific
  about it).

Neither is a dumping ground for anything merely "reused" — scoped to
*where it's actually consumed*: something only ever used within one
domain's own views belongs in that domain's own directory (or its own
nested `lib/`), not promoted up here just because it's shared by more
than one file.

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
