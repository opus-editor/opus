namespace Syntax {
  public errordomain GrammarError {
    NOT_FOUND,
    LOAD_FAILED,
    INCOMPATIBLE_ABI,
  }

  [CCode (has_target = false)]
  private delegate unowned TreeSitter.Language GrammarFunc ();

  /**
   * Turns a grammar's compiled shared library into a usable
   * TreeSitter.Language. A library is opened once and stays mapped for
   * the life of the process: the Language it hands out is static data
   * inside it, and every tree parsed with it points back there.
   */
  public class GrammarLoader : Object {
    /** Opus only runs on Linux, and GLib deprecated its own per-platform constant for this. */
    public const string LIBRARY_SUFFIX = "so";

    private string[] directories;
    private HashTable<string, unowned TreeSitter.Language> loaded = new HashTable<string, unowned TreeSitter.Language> (str_hash, str_equal);

    /**
     * `directories` are searched in order, each for a library built
     * from exactly the grammar's commit ({@link library_name}) and
     * then for a plain `<grammar name>.so` — what Opus's own build
     * names the bundled ones, whose commit is whatever it shipped.
     */
    public GrammarLoader (string[] directories) {
      this.directories = directories;
    }

    /** The file name of `grammar`'s library when built for its pinned commit. */
    public static string library_name (GrammarSource grammar) {
      return "%s-%s.%s".printf (grammar.name, grammar.rev, LIBRARY_SUFFIX);
    }

    public unowned TreeSitter.Language load (GrammarSource grammar) throws GrammarError {
      var path = find (grammar);
      unowned TreeSitter.Language? cached = loaded[path];
      if (cached != null) {
        return cached;
      }

      unowned TreeSitter.Language language = open (path, grammar);
      check_abi (language, grammar);
      loaded[path] = language;
      return language;
    }

    private string find (GrammarSource grammar) throws GrammarError {
      string[] file_names = { library_name (grammar), "%s.%s".printf (grammar.name, LIBRARY_SUFFIX) };
      foreach (unowned string directory in directories) {
        foreach (unowned string file_name in file_names) {
          var path = Path.build_filename (directory, file_name);
          if (FileUtils.test (path, FileTest.IS_REGULAR)) {
            return path;
          }
        }
      }
      throw new GrammarError.NOT_FOUND ("no compiled grammar \"%s\"", grammar.name);
    }

    private static unowned TreeSitter.Language open (string path, GrammarSource grammar) throws GrammarError {
      var module = Module.open (path, ModuleFlags.LAZY | ModuleFlags.LOCAL);
      if (module == null) {
        throw new GrammarError.LOAD_FAILED ("%s: %s", path, Module.error ());
      }

      void* symbol;
      if (!module.symbol (grammar.symbol, out symbol) || symbol == null) {
        throw new GrammarError.LOAD_FAILED ("%s does not export %s", path, grammar.symbol);
      }

      // `module` going out of scope would otherwise unmap the Language
      // this returns.
      module.make_resident ();
      return ((GrammarFunc) symbol) ();
    }

    /** A grammar outside this range would be refused by the parser anyway, only later and without saying why. */
    private static void check_abi (TreeSitter.Language language, GrammarSource grammar) throws GrammarError {
      uint32 abi = language.abi_version ();
      if (abi < TreeSitter.MIN_COMPATIBLE_LANGUAGE_VERSION || abi > TreeSitter.LANGUAGE_VERSION) {
        throw new GrammarError.INCOMPATIBLE_ABI (
          "grammar \"%s\" has ABI %u; this Opus runs ABI %u to %u",
          grammar.name, abi, TreeSitter.MIN_COMPATIBLE_LANGUAGE_VERSION, TreeSitter.LANGUAGE_VERSION
        );
      }
    }
  }
}
