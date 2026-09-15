# Opus

Native GTK4 + Libadwaita source code editor, written in Vala. See
[README.md](README.md) for the pitch.

## Building

```shell
meson setup builddir
ninja -C builddir
./builddir/src/opus
```

Rebuild after adding/removing a `.vala` file: `meson setup --reconfigure
builddir` (Meson doesn't glob sources — every file must be listed in the
nearest `meson.build`).

Or via the `justfile` (`just --list` for the full set): `just build`,
`just test`, `just run [folder]`, `just clean`.

Toolchain this was written against: Vala 0.56, Meson 1.7, GTK4 4.18,
Libadwaita 1.7.

## Logging

`Logger.warn`/`Logger.info` (`src/models/logger.vala`) print to stderr, gated
by a runtime `-v`/`--verbose` flag (`just run -v`). In a `debug` buildtype
(the default), Meson passes `--define=DEBUG` to valac and these calls do
real work; in a `release` build the whole namespace body compiles to empty
functions — calls stay in the source, but the logging is gone from the
binary, not just silenced. Leave `Logger.warn (...)` calls in place rather
than deleting them after debugging.

Use sparingly: only at real points of interest (a signal crossing a
Controller/View boundary, a decision branch worth tracing), never scattered
across every function — it's a diagnostic tool, not routine narration.

## Testing

```shell
meson test -C builddir
```

One test binary per Model or Controller. Views are mocked through their
interface (see below) — no real `Gtk`/`Adw` widget is ever instantiated in a
test.

## Structure

```
src/
  main.vala           entry point: builds Models, Views, Controllers and wires them together
  models/             plain Vala objects — no `Gtk`/`Adw` import anywhere in this directory
  controllers/         mediate Model <-> View; hold no widgets, only `I*View` references
  views/
    interfaces/        one `I*View` per screen area — the only thing a Controller may depend on
    gtk/                concrete Adw/Gtk-backed implementations of those interfaces
data/                 .desktop file, GResource XML, icons
```

## Architecture: MVC, with Views as facades

Standard MVC, except a **View is not a window or widget** — it's a facade
that owns one (or several) internally and exposes a narrow interface. A
Controller never touches `Gtk`/`Adw` directly; it only calls interface
methods and connects to interface signals. This is what makes the pattern
line up with SOLID:

- **Single Responsibility** — a Model holds state and nothing else; a View
  wires widgets and translates user interaction into signals; a Controller
  reacts to those signals and updates Models. No class does two of these.
- **Open/Closed** — swapping the editor's underlying widget (e.g. from
  `GtkSourceView` to a custom `Gtk.TextView` driven by tree-sitter) means
  writing a new class in `views/gtk/` that implements the existing
  interface. Nothing in `controllers/` or `models/` changes.
- **Liskov Substitution** — any concrete `I*View` implementation must be
  fully interchangeable with another, including a test fake that implements
  the interface with no real widget behind it.
- **Interface Segregation** — one interface per screen area
  (`IEditorView`, `IFileTreeView`, `ITabBarView`, `ITitleBarView`), not one
  `IMainWindowView` covering everything. A Controller depends only on the
  methods it actually calls.
- **Dependency Inversion** — `controllers/` and `models/` depend only on the
  interfaces in `views/interfaces/`. `views/gtk/` is the *only* directory
  allowed to import `Gtk` or `Adw`.

### Shape

```vala
// views/interfaces/editor-view.vala
public interface IEditorView : Object {
    public signal void text_changed (string new_text);

    public abstract void set_text (string text);
    public abstract string get_text ();
    public abstract void set_language (string language_id);
}

// views/gtk/editor-view.vala
public class EditorView : Object, IEditorView {
    private Gtk.TextView text_view;
    private Gtk.ScrolledWindow scrolled_window;

    public Gtk.Widget widget { get { return scrolled_window; } }

    public EditorView () {
        text_view = new Gtk.TextView ();
        scrolled_window = new Gtk.ScrolledWindow ();
        scrolled_window.set_child (text_view);
        text_view.buffer.changed.connect (() => text_changed (get_text ()));
    }

    public void set_text (string text) { text_view.buffer.text = text; }
    public string get_text () { return text_view.buffer.text; }
    public void set_language (string language_id) { /* ... */ }
}

// controllers/editor-controller.vala
public class EditorController : Object {
    private IEditorView view;
    private DocumentModel document;

    public EditorController (IEditorView view, DocumentModel document) {
        this.view = view;
        this.document = document;
        view.set_text (document.content);
        view.text_changed.connect ((text) => document.content = text);
    }
}
```

`EditorController` never sees a `Gtk.TextView`. A test can hand it a fake
`IEditorView` and assert on `DocumentModel.content` without ever touching
GTK. The same shape applies to windows: an `IMainWindowView` facade owns the
`Adw.ApplicationWindow` and exposes methods like `show_error (string)` or a
`close_requested` signal — the `MainController` reacts to that signal, it
never calls `.close ()` on a window it doesn't hold a reference to.
