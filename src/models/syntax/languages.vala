namespace Syntax {
  /**
   * The one place the rest of Opus asks "what language is this file,
   * and give it to me ready to use". Owns the registry of packages and
   * the cache of loaded languages, so a grammar is loaded and its
   * queries compiled once per process no matter how many tabs show
   * that language.
   */
  public class Languages : Object {
    // A package edited in place is saved as several writes; one reload for the burst.
    private const uint RELOAD_LATENCY_MS = 200;

    /** Set once by App.startup(), before any window exists — every CodeEditor reads it. */
    public static Languages? instance { get; set; }

    private string[] language_directories;
    private LanguageRegistry registry;
    private GrammarLoader grammars;
    private GrammarBuilder? builder;
    private QuerySource queries;
    private CaptureStyles styles;
    // A null value records a language that failed to load, so it isn't
    // retried (and re-logged) for every file of that type.
    private HashTable<string, LoadedLanguage?> loaded = new HashTable<string, LoadedLanguage?> (str_hash, str_equal);
    private GenericSet<string> building = new GenericSet<string> (str_hash, str_equal);
    private GenericArray<FileMonitor> monitors = new GenericArray<FileMonitor> ();
    private string? watched_directory;
    private uint pending_reload_id = 0;

    /**
     * What {@link detect} answers may be different now: a package was
     * added, edited or removed, or a grammar that was still being
     * built is ready. Whoever holds a language should ask again.
     */
    public signal void changed ();

    /**
     * `language_directories` in rising precedence, `grammar_directories`
     * in search order (see LanguageRegistry and GrammarLoader);
     * `style_keys` are the styles the theme can paint, which captures
     * get resolved against. With a `builder`, a package whose grammar
     * was never compiled gets it built the first time a file needs it.
     */
    public Languages (string[] language_directories, string[] grammar_directories, string[] style_keys, GrammarBuilder? builder = null) {
      this.language_directories = language_directories;
      this.builder = builder;
      registry = new LanguageRegistry (language_directories);
      grammars = new GrammarLoader (grammar_directories);
      queries = new QuerySource (registry);
      styles = new CaptureStyles (style_keys);
    }

    /**
     * Swaps the styles captures resolve against — a theme change.
     * Reaches the languages already loaded too, so anything painted
     * before this has to be painted again to pick the new styles up.
     */
    public void set_style_keys (string[] style_keys) {
      styles = new CaptureStyles (style_keys);
      foreach (var language in loaded.get_values ()) {
        if (language != null) {
          language.resolve_styles (styles);
        }
      }
    }

    /** The language of the file at `path`, ready to use — null when no package claims the file or the one that does can't be loaded. */
    public LoadedLanguage? detect (string path, string? first_line = null) {
      var package = registry.detect (path, first_line);
      return package == null ? null : load (package);
    }

    /** The language an injection naming `name` means (a fenced code block's `js`, a query's `"css"`), ready to use — null on the same terms as {@link detect}. */
    public LoadedLanguage? for_injection (string name) {
      var package = registry.for_injection (name);
      return package == null ? null : load (package);
    }

    /** Reads every package from disk again and forgets every loaded language. Compiled grammars stay: a library can't be unloaded, so a rebuilt one only takes effect on the next start. */
    public void reload () {
      registry = new LanguageRegistry (language_directories);
      queries = new QuerySource (registry);
      loaded.remove_all ();
      changed ();
    }

    /**
     * Calls {@link reload} whenever a package under `directory`
     * changes — what lets someone writing a package see a saved query
     * take effect without restarting. Meant for the user's own
     * directory; the bundled one never changes under a running Opus.
     */
    public void watch (string directory) {
      watched_directory = directory;
      rewatch ();
    }

    private LoadedLanguage? load (LanguagePackage package) {
      if (loaded.contains (package.name)) {
        return loaded[package.name];
      }

      LoadedLanguage? language = null;
      try {
        language = LoadedLanguage.load (package, grammars, queries, styles);
      } catch (LanguageError e) {
        if (e is LanguageError.GRAMMAR_NOT_BUILT && builder != null) {
          build_grammar.begin (package);
          // Not cached as failed: the build's own `changed` has callers ask again.
          return null;
        }
        Logger.warn (e.message);
      }
      loaded[package.name] = language;
      return language;
    }

    private async void build_grammar (LanguagePackage package) {
      var key = GrammarLoader.library_name (package.grammar);
      if (building.contains (key)) {
        return;
      }
      building.add (key);

      try {
        yield builder.build_async (package.grammar);
        Logger.info ("built grammar %s".printf (key));
      } catch (BuildError e) {
        Logger.warn ("language \"%s\": %s".printf (package.name, e.message));
        // Recorded as failed, so the next file of this type doesn't start the build over.
        loaded[package.name] = null;
        building.remove (key);
        return;
      }
      building.remove (key);
      changed ();
    }

    /** One monitor on the directory, one per package and one per package's `queries`: GFileMonitor doesn't recurse. */
    private void rewatch () {
      foreach (var monitor in monitors) {
        monitor.cancel ();
      }
      monitors = new GenericArray<FileMonitor> ();

      monitor_directory (watched_directory);
      try {
        var dir = Dir.open (watched_directory);
        string? name;
        while ((name = dir.read_name ()) != null) {
          var package_directory = Path.build_filename (watched_directory, name);
          monitor_directory (package_directory);
          monitor_directory (Path.build_filename (package_directory, "queries"));
        }
      } catch (FileError e) {
        // No such directory yet: its parent isn't watched, so packages
        // first appearing there are picked up on the next start.
      }
    }

    private void monitor_directory (string path) {
      if (!FileUtils.test (path, FileTest.IS_DIR)) {
        return;
      }
      try {
        var monitor = File.new_for_path (path).monitor_directory (FileMonitorFlags.NONE);
        monitor.changed.connect (schedule_reload);
        monitors.add (monitor);
      } catch (Error e) {
        Logger.warn ("couldn't watch %s: %s".printf (path, e.message));
      }
    }

    private void schedule_reload () {
      if (pending_reload_id != 0) {
        return;
      }
      pending_reload_id = Timeout.add (RELOAD_LATENCY_MS, () => {
        pending_reload_id = 0;
        // A new package directory needs its own monitors too.
        rewatch ();
        reload ();
        return Source.REMOVE;
      });
    }
  }
}
