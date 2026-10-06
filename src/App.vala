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
 * object alive itself (see src/views/AGENTS.md's own note on this).
 * Without this array, a MainWindow with no other reference to it would be
 * collected the moment open_window()/open_workspace() returns.
 */
public class App : Adw.Application {
  private GLib.Settings settings;
  private GenericArray<MainWindow> windows = new GenericArray<MainWindow> ();
  private Opus.Plugins.Engine plugins_engine;
  private UserSettings user_settings;
  private LastFolder last_folder;

  #if DEBUG
  // See src/lib/AGENTS.md's own note on why Opus.Dev.DevServer lives
  // outside views/ despite reaching into one — a debug-only D-Bus
  // control surface for the terminal, gated the same way Logger's own
  // debug-only work is (see lib/logger.vala).
  private Opus.Dev.DevServer dev_server;
  #endif

  public App (string app_id) {
    Object (application_id: app_id, flags: ApplicationFlags.HANDLES_COMMAND_LINE);
    settings = new GLib.Settings ("io.github.opus_editor.Opus");
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

    // The shell on Wayland finds the app icon through the app id's own
    // .desktop file by itself; under X11/XWayland a window carries its
    // icon explicitly, and this is the one place to name it for every
    // window at once.
    Gtk.Window.set_default_icon_name (application_id);

    // Before any window (and therefore any MainWindow-owned
    // Opus.Plugins.WorkspaceExtensions) can be built — every built-in
    // plugin is discovered/loaded exactly once, process-wide.
    plugins_engine = new Opus.Plugins.Engine ();

    // Same deadline: every CodeEditor asks it for its file's language.
    // No style keys yet — EditorTheme, below, supplies its theme's.
    Syntax.Languages.instance = new Syntax.Languages (language_directories (), grammar_directories (), {}, grammar_builder ());
    Syntax.Languages.instance.watch (user_languages_directory ());

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

    var saved_pathname = settings.get_string ("last-folder");
    user_settings = new UserSettings (Environment.get_user_config_dir ());

    // The bundled themes, then the user's own, which win a shared name.
    EditorTheme.instance = new EditorTheme (
      user_settings,
      {
        Environment.get_variable ("OPUS_THEMES_DIR") ?? BuildInfo.THEMES_DIR,
        Path.build_filename (Environment.get_user_data_dir (), "opus", "themes"),
      }
    );
    last_folder = new LastFolder (user_settings.restore_folder, saved_pathname == "" ? null : saved_pathname);
    save_last_folder ();
    last_folder.notify["recorded-pathname"].connect (save_last_folder);

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

  private void save_last_folder () {
    settings.set_string ("last-folder", last_folder.recorded_pathname ?? "");
  }

  /**
   * `opus` (no argument) opens blank — no folder linked, no sidebar, no
   * tab — or, with `window.restore_folder` on, on the folder LastFolder
   * recorded. `opus <file>` opens that file, still with no folder linked.
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
  /**
   * What argv can be answered by this very process, before run() ever
   * hands it to an Opus that may already be open: `--version`, the
   * language package commands, and a flag nobody knows (which would otherwise open a window on a folder
   * named after it). Not command_line()'s job — with an instance
   * running, that executes over there, and its print() travels back
   * over D-Bus, which a Flatpak sandbox's bus proxy doesn't let through:
   * the terminal that asked would hear nothing.
   */
  public static bool answers_locally (string[] args, out int exit_status) {
    exit_status = 0;
    if (args.length > 1 && (args[1] == "--install-language" || args[1] == "--check-language")) {
      exit_status = run_language_command (args);
      return true;
    }
    foreach (var arg in args[1:args.length]) {
      if (arg == "--version") {
        print ("opus %s\n", BuildInfo.VERSION);
        return true;
      }
      if (arg.has_prefix ("-") && arg != "-" && arg != "-v" && arg != "--verbose") {
        printerr ("opus: unknown option %s\n", arg);
        exit_status = 1;
        return true;
      }
    }
    return false;
  }

  /** The bundled packages, then the user's own, which win a shared name. The variable points an uninstalled build (`just run`, the tests) at the source tree's packages. */
  private static string[] language_directories () {
    return { Environment.get_variable ("OPUS_LANGUAGES_DIR") ?? BuildInfo.LANGUAGES_DIR, user_languages_directory () };
  }

  private static string user_languages_directory () {
    return Path.build_filename (Environment.get_user_data_dir (), "opus", "languages");
  }

  /** What the user's packages had built first — a package pinning its own commit of a bundled grammar gets that one — then what Opus shipped. */
  private static string[] grammar_directories () {
    return { user_grammars_directory (), Environment.get_variable ("OPUS_GRAMMARS_DIR") ?? BuildInfo.GRAMMARS_DIR };
  }

  /** The cache, not the data directory: every file here can be built again from a package's manifest. */
  private static string user_grammars_directory () {
    return Path.build_filename (Environment.get_user_cache_dir (), "opus", "grammars");
  }

  private static Syntax.GrammarBuilder grammar_builder () {
    return new Syntax.GrammarBuilder (
      Path.build_filename (Environment.get_user_cache_dir (), "opus", "grammar-sources"),
      user_grammars_directory ()
    );
  }

  /** `--install-language <folder|git url>` and `--check-language <folder>`: answered and printed here, on the terminal that asked. */
  private static int run_language_command (string[] args) {
    if (args.length != 3) {
      printerr ("usage: opus %s <%s>\n", args[1], args[1] == "--install-language" ? "folder or git url" : "folder");
      return 1;
    }
    return args[1] == "--install-language" ? install_language (args[2]) : check_language (args[2]);
  }

  private static int install_language (string source) {
    var installer = new Syntax.LanguageInstaller (user_languages_directory ());
    try {
      var package = FileUtils.test (source, FileTest.IS_DIR)
        ? installer.install (source)
        : installer.install_from_repository (source);
      print ("Installed %s in %s\n", package.name, package.directory);
      if (package.grammar != null) {
        print ("Building its grammar...\n");
        grammar_builder ().build (package.grammar);
      }
      return report (check_problems (package.directory));
    } catch (Error e) {
      printerr ("opus: %s\n", e.message);
      return 1;
    }
  }

  private static int check_language (string directory) {
    return report (check_problems (directory));
  }

  private static string[] check_problems (string directory) {
    var checker = new Syntax.LanguageChecker (language_directories (), new Syntax.GrammarLoader (grammar_directories ()), grammar_builder ());
    return checker.check (directory);
  }

  private static int report (string[] problems) {
    foreach (unowned string problem in problems) {
      printerr ("%s\n", problem);
    }
    if (problems.length == 0) {
      print ("No problems found.\n");
    }
    return problems.length == 0 ? 0 : 1;
  }

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
    Workspace.resolve (remaining, command_line.get_cwd () ?? Environment.get_current_dir (), out folder_path, out file_path);
    if (folder_path != null) {
      open_workspace (folder_path);
    } else if (file_path != null) {
      open_window (file_path);
    } else {
      open_window (null, last_folder.get_pathname ());
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
  public void open_window (string? initial_file, string? restored_folder = null) {
    var root_path = initial_file != null ? Path.get_dirname (initial_file) : Environment.get_current_dir ();
    var window = create_window (root_path);

    window.new_window_requested.connect (() => open_window (initial_file));

    if (restored_folder != null) {
      try {
        window.link_folder (restored_folder);
      } catch (Error e) {
        Logger.warn ("couldn't restore %s: %s".printf (restored_folder, e.message));
      }
    }

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
    var window = new MainWindow (this, settings, user_settings, last_folder, root_path);
    windows.add (window);

    #if DEBUG
    dev_server.add_session (window);
    #endif

    window.closed.connect (() => {
      windows.remove (window);
      #if DEBUG
      dev_server.remove_session (window);
      #endif
    });

    return window;
  }
}
