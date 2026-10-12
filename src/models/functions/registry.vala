namespace Functions {
  /** Whether a name is a language package's — what tells a language group's folder from a stray one. */
  public delegate bool KnownLanguageFunc (string name);

  /**
   * Every function the `|` list can offer: the native catalog, then the
   * packages of each directory in turn — the bundled ones, then the
   * user's — a later one replacing an earlier one of the same id. A
   * folder with no manifest is a language group: its functions are
   * listed for that language only. Scanned on `reload ()`, never
   * before: nothing is read until the list is first asked for, or
   * "Reload functions" runs.
   */
  public class Registry : Object {
    public static Registry? instance { get; set; }

    private string[] directories;
    private KnownLanguageFunc is_language;
    private GenericArray<Function> functions = new GenericArray<Function> ();

    /** False until the first {@link reload}. */
    public bool loaded { get; private set; default = false; }

    public Registry (string[] directories, owned KnownLanguageFunc is_language) {
      this.directories = directories;
      this.is_language = (owned) is_language;
    }

    public void reload () {
      functions = new GenericArray<Function> ();
      foreach (var function in Native.catalog ()) {
        add (function);
      }
      foreach (var directory in directories) {
        scan (directory, null);
      }
      loaded = true;
    }

    /** The functions listed for `language` (null for a file with none), by name. */
    public GenericArray<Function> for_language (string? language) {
      var listed = new GenericArray<Function> ();
      foreach (var function in functions) {
        if (function.applies_to (language)) {
          listed.add (function);
        }
      }
      listed.sort ((a, b) => strcmp (a.name.casefold (), b.name.casefold ()));
      return listed;
    }

    public Function? by_id (string id) {
      foreach (var function in functions) {
        if (function.id == id) {
          return function;
        }
      }
      return null;
    }

    private void scan (string directory, string? group) {
      Dir dir;
      try {
        dir = Dir.open (directory);
      } catch (FileError e) {
        return; // a directory that isn't there yet holds no functions
      }
      string? name;
      while ((name = dir.read_name ()) != null) {
        var path = Path.build_filename (directory, name);
        if (!FileUtils.test (path, FileTest.IS_DIR)) {
          continue;
        }
        if (FileUtils.test (Path.build_filename (path, Manifest.FILE), FileTest.IS_REGULAR)) {
          load_package (path, group);
        } else if (group == null && is_language (name)) {
          scan (path, name);
        } else {
          Logger.warn ("functions: %s is neither a function (no %s) nor a language".printf (path, Manifest.FILE));
        }
      }
    }

    private void load_package (string path, string? group) {
      Manifest manifest;
      try {
        manifest = Manifest.load (path);
      } catch (ManifestError e) {
        Logger.warn ("functions: %s".printf (e.message));
        return;
      }
      var languages = manifest.languages;
      if (group != null && !(group in languages)) {
        languages += group;
      }
      add (new Function (manifest.id, manifest.name, manifest.description, manifest.input, languages, new LuaRunner (manifest.entry)));
    }

    private void add (Function function) {
      for (uint i = 0; i < functions.length; i++) {
        if (functions[i].id == function.id) {
          functions[i] = function;
          return;
        }
      }
      functions.add (function);
    }
  }
}
