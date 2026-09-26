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

## `g_signal_connect_object` disconnects cleanly but doesn't keep anything alive

A `this`-capturing closure connected via `g_signal_connect_object`
guarantees a clean disconnect once the connected object dies — nothing
dangles. It does **not** keep that object alive itself. Anything with its
own signal handlers still needs an explicit owner for as long as it
should react to events (`App.windows` for every open `MainWindow`,
`EditorPane` holding `TabBar`/`TextEditor`, and so on down the tree) —
without one, it's collected the moment nothing else references it, even
while its own signal connections are still "live."
