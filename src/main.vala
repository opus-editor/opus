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
    public SearchController search_controller;
}

private static GenericArray<Session> sessions;

// The app's own single, process-wide GLib.Settings instance
// (io.github.nowaos.Opus) — window size and the style-variant/theme
// choice are both genuinely app-wide, not per-window, so this is a
// module-level static (like `sessions` above) rather than threaded
// through every window-opening function's own parameters.
private static GLib.Settings settings;

#if DEBUG
// See src/modules/dev-server/index.vala's own doc comment — a D-Bus
// control surface for the terminal, debug builds only.
private static Opus.Dev.DevServer dev_server;
#endif

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
    session.window_view = new MainWindowView (app, session.tab_bar_view.widget, settings);
    session.search_controller = new SearchController (session.window_view.search_bar, session.editor_view, session.editor_controller);
    session.window_view.find_requested.connect (() => session.search_controller.open_find ());

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

    // "Reveal in Sidebar" — a pure View<->View navigation, no
    // Model/Controller involved, so it's bridged here rather than through
    // MainController (that's specifically the FileTree<->Editor glue).
    // A no-op with no folder linked (session.file_tree_view null) — read
    // fresh at signal time, not captured up front, since which window
    // that's true for can change later (Open Folder…/Close Folder).
    session.tab_bar_view.reveal_in_sidebar_requested.connect ((path) => {
        if (session.file_tree_view == null) {
            return;
        }
        session.window_view.reveal_sidebar ();
        session.file_tree_view.reveal_path (path);
    });

    // Double-click on the sidebar's own resize handle — same
    // read-fresh-and-guard pattern as "Reveal in Sidebar" above: nothing
    // to measure with no folder (and so no FileTreeView) linked yet.
    session.window_view.sidebar_reset_width_requested.connect (() => {
        if (session.file_tree_view == null) {
            return;
        }
        session.window_view.set_sidebar_width (session.file_tree_view.get_optimal_width ());
    });

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
    #if DEBUG
    dev_server.add_session (session.editor_controller);
    #endif
    session.window_view.closed.connect (() => {
        if (session.file_tree_controller != null) {
            session.file_tree_controller.close ();
        }
        session.editor_controller.close ();
        sessions.remove (session);
        #if DEBUG
        dev_server.remove_session (session.editor_controller);
        #endif
    });

    return session;
}

/**
 * Maps the "style-variant" setting ("follow"/"light"/"dark") onto
 * Adw.StyleManager's own real color-scheme property — confirmed against
 * GNOME Text Editor's real source (editor-application.c,
 * style_variant_to_color_scheme()), which does the exact same three-way
 * mapping via a settings binding. A plain "changed" handler is used here
 * instead of Vala's own GLib.Settings.bind_with_mapping() — functionally
 * identical, but this avoids that method's C-shaped GValue/GVariant
 * callback signature for what's otherwise a three-line mapping.
 */
private static void apply_color_scheme () {
    string variant = settings.get_string ("style-variant");
    Adw.StyleManager.get_default ().color_scheme = variant == "dark" ? Adw.ColorScheme.FORCE_DARK
        : variant == "light" ? Adw.ColorScheme.FORCE_LIGHT
        : Adw.ColorScheme.DEFAULT;
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
    settings = new GLib.Settings ("io.github.nowaos.Opus");

    #if DEBUG
    dev_server = new Opus.Dev.DevServer ();
    #endif

    // HANDLES_COMMAND_LINE: without it, GApplication's default argv handling
    // treats a bare positional argument as a file to open and aborts with
    // "This application can not open files" unless HANDLES_OPEN is also set.
    // Handling it ourselves keeps the folder argument going through
    // Workspace.resolve, as decided in the sprint spec, instead of GLib's
    // own GFile-based "open" semantics.
    //
    // The app id itself is overridable via OPUS_APP_ID — unset for every
    // real launch (the normal "io.github.nowaos.Opus" applies), set by
    // SystemTestSession to a value unique to that one test run. Without
    // this, a system test's own freshly-spawned process would find
    // "io.github.nowaos.Opus" already owned by any real Opus window the
    // developer happens to have open, and GApplication's own single-
    // instance behavior would silently hand the whole test off to *that*
    // window instead of the isolated one just spawned for it — reported
    // live as tests seeming to run in an already-open window, with no
    // reliable way to tell when they'd actually finished.
    var app_id = Environment.get_variable ("OPUS_APP_ID") ?? "io.github.nowaos.Opus";
    var app = new Adw.Application (app_id, ApplicationFlags.HANDLES_COMMAND_LINE);

    // Not any earlier: Adw.StyleManager.get_default() needs a real
    // Gdk.Display, which doesn't exist until GTK itself has actually
    // initialized — done by the time `startup` fires, not at
    // construction (confirmed the hard way: calling this before
    // app.run() aborts with "gdk_display_manager_get() was called
    // before gtk_init()"). One-way (settings -> style manager): the
    // reverse never happens through this app, since nothing here ever
    // sets color_scheme directly — every actual write goes through the
    // theme selector's own "settings.style-variant" action (see
    // MainWindowView's own build_primary_menu()), which writes the
    // setting, which fires this same "changed" handler right back.
    // Applied once up front for whatever the setting already held from
    // a previous run, then again on every future change — covers every
    // open window at once, since Adw.StyleManager's own color-scheme is
    // already process-wide.
    app.startup.connect (() => {
        apply_color_scheme ();
        settings.changed["style-variant"].connect (() => apply_color_scheme ());

        // GtkText/GtkEntry (and friends) call gtk_widget_error_bell() —
        // an audible system beep — on actions that can't do anything
        // (Backspace on an empty entry, Left at position 0, …). Gated by
        // this one process-wide GtkSettings property, no per-widget way
        // to scope it (checked gtkwidget.c: gtk_widget_error_bell reads
        // "gtk-error-bell" straight off Gtk.Settings.get_default()).
        Gtk.Settings.get_default ().gtk_error_bell = false;
    });

    #if DEBUG
    // Not any earlier: the application's own D-Bus connection/object path
    // (get_dbus_connection()/get_dbus_object_path()) only exist once
    // GApplication has actually registered itself on the bus, which is
    // done by the time `startup` fires — not at construction.
    app.startup.connect (() => {
        var connection = app.get_dbus_connection ();
        var object_path = app.get_dbus_object_path ();
        if (connection != null && object_path != null) {
            dev_server.start (connection, object_path + "/Dev");
        }
    });
    #endif

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
