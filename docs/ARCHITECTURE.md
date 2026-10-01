# Architecture

## Models

- Plain Vala objects — state and pure logic only, never `Gtk`/`Adw`, so they stay testable and UI-independent.

## Libs

- Generic infrastructure independent of Opus's own domain concepts — the one exception allowed to import `Gtk`/`Adw`, when its own task genuinely needs it.

## Plugins

- Model-grade code discovered via libpeas — talks to the host only through `WorkspaceContext` and its own extension-point interfaces, never by importing a View.

## Views

- The only layer allowed to import `Gtk`/`Adw` (besides `lib/`'s exception) — a facade that owns real widgets internally and exposes only plain methods + signals, never a `Gtk.Widget` subclass passed around
- Similar to a Vue/Svelte component (own template, props/events as the only surface).

### Composition

- A component owns its own appearance and lifecycle — it calls a Model directly when it needs one, no intermediary layer between the two.
- A component that needs a sibling it doesn't own talks through a signal, handled by whichever component composes both — it never reaches into a sibling directly.
- A component composing several subcomponents owns their coordination itself: wiring their signals, deciding what each one does next.

### Componentes and subcomponents

- A component is a folder + `index.vala`.
- A subcomponent belongs to exactly one component and is never referenced outside it — a flat `_[name].vala` file when it has no sub-parts of its own, or its own nested folder (a component itself, one level deeper) once it does.
- When a component owns other components as subcomponents, the parent component's class takes a `Widget` suffix to avoid colliding with the shared namespace that embraces their subcomponents.
- A flat subcomponent's (`_[name].vala`) class name is prefixed with its owning component's name (`ExplorerPaneTree`, not bare `Tree`).

### Libs vs Components

- `views/lib/` holds shared helpers for views that need `Gtk`/`Adw` but aren't a widget themselves (`SystemColor`, `FileDrag`).
- `views/components/` holds a real, reusable `Gtk.Widget` subclass (`ContextMenu`, `SearchInput`).
- Neither is for something used by only one domain, which belongs in that domain's own directory instead.

### Namespacing related components

- A domain with several sibling views shares a plain namespace naming the domain itself.
- Code outside that namespace always spells it out in full.


