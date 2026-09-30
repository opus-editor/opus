# Decisions

Short technical notes for things confirmed by testing, not assumption —
kept here instead of bloating a `CLAUDE.md` with the proof.

## A class named the same as itself, inside its own namespace, resolves to itself

Confirmed with a standalone `valac` compile test: `namespace Foo { class
Bar { Bar() { new Bar("x"); } } }` alongside a global `class Bar` — the
`new Bar("x")` inside `Foo.Bar`'s own constructor resolves to the
*enclosing* class, not the global one (a wrong-arg-count compile error).
This is why a sub-component's role name can't just be the same word as an
existing Model — `ExplorerPaneTree`, not the bare `Tree`, next to the
`FileTree` Model.

## A namespace and a class can share a name, but we still avoid it

Confirmed with a compile test: `namespace Foo { class Foo { Foo x() { return new Foo(); } } }`, plus a sibling class in the same namespace calling `new Foo()` unqualified — all resolve correctly, no ambiguity (Vala treats this the same way Rust treats `mod foo { struct Foo }`). So a sub-view nested under its owner (`editor-pane/tab-bar/`) *could* legally live in `namespace EditorPane` right next to `class EditorPane`.

We still don't do this — reads as if the class and the namespace were the same thing. Instead, the namespace gets a trailing-underscore suffix: `namespace EditorPane_`, distinct identifier from `class EditorPane`, no clash, no confusion. A *leading* underscore was considered and rejected: it already means "private, colocated single file" everywhere else in this codebase (`_row.vala`, `_tree.vala`) — reusing it for "this namespace spans a whole directory" would overload a symbol that already has a narrower, established meaning.

## `g_signal_connect_object` disconnects cleanly but doesn't keep anything alive

A `this`-capturing closure connected via `g_signal_connect_object`
guarantees a clean disconnect once the connected object dies — nothing
dangles. It does **not** keep that object alive itself. Anything with its
own signal handlers still needs an explicit owner for as long as it
should react to events (`App.windows` for every open `MainWindow`,
`EditorPane` holding `TabBar`/`TextEditor`, and so on down the tree) —
without one, it's collected the moment nothing else references it, even
while its own signal connections are still "live."

## An interface with a prerequisite must be listed after it on the implementing class

`FileDecoration.IProvider : Object, IWorkspaceExtension` names
`IWorkspaceExtension` as its own prerequisite. A class implementing
`IProvider` must list `IWorkspaceExtension` *before* it in its own base
list — `Object, IWorkspaceExtension, FileDecoration.IProvider`, not the
reverse. Getting the order backwards compiles cleanly but aborts at
runtime: `GLib-GObject-FATAL-CRITICAL: cannot add interface type
'FileDecorationIProvider' to type 'X' which does not conform to
prerequisite 'IWorkspaceExtension'` — confirmed live while building the
git-status plugin's own tests (`tests/models/file-decoration-registry-test.vala`'s
`FakeProvider`). valac itself never warns about the ordering; only `g_type_add_interface_static`'s
own runtime check catches it, at the first construction of an affected class.

## A `{ get; construct; }` *interface* property can crash a class overriding it — depending on unrelated code elsewhere in the same compile

Real, reproducible valac 0.56 bug, not something fixable by writing the
override "more correctly": a class overriding an interface's `{ get;
construct; }` property can end up with its own generated
`set_property()`/`get_property()` glue calling through to the
*interface's* own vfunc (`iworkspace_extension_set_context(...)`) instead
of using its own concrete backing field — and that vfunc is never
actually declared for a construct-only property (GObject convention: no
public setter for construct-only), so the generated C fails to compile
with an implicit-function-declaration error.

The genuinely unsettling part: whether this triggers depends on the *rest
of the same compilation unit* — a small, isolated repro with the exact
same interface/class shapes compiled fine every time; the real
`Opus.Plugins.GitStatus.Provider` class, compiled alongside the rest of
`opus_model_sources`/`opus_gtk_view_sources` as part of the full `opus`
binary, hit it every time, while the *same* `provider.vala` compiled
alongside only `opus_model_sources` (the `git-status-provider-test`
binary) did not. Never isolated the exact trigger condition — not worth
the time once a clean workaround existed.

**Workaround, applied for real (`IWorkspaceExtension.context`,
`FileDecoration.State`'s consumers, and any future interface property
libpeas needs to see):** declare the property as plain `{ get; set; }`
on the interface (not `{ get; construct; }`), with implementors matching
exactly (`{ get; set; }`, not `{ get; construct set; }` — Vala requires
an override's accessors to match the interface's exactly, confirmed:
`construct set` alone produces "incompatible set accessor"). This still
works for `Peas.ExtensionSet.with_properties`/`Object (context: ...)` at
construction time — GObject construction can set any writable property
passed to `g_object_new`, not only ones flagged `CONSTRUCT`; nothing here
ever reads a plugin's own `.context` before construction has fully
finished anyway.

Removing the property from the interface entirely (the first workaround
tried) is *not* viable despite compiling and running cleanly in
isolation: `Peas.ExtensionSet.with_properties` validates property names
against the *interface* type (`extension_type`) before it ever
instantiates a concrete class, and fails silently-ish at runtime instead
(`libpeas-WARNING: peas_utils_properties_array_to_parameter_list: type
'...IProvider' has no property named 'context'`, cascading into
`GLib-GObject-CRITICAL: invalid (NULL) pointer instance` wherever the
(now-empty) extension set gets used) if the property isn't declared
there. The property has to stay on the interface; it's the *accessor
combination* that has to change.

## GTK4's own CSS engine: no `light-dark()`, no logical margin properties

Confirmed live (`Gtk-WARNING: Theme parser error`), not assumed from the
web CSS spec: GTK 4.18's CSS parser rejects `light-dark(#a, #b)` outright
("Expected a valid color") and `margin-inline-end`/other CSS Logical
Properties equally ("No property named ..."). GTK4 CSS's own box model is
physical-only (`margin-top`/`-right`/`-bottom`/`-left`, no `-start`/`-end`
logical pair) with no browser-style light/dark color function baked into
the stylesheet language itself — a color that needs to differ by theme
either comes from a real libadwaita/GTK named token (`--accent-color` and
friends, which already do the right thing per theme) or gets picked in
Vala code off `Adw.StyleManager.get_default ().dark` (`FindResults`'s own
`apply_style_scheme()` is the established pattern for that), never a bare
CSS function.

## A constructor can't usefully fire its own signal — nobody's connected yet

Hit this twice in the same feature, at two different layers, and it cost
real debugging time both times because everything *compiled* fine and
*looked* correct: `Peas.ExtensionSet.with_properties()` itself
instantiates (and internally fires its own `extension_added` for) every
plugin already loaded at that exact moment — before
`extension_set.extension_added.connect (...)`, called right after
`with_properties()` returns, can ever see it. `Opus.Plugins.
WorkspaceExtensions`'s own constructor originally repeated the identical
mistake one layer up: it looped over already-active extensions and fired
its *own* `added()` signal for each, right there in the constructor —
before `MainWindow.link_folder()`, the actual caller, had gotten past `new
WorkspaceExtensions (...)` to call `.added.connect (...)` at all.

Nothing errored. Nothing warned. The whole pipeline (git subprocess →
`GitStatus` → `Provider.current_decorations()` → `FileDecoration.Registry`)
computed correct data end to end, confirmed by dedicated tests at every
layer — the dots just never appeared, because the one signal carrying
that data from `WorkspaceExtensions` up to `MainWindow`/`ExplorerPane` had
already fired into an empty room by the time anyone was listening.

**The pattern to avoid:** a constructor must never assume its own signal
has a listener yet — anything the constructor needs to announce that a
caller must react to has to be deferred to a method the caller invokes
*after* connecting, not fired inline during construction. Fixed here with
`WorkspaceExtensions.notify_existing()`, called by `MainWindow.
link_folder()` immediately after wiring `added`/`removed` — `activate()`
still happens in the constructor (nothing depends on a listener for that),
only the `added()` *announcement* itself was moved out.

## `GenericArray<T>` can't convert back to `T[]` when `T` is a plain Object

`GenericArray<Hunk>`'s own `.data`/`.steal ()` both compile, but the
generated C mismatches pointer types (`assignment to 'GitDiffHunk **'
from incompatible pointer type 'void **'`) — `Hunk` isn't a simple/compact
type, so valac's array-conversion codegen for `GenericArray<T>` doesn't
produce a correctly-typed cast. Fix: don't route through
`GenericArray<T>` for a T like this at all — build the result with a
plain `GLib.List<T>` (`.append()`, iterate, copy into a pre-sized `new
T[list.length ()]`) or, if the final count is already known, a directly
pre-sized `T[]` filled by index — both idioms this codebase already uses
elsewhere (`GitStatus.paths ()`, `CursorCollection`'s own `new
Cursor[cursors.length]` throughout).

## A `T[]` property can't hold a custom `Object` array either

`public Hunk[] hunks { get { ... } }` on a `GLib.Object`-derived class
warns `Type 'GitDiff.Hunk[]' can not be used for a GLib.Object property` —
GObject's property system has no `GParamSpec` for "array of a custom
Object subtype" (unlike `string[]`, which maps to `G_TYPE_STRV`), and this
applies even to a property backed by a computed getter body, not just an
auto-implemented one. Fix: expose it as a plain method instead
(`public Hunk[] hunks ()`), the same way `GitStatus.paths ()` is a method,
not a property, for the identical reason.

## A signal connected to a bound method can auto-disconnect out from under you

`provider.bases_changed.connect (on_bases_changed)`, where
`on_bases_changed` is one of `GitDiff.DocumentTracker`'s own instance
methods, uses `g_signal_connect_object`-style semantics under the hood
(same fact `src/views/CLAUDE.md` already documents the other direction:
"it never keeps that object alive itself") — meaning GObject
automatically disconnects the connection the moment `DocumentTracker`
itself is destroyed, with **no notification back** to whatever field is
still caching that handler id. If a later code path (a destructor, or a
different lifecycle event) then calls `provider.disconnect
(cached_handler_id)` using that now-stale id, the process aborts outright
(`GLib-GObject-FATAL-CRITICAL: ... has no handler with id ...`) —
confirmed live, reproducibly, while writing `DocumentTracker`'s own
`git-diff-document-tracker-test.vala`. Two real fixes were needed
together, not either alone:

1. Never reconnect a signal you're already connected to — re-subscribing
   to the *same* provider (e.g. from that provider's own emission,
   asking to "refresh") is pure churn; guard with `if (provider !=
   current_provider)` before disconnecting/reconnecting at all.
2. Before any explicit disconnect, check
   `g_signal_handler_is_connected (instance, handler_id)` first — not in
   the GLib vapi, so declared as a small `extern` binding
   (`[CCode (cname = "g_signal_handler_is_connected")]`). This is the
   actual load-bearing fix: it's the only way to tell whether GObject's
   own automatic cleanup already beat you to it.
