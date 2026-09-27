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
