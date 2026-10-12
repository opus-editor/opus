namespace Opus.Plugins.EditorConfig {
  /**
   * One `[pattern]` section of a parsed .editorconfig file: the glob it
   * matches against, compiled once up front, and the lowercase key/value
   * properties declared under it.
   */
  private class Section : Object {
    public Regex pattern;
    public HashTable<string, string> properties = new HashTable<string, string> (str_hash, str_equal);
  }

  /**
   * One parsed .editorconfig file. Its sections' globs are relative to
   * the directory it sits in, the spec's rule: `[src/*.js]` in
   * `packages/app/.editorconfig` matches `packages/app/src/x.js`, and a
   * file outside that directory matches nothing here. `root = true` in
   * the preamble makes it the last file a Hierarchy reads on its way up.
   */
  public class ConfigFile : Object {
    public const string NAME = ".editorconfig";

    public string directory { get; private set; }
    public bool is_root { get; private set; default = false; }
    private GenericArray<Section> sections = new GenericArray<Section> ();

    private ConfigFile (string directory) {
      this.directory = directory;
    }

    /** The file in `directory`, null when there is none or it can't be read. */
    public static ConfigFile? in_directory (string directory) {
      var path = Path.build_filename (directory, NAME);
      if (!FileUtils.test (path, FileTest.IS_REGULAR)) {
        return null;
      }
      string contents;
      try {
        FileUtils.get_contents (path, out contents);
      } catch (Error e) {
        return null;
      }
      return parse (contents, directory);
    }

    /** Split out from {@link in_directory} so parsing can be tested against fixture text, no temp file needed. */
    public static ConfigFile parse (string contents, string directory) {
      var config = new ConfigFile (directory);
      Section? current = null;

      foreach (unowned string raw_line in contents.split ("\n")) {
        var line = raw_line.strip ();

        if (line.length == 0 || line.has_prefix (";") || line.has_prefix ("#")) {
          continue;
        }

        if (line.has_prefix ("[") && line.has_suffix ("]")) {
          current = new Section ();
          current.pattern = compile_glob (line.slice (1, line.length - 1));
          config.sections.add (current);
          continue;
        }

        int separator = line.index_of ("=");
        if (separator < 0) {
          continue;
        }
        var key = line.substring (0, separator).strip ().down ();
        var value = line.substring (separator + 1).strip ().down ();

        if (current == null) {
          // The preamble: only `root` means anything there.
          config.is_root = config.is_root || (key == "root" && value == "true");
          continue;
        }
        current.properties[key] = value;
      }

      return config;
    }

    /** Lays every section that matches `path` (absolute) over `properties`, in file order — a later section's value wins. */
    public void apply (string path, HashTable<string, string> properties) {
      var relative = relative_to_directory (path);
      if (relative == null) {
        return;
      }
      for (int i = 0; i < sections.length; i++) {
        var section = sections[i];
        if (!section.pattern.match (relative)) {
          continue;
        }
        section.properties.foreach ((key, value) => properties[key] = value);
      }
    }

    /** `path` relative to this file's directory, null when it isn't inside it. */
    private string? relative_to_directory (string path) {
      var prefix = directory == "/" ? "/" : directory + "/";
      return path.has_prefix (prefix) ? path.substring (prefix.length) : null;
    }

    /** A section header's glob as a Regex — see {@link Glob.compile} for the syntax. */
    private static Regex compile_glob (string pattern) {
      try {
        return Glob.compile (pattern);
      } catch (RegexError e) {
        error ("unreachable: EditorConfig-generated regex failed to compile: %s (pattern: %s)", e.message, pattern);
      }
    }
  }
}
