/**
 * The application itself — a real Adw.Application subclass, not a plain
 * instance wired up procedurally from main(). Owns every window this
 * process has open, the app-wide GLib.Settings instance, and (debug
 * builds only) the Opus.Dev.DevServer, as real instance state on the one
 * object that actually represents the running app.
 *
 * `windows` keeps every open MainWindow alive: a `this`-capturing closure
 * connects through `g_signal_connect_object`, which only guarantees a
 * clean disconnect if the connected object dies — it never keeps that
 * object alive itself (see src/views/CLAUDE.md's own note on this).
 * Without this array, a MainWindow with no other reference to it would be
 * collected the moment open_window()/open_workspace() returns.
 */
public class App : Adw.Application {
  private GLib.Settings settings;
  private GenericArray<MainWindow> windows = new GenericArray<MainWindow> ();

  #if DEBUG
  // See src/lib/CLAUDE.md's own note on why Opus.Dev.DevServer lives
  // outside views/ despite reaching into one — a debug-only D-Bus
  // control surface for the terminal, gated the same way Logger's own
  // debug-only work is (see models/logger.vala).
  private Opus.Dev.DevServer dev_server;
  #endif

  public App (string app_id) {
    Object (application_id: app_id, flags: ApplicationFlags.HANDLES_COMMAND_LINE);
    settings = new GLib.Settings ("io.github.nowaos.Opus");
    #if DEBUG
    dev_server = new Opus.Dev.DevServer ();
    #endif
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
  private void apply_color_scheme () {
    string variant = settings.get_string ("style-variant");
    Adw.StyleManager.get_default ().color_scheme = variant == "dark" ? Adw.ColorScheme.FORCE_DARK
      : variant == "light" ? Adw.ColorScheme.FORCE_LIGHT
      : Adw.ColorScheme.DEFAULT;
  }

  /**
   * Not any earlier than this vfunc: Adw.StyleManager.get_default() needs
   * a real Gdk.Display, and the application's own D-Bus connection/object
   * path, which the DEBUG block below reads, don't exist until GApplication
   * has actually registered itself on the bus — both only guaranteed once
   * the base class's own startup work (chained via base.startup() first)
   * has run.
   */
  public override void startup () {
    base.startup ();

    // One-way (settings -> style manager): the reverse never happens
    // through this app, since nothing here ever sets color_scheme
    // directly — every actual write goes through the theme selector's
    // own "settings.style-variant" action (MainWindow's own
    // build_theme_selector()), which writes the setting, which fires
    // this same "changed" handler right back. Applied once up front for
    // whatever the setting already held from a previous run, then again
    // on every future change — covers every open window at once, since
    // Adw.StyleManager's own color-scheme is already process-wide.
    apply_color_scheme ();
    settings.changed["style-variant"].connect (() => apply_color_scheme ());

    // GtkText/GtkEntry (and friends) call gtk_widget_error_bell() — an
    // audible system beep — on actions that can't do anything (Backspace
    // on an empty entry, Left at position 0, …). Gated by this one
    // process-wide GtkSettings property, no per-widget way to scope it
    // (checked gtkwidget.c: gtk_widget_error_bell reads "gtk-error-bell"
    // straight off Gtk.Settings.get_default()).
    Gtk.Settings.get_default ().gtk_error_bell = false;

    #if DEBUG
    var connection = get_dbus_connection ();
    var object_path = get_dbus_object_path ();
    if (connection != null && object_path != null) {
      dev_server.start (connection, object_path + "/Dev");
    }
    #endif
  }

  /**
   * `opus` (no argument) opens blank — no folder linked, no sidebar, no
   * tab. `opus <file>` opens that file, still with no folder linked.
   * `opus <dir>` links it as the workspace root, sidebar shown, no tab
   * open yet (browse it via the tree).
   *
   * HANDLES_COMMAND_LINE, not the default GApplication argv handling:
   * without it, a bare positional argument is treated as a file to open
   * and aborts with "This application can not open files" unless
   * HANDLES_OPEN is also set. Handling it ourselves keeps the folder
   * argument going through Workspace.resolve instead of GLib's own
   * GFile-based "open" semantics.
   */
  public override int command_line (ApplicationCommandLine command_line) {
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

    string? folder_path;
    string? file_path;
    Workspace.resolve (remaining, out folder_path, out file_path);
    if (folder_path != null) {
      open_workspace (folder_path);
    } else {
      open_window (file_path);
    }
    return 0;
  }

  /**
   * A window with no folder linked — blank (`initial_file == null`) or
   * opened straight to one file. "Copy Relative Path" resolves against
   * the file's own containing directory (or the process's cwd, for a
   * genuinely blank window) until "Open Folder…" gives it a real project
   * root (MainWindow.link_folder(), from its own primary menu/Ctrl+Shift+O).
   */
  public void open_window (string? initial_file) {
    var root_path = initial_file != null ? Path.get_dirname (initial_file) : Environment.get_current_dir ();
    var window = create_window (root_path);

    window.new_window_requested.connect (() => open_window (initial_file));

    if (initial_file != null) {
      window.open_initial_file (initial_file);
    }

    window.present ();
  }

  /** A window that links `root_path` as its workspace root from the start. Reopens the same folder in a second window — a window here is fundamentally "one workspace root," not something that gets re-pointed at another one later on. */
  public void open_workspace (string root_path) {
    var window = create_window (root_path);

    try {
      window.link_folder (root_path);
    } catch (Error e) {
      error ("failed to open %s: %s", root_path, e.message);
    }

    window.new_window_requested.connect (() => open_workspace (root_path));

    window.present ();
  }

  /** Builds a window and registers it with everything app-wide that needs to know about it — the one bit both open_window()/open_workspace() actually share, now that MainWindow itself owns everything else a window needs wired in. */
  private MainWindow create_window (string root_path) {
    var window = new MainWindow (this, settings, root_path);
    windows.add (window);

    #if DEBUG
    dev_server.add_session (window.editor_pane);
    #endif

    window.closed.connect (() => {
      windows.remove (window);
      #if DEBUG
      dev_server.remove_session (window.editor_pane);
      #endif
    });

    return window;
  }
}
