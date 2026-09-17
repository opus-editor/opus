/**
 * Everything built for one open window: Views, Controllers and the window
 * itself. `build_session`'s locals would otherwise be unreffed the moment
 * it returns — Vala's `this`-capturing closures connect via
 * `g_signal_connect_object`, which only guarantees a *clean disconnect* if
 * the connected object dies, not that it stays alive. Kept alive by being
 * appended to the module-level `sessions` array below — one entry per open
 * window (New Window/Open File/Open Folder… can have more than one at a
 * time) — removed once that window actually closes.
 *
 * `file_tree_view`/`file_tree_controller`/`main_controller` are null until
 * a folder is actually linked — a window opened blank (`opus`) or for a
 * single file (`opus <file>`) has no sidebar at all until "Open Folder…"
 * links one (see MainWindowView.link_folder).
 */
private class Session : Object {
    public FileTreeView? file_tree_view;
    public TabBarView tab_bar_view;
    public EditorView editor_view;
    public FileTreeController? file_tree_controller;
    public EditorController editor_controller;
    public MainController? main_controller;
    public MainWindowView window_view;
}

private static GenericArray<Session> sessions;

/**
 * Everything a window needs regardless of whether a folder ends up linked
 * — open_window() (blank, or a single file, neither links one) and
 * open_workspace() (links one from the start) both go through this, then
 * each adds whatever's specific to its own case.
 */
private static Session build_session (Gtk.Application app, string editor_root_path) {
    // A couple of app-bundled symbolic icons (e.g. git-symbolic) that don't
    // exist in the system icon theme; registered under our own gresource
    // prefix so `icon-name: "git-symbolic"` resolves like any other icon.
    // Must be scalable/<context>/, not symbolic/<context>/ — the latter is
    // just how Adwaita's own index.theme happens to name one of its
    // directories, not a convention add_resource_path() understands on its
    // own (it has no index.theme to read); without a match here it silently
    // falls through to the active theme's "image-missing" icon instead of
    // erroring, which is what actually happens if this path is wrong.
    Gtk.IconTheme.get_for_display (Gdk.Display.get_default ()).add_resource_path ("/io/github/nowaos/Opus/icons");

    var session = new Session ();
    session.tab_bar_view = new TabBarView ();
    session.editor_view = new EditorView ();
    session.editor_controller = new EditorController (session.tab_bar_view, session.editor_view, editor_root_path);
    session.window_view = new MainWindowView (app, session.tab_bar_view.widget);

    // The editor's widget only belongs in the content pane while at least
    // one tab is open — otherwise an empty-state placeholder takes its
    // place (see MainWindowView.show_empty_state()).
    session.editor_controller.has_open_tabs_changed.connect ((has_tabs) => {
        if (has_tabs) {
            session.window_view.show_content (session.editor_view.widget);
        } else {
            session.window_view.show_empty_state ();
        }
    });

    // The tab bar's own widget can't host a dragged tab's floating ghost
    // copy itself — it'd be confined to the tab bar's own bounds, unable
    // to follow the pointer once it leaves that narrow strip — so it asks
    // the window (which spans the whole screen area the ghost needs) to
    // show it instead.
    session.tab_bar_view.drag_ghost_shown.connect (
        (ghost, x, y, width, height) => session.window_view.show_floating (ghost, x, y, width, height)
    );
    session.tab_bar_view.drag_ghost_moved.connect ((x, y) => session.window_view.move_floating (x, y));
    session.tab_bar_view.drag_ghost_hidden.connect (() => session.window_view.hide_floating ());

    // The primary menu's own Close/Save/Save as… items (and the tab
    // context menu's "Close") name these same shortcuts — wired here, not
    // through MainController, since MainController is specifically the
    // FileTree<->Editor glue and both these are already Session fields.
    session.window_view.close_active_tab_requested.connect (() => session.editor_controller.close_active ());
    session.window_view.save_requested.connect (() => session.editor_controller.save_active.begin ());
    session.window_view.save_as_requested.connect (() => session.editor_controller.save_as_active.begin ());
    session.editor_controller.active_state_changed.connect (
        (path, dirty) => session.window_view.set_active_state (path != null, dirty)
    );

    // New File opens a brand-new "Untitled-N" tab with nothing on disk
    // yet — saving it (Save or Save as…, either one) goes through the
    // Save As flow, since there's nowhere existing to plain-save to.
    session.window_view.new_file_requested.connect (() => session.editor_controller.new_untitled ());
    // Open File… opens the chosen file as a tab right in this same
    // window — it never links a folder on its own. Open Folder… links
    // one into this same window (or replaces whichever one it already
    // had). Neither one opens a new window — New Window is the one
    // action that does, reopening this exact window's own contents.
    session.window_view.open_file_requested.connect (() => on_open_file_requested.begin (session));
    session.window_view.open_folder_requested.connect (() => on_open_folder_requested.begin (session));
    session.window_view.close_folder_requested.connect (() => unlink_folder (session));

    sessions.add (session);
    session.window_view.closed.connect (() => {
        if (session.file_tree_controller != null) {
            session.file_tree_controller.close ();
        }
        session.editor_controller.close ();
        sessions.remove (session);
    });

    return session;
}

/**
 * A window with no folder linked — blank (`opus`, `initial_file == null`)
 * or opened straight to one file (`opus <file>`). "Copy Relative Path"
 * resolves against the file's own containing directory (or the process's
 * cwd, for a genuinely blank window) until "Open Folder…" gives it a real
 * project root.
 */
private static void open_window (Gtk.Application app, string? initial_file) {
    var editor_root_path = initial_file != null ? Path.get_dirname (initial_file) : Environment.get_current_dir ();
    var session = build_session (app, editor_root_path);

    session.window_view.new_window_requested.connect (() => open_window (app, initial_file));

    if (initial_file != null) {
        try {
            session.editor_controller.open (initial_file, true);
        } catch (Error e) {
            session.window_view.show_error (_("Couldn’t open “%s”: %s").printf (initial_file, e.message));
        }
    }

    session.window_view.present ();
}

private static void open_workspace (Gtk.Application app, string root_path) {
    var file_tree_view = new FileTreeView ();
    FileTreeController file_tree_controller;
    try {
        file_tree_controller = new FileTreeController (file_tree_view, root_path);
    } catch (Error e) {
        error ("failed to open %s: %s", root_path, e.message);
    }

    var session = build_session (app, root_path);
    link_folder (session, file_tree_view, file_tree_controller);

    // Reopens the same folder in a second window — a window here is
    // fundamentally "one workspace root", not something Views/Controllers
    // get re-pointed at.
    session.window_view.new_window_requested.connect (() => open_workspace (app, root_path));

    session.window_view.present ();
}

/** Replaces whichever FileTreeController this session already had (if any) — closing it first (see its own close() doc comment) so its watches/timers don't keep running after nothing references it anymore. */
private static void link_folder (Session session, FileTreeView file_tree_view, FileTreeController file_tree_controller) {
    if (session.file_tree_controller != null) {
        session.file_tree_controller.close ();
    }

    session.file_tree_view = file_tree_view;
    session.file_tree_controller = file_tree_controller;
    session.main_controller = new MainController (file_tree_controller, session.editor_controller);
    session.window_view.link_folder (file_tree_view.widget);
}

/**
 * "Close Folder" — the opposite of link_folder(): drops this same
 * window's FileTreeView/FileTreeController/MainController entirely (their
 * signal connections disconnect on their own once nothing references them
 * — see Session's own doc comment on why that's safe) and hides the
 * sidebar. Open tabs stay exactly as they are; "Copy Relative Path" falls
 * back to the process's cwd, same as a window that never had a folder
 * linked in the first place (see open_window()'s own comment).
 */
private static void unlink_folder (Session session) {
    if (session.file_tree_controller != null) {
        session.file_tree_controller.close ();
    }

    session.file_tree_view = null;
    session.file_tree_controller = null;
    session.main_controller = null;
    session.editor_controller.set_root_path (Environment.get_current_dir ());
    session.window_view.unlink_folder ();
}

private static async void on_open_file_requested (Session session) {
    var path = yield session.window_view.choose_file ();
    if (path == null) {
        return;
    }

    try {
        session.editor_controller.open (path, true);
    } catch (Error e) {
        session.window_view.show_error (_("Couldn’t open “%s”: %s").printf (path, e.message));
    }
}

/**
 * Links `path` into this same window — the open tab bar/editor stay
 * exactly as they are (switching folders doesn't imply discarding
 * whatever's already open), only what FileTreeView shows and what
 * EditorController resolves relative paths against. Replaces whichever
 * folder was already linked, if any.
 */
private static async void on_open_folder_requested (Session session) {
    var path = yield session.window_view.choose_folder ();
    if (path == null) {
        return;
    }

    var file_tree_view = new FileTreeView ();
    FileTreeController file_tree_controller;
    try {
        file_tree_controller = new FileTreeController (file_tree_view, path);
    } catch (Error e) {
        session.window_view.show_error (_("Couldn’t open “%s”: %s").printf (path, e.message));
        return;
    }

    session.editor_controller.set_root_path (path);
    link_folder (session, file_tree_view, file_tree_controller);
}

int main (string[] args) {
    sessions = new GenericArray<Session> ();

    // HANDLES_COMMAND_LINE: without it, GApplication's default argv handling
    // treats a bare positional argument as a file to open and aborts with
    // "This application can not open files" unless HANDLES_OPEN is also set.
    // Handling it ourselves keeps the folder argument going through
    // Workspace.resolve, as decided in the sprint spec, instead of GLib's
    // own GFile-based "open" semantics.
    var app = new Adw.Application ("io.github.nowaos.Opus", ApplicationFlags.HANDLES_COMMAND_LINE);

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

        // `opus` (no argument) opens blank — no folder linked, no sidebar,
        // no tab. `opus <file>` opens that file, still with no folder
        // linked. `opus <dir>` links it as the workspace root, sidebar
        // shown, no tab open yet (browse it via the tree).
        string? folder_path;
        string? file_path;
        Workspace.resolve (remaining, out folder_path, out file_path);
        if (folder_path != null) {
            open_workspace (app, folder_path);
        } else {
            open_window (app, file_path);
        }
        return 0;
    });

    return app.run (args);
}
