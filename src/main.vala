private static void open_workspace (Gtk.Application app, string root_path) {
    var file_tree_view = new FileTreeView ();
    var tab_bar_view = new TabBarView ();
    var editor_view = new EditorView ();

    FileTreeController file_tree_controller;
    try {
        file_tree_controller = new FileTreeController (file_tree_view, root_path);
    } catch (Error e) {
        error ("failed to open %s: %s", root_path, e.message);
    }

    var editor_controller = new EditorController (tab_bar_view, editor_view);
    new MainController (file_tree_controller, editor_controller);

    var window_view = new MainWindowView (app, file_tree_view.widget, tab_bar_view.widget, editor_view.widget);
    window_view.set_folder_name (Path.get_basename (root_path));
    window_view.present ();
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
        string root_path = Workspace.resolve_root_path (command_line.get_arguments (), Environment.get_current_dir ());
        open_workspace (app, root_path);
        return 0;
    });

    return app.run (args);
}
