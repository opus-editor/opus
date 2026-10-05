namespace Syntax {
  /**
   * The one place the rest of Opus asks "what language is this file,
   * and give it to me ready to use". Owns the registry of packages and
   * the cache of loaded languages, so a grammar is loaded and its
   * queries compiled once per process no matter how many tabs show
   * that language.
   */
  public class Languages : Object {
    /** Set once by App.startup(), before any window exists — every CodeEditor reads it. */
    public static Languages? instance { get; set; }

    private LanguageRegistry registry;
    private GrammarLoader grammars;
    private QuerySource queries;
    private CaptureStyles styles;
    // A null value records a language that failed to load, so it isn't
    // retried (and re-logged) for every file of that type.
    private HashTable<string, LoadedLanguage?> loaded = new HashTable<string, LoadedLanguage?> (str_hash, str_equal);

    /**
     * `language_directories` in rising precedence, `grammar_directories`
     * in search order (see LanguageRegistry and GrammarLoader);
     * `style_keys` are the styles the theme can paint, which captures
     * get resolved against.
     */
    public Languages (string[] language_directories, string[] grammar_directories, string[] style_keys) {
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

    private LoadedLanguage? load (LanguagePackage package) {
      if (loaded.contains (package.name)) {
        return loaded[package.name];
      }

      LoadedLanguage? language = null;
      try {
        language = LoadedLanguage.load (package, grammars, queries, styles);
      } catch (LanguageError e) {
        Logger.warn (e.message);
      }
      loaded[package.name] = language;
      return language;
    }
  }
}
