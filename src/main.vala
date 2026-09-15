/**
 * Everything built for one open folder: Views, Controllers and the window.
 * `open_workspace`'s locals would otherwise be unreffed the moment it
 * returns — Vala's `this`-capturing closures connect via
 * `g_signal_connect_object`, which only guarantees a *clean disconnect* if
 * the connected object dies, not that it stays alive. Stashing one Session
 * on the Application (its natural lifetime owner) via `set_data` keeps
 * every Controller/View alive for as long as the app runs.
 */
private class Session : Object {
    public FileTreeView file_tree_view;
    public TabBarView tab_bar_view;
    public EditorView editor_view;
    public FileTreeController file_tree_controller;
    public EditorController editor_controller;
    public MainController main_controller;
    public MainWindowView window_view;
}

private static void open_workspace (Gtk.Application app, string root_path) {
    // A couple of app-bundled symbolic icons (e.g. git-symbolic) that don't
    // exist in the system icon theme; registered under our own gresource
    // prefix so `icon-name: "git-symbolic"` resolves like any other icon.
    // Must be scalable/<context>/, not symbolic/<context>/ — the latter is
    // just how Adwaita's own index.theme happens to name one of its
    // directories, not a convention add_resource_path() understands on its
    // own (it has no index.theme to read); without a match here it silently
    // falls through to the active theme's "image-missing" icon instead of
    // erroring, which is what actually happens if this path is wrong.
    Gtk.IconTheme.get_for_display (Gdk.Display.get_default ()).add_resource_path ("/io/github/alxmagro/Codi/icons");

    var session = new Session ();
    session.file_tree_view = new FileTreeView ();
    session.tab_bar_view = new TabBarView ();
    session.editor_view = new EditorView ();

    try {
        session.file_tree_controller = new FileTreeController (session.file_tree_view, root_path);
    } catch (Error e) {
        error ("failed to open %s: %s", root_path, e.message);
    }

    session.editor_controller = new EditorController (session.tab_bar_view, session.editor_view);
    session.main_controller = new MainController (session.file_tree_controller, session.editor_controller);

    session.window_view = new MainWindowView (
        app, session.file_tree_view.widget, session.tab_bar_view.widget, session.editor_view.widget
    );
    session.window_view.set_folder_name (Path.get_basename (root_path));
    session.window_view.present ();

    app.set_data<Session> ("session", session);
}

int main (string[] args) {
    // HANDLES_COMMAND_LINE: without it, GApplication's default argv handling
    // treats a bare positional argument as a file to open and aborts with
    // "This application can not open files" unless HANDLES_OPEN is also set.
    // Handling it ourselves keeps the folder argument going through
    // Workspace.resolve_root_path, as decided in the sprint spec, instead of
    // GLib's own GFile-based "open" semantics.
    var app = new Adw.Application ("io.github.alxmagro.Codi", ApplicationFlags.HANDLES_COMMAND_LINE);

    app.command_line.connect ((command_line) => {
        string[] argv = command_line.get_arguments ();
        string[] remaining = {};
        bool verbose = false;
        foreach (var arg in argv) {
            if (arg == "-v" || arg == "--verbose") {
                verbose = true;
            } else {
                remaining += arg;
            }
        }
        Logger.configure (verbose);

        string root_path = Workspace.resolve_root_path (remaining, Environment.get_current_dir ());
        open_workspace (app, root_path);
        return 0;
    });

    return app.run (args);
}
