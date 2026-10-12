namespace Opus.Plugins.EditorConfig {
  /** Where a Hierarchy gets the file of a directory from — ConfigFile.in_directory, or a cache in front of it. */
  public delegate ConfigFile? Loader (string directory);

  /**
   * The .editorconfig files that apply to one file: from its own
   * directory up to the filesystem root (so a `~/.editorconfig` counts),
   * stopping at the first with `root = true`. Resolved outermost first,
   * so the closest file has the last word; then a property left at
   * `unset` is dropped, as if no file had named it.
   */
  public class Hierarchy : Object {
    /** Outermost first. */
    private GenericArray<ConfigFile> files;

    public Hierarchy (GenericArray<ConfigFile> files) {
      this.files = files;
    }

    public static Hierarchy for_file (string path, Loader loader = ConfigFile.in_directory) {
      var found = new GenericArray<ConfigFile> ();
      var directory = Path.get_dirname (path);
      while (true) {
        var file = loader (directory);
        if (file != null) {
          found.insert (0, file);
          if (file.is_root) {
            break;
          }
        }
        if (directory == "/" || directory == ".") {
          break;
        }
        directory = Path.get_dirname (directory);
      }
      return new Hierarchy (found);
    }

    public Resolved resolve (string path) {
      var properties = new HashTable<string, string> (str_hash, str_equal);
      foreach (var file in files) {
        file.apply (path, properties);
      }
      foreach (var key in properties.get_keys ()) {
        if (properties[key] == "unset") {
          properties.remove (key);
        }
      }
      return new Resolved (properties);
    }
  }

  /** The properties that apply to one file, read as what the editor understands; null where the files say nothing (or something unsupported). */
  public class Resolved : Object {
    private HashTable<string, string> properties;

    public Resolved (HashTable<string, string> properties) {
      this.properties = properties;
    }

    public string? property (string key) {
      return properties[key];
    }

    /** `indent_size`, or `tab_width` when `indent_size = tab`, per spec — null without either. */
    public int? indent_size () {
      var value = properties["indent_size"];
      if (value == "tab") {
        value = properties["tab_width"];
      }
      return value == null ? null : (int?) int.parse (value);
    }

    /** `indent_style`: "space" is true, "tab" (or anything else set) false. */
    public bool? insert_spaces () {
      var value = properties["indent_style"];
      return value == null ? null : (bool?) (value == "space");
    }

    /** `end_of_line`: lf or crlf; "cr", which nothing supports, is null. */
    public Document.LineEnding? end_of_line () {
      switch (properties["end_of_line"]) {
        case "lf": return Document.LineEnding.LF;
        case "crlf": return Document.LineEnding.CRLF;
        default: return null;
      }
    }

    public bool? trim_trailing_whitespace () {
      return boolean ("trim_trailing_whitespace");
    }

    public bool? insert_final_newline () {
      return boolean ("insert_final_newline");
    }

    private bool? boolean (string key) {
      switch (properties[key]) {
        case "true": return true;
        case "false": return false;
        default: return null;
      }
    }
  }
}
