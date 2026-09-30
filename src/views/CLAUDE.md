# src/views/

The only directory allowed to import `Gtk`/`Adw` (`src/lib/` is the
exception — see its own doc comment). A View is a facade: owns
real widgets internally, exposes plain methods + signals — never a
`Gtk.Widget` subclass passed around directly.

No Controller layer: a View that needs a Model calls it directly; a View
that needs a sibling View it doesn't own emits a signal for whichever
View composes both. A View composing several real sub-components
absorbs what a Controller used to do from outside it (`EditorPane`
absorbed `EditorController`, `ExplorerPane` absorbed
`FileTreeController`, `MainWindow` absorbed `MainController`/
`SearchController`).

## Layout

Organized by domain first, not by widget kind:

```
views/
  lib/              app-wide supporting code, not a widget itself
    file-drag/
  components/       app-wide reusable Gtk.Widget subclasses
    code-editor/    a multi-file component gets its own directory, same
                    index.vala + _sub.vala convention as a view
  main/             window chrome: header, global menu, sidebar toggle
    main-window/
  editor-view/      explorer-pane/ editor-pane/ find-bar/
  git-view/         future, not created yet
```

Each view gets its own `<domain>/<name>/`: `index.vala` (the facade
class) and `index.blp` (its Blueprint template, if any — some views are
built entirely in code and have none). Load a template via
`Gtk.Builder.from_resource (...)` in the constructor, never
`[GtkTemplate]` — some Gtk types are `final` and can't be subclassed.

- A sub-widget used only by its owning view sits alongside it with a
  leading underscore instead of its own directory: `explorer-pane/
  _tree-row.{vala,blp}`.
- A sub-component substantial enough for its own template/further
  sub-parts gets its own nested directory instead: `editor-pane/tab-bar/`
  — see Naming below for what that does to its namespace.

## Naming

- A view's class name never repeats "View" or its own directory name —
  the path under `views/<domain>/<name>/` already says that.
- A domain with several sibling views gets a real `namespace` instead:
  `EditorView.ExplorerPane`/`EditorPane`/`FindBar`.
- A sub-widget/sub-component's suffix names its *owning view*: `ExplorerPaneTree`, not the bare `Tree` (collides with the `FileTree` Model).
- A view nested under another one keeps its own name unchanged (`TabBar`,
  not `EditorPaneTabBar`) but moves into a namespace named after its
  owner, suffixed `_`: `EditorView.EditorPane_.TabBar` — avoids a
  namespace sharing a name with its owner's own class (see
  `docs/decisions.md`).
- Code outside the namespace always spells it out in full
  (`EditorView.ExplorerPane`) — no `using` to shorten a namespace, ever.
- `views/lib/`, `views/components/`, and `main/` stay unnamespaced —
  nothing to disambiguate against yet.

## `lib/` vs `components/`

Both hold code shared *across* domains — split on whether it's a widget:
`views/lib/` needs `Gtk`/`Adw` but isn't one itself (`SystemColor`, the
`FileDrag` trio); `views/components/` is a real, reusable `Gtk.Widget`
subclass (`ContextMenu`, `SearchInput`). Neither is a dumping ground for
anything merely "reused" — something used within only one domain
belongs in that domain's own directory instead.

## Signal connections don't keep an object alive

`g_signal_connect_object` only guarantees a clean disconnect once the
connected object dies — it never keeps that object alive itself.
Anything with its own signal handlers needs an explicit owner: see
`App.windows` (`src/App.vala`) for every open `MainWindow`.
