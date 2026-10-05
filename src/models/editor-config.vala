/**
 * One `[pattern]` section of a parsed .editorconfig file: the glob it
 * matches against, compiled once up front, and the lowercase key/value
 * properties declared under it.
 */
private class EditorConfigSection : Object {
  public Regex pattern;
  public HashTable<string, string> properties = new HashTable<string, string> (str_hash, str_equal);
}

/**
 * Parses a .editorconfig file and resolves its `indent_size` for a given
 * path — the piece {@link CodeEditorSourceView}'s future indent
 * guides need to know how many columns one indent level is.
 *
 * Only ever reads the .editorconfig at the linked workspace folder's own
 * root, not the full upward directory walk (each ancestor directory up to
 * a `root = true` file) the real spec does per edited file — every file
 * Opus opens lives under that one linked root already, so a single file
 * there covers the common case without needing a per-file search.
 *
 * A file can declare more than one `indent_size` — a global `[*]` section
 * plus per-language overrides like `[*.py]` — so sections are matched in
 * file order and, same as the real spec, a later matching section wins
 * over an earlier one for the same property.
 */
public class EditorConfig : Object {
  private GenericArray<EditorConfigSection> sections = new GenericArray<EditorConfigSection> ();

  private EditorConfig () {}

  /** Null when `folder_path` has no `.editorconfig`, or it can't be read. */
  public static EditorConfig? load (string folder_path) {
    var path = Path.build_filename (folder_path, ".editorconfig");
    if (!FileUtils.test (path, FileTest.EXISTS)) {
      return null;
    }

    string contents;
    try {
      FileUtils.get_contents (path, out contents);
    } catch (Error e) {
      return null;
    }

    return parse (contents);
  }

  /** Split out from {@link load} so parsing can be tested directly against fixture text, no temp file needed. */
  public static EditorConfig parse (string contents) {
    var config = new EditorConfig ();
    EditorConfigSection? current = null;

    foreach (unowned string raw_line in contents.split ("\n")) {
      var line = raw_line.strip ();

      if (line.length == 0 || line.has_prefix (";") || line.has_prefix ("#")) {
        continue;
      }

      if (line.has_prefix ("[") && line.has_suffix ("]")) {
        current = new EditorConfigSection ();
        current.pattern = compile_glob (line.slice (1, line.length - 1));
        config.sections.add (current);
        continue;
      }

      if (current == null) {
        continue; // preamble before the first section (e.g. `root = true`) — not a matchable property
      }

      int separator = line.index_of ("=");
      if (separator < 0) {
        continue;
      }

      var key = line.substring (0, separator).strip ().down ();
      var value = line.substring (separator + 1).strip ().down ();
      current.properties[key] = value;
    }

    return config;
  }

  /**
   * The resolved `indent_size` for `relative_path` (relative to the
   * linked folder), or null if no matching section sets it. `indent_size
   * = tab` resolves to that same section chain's `tab_width` instead,
   * per spec — and null if that isn't set either.
   */
  public int? indent_size_for (string relative_path) {
    string? indent_size = resolve_property (relative_path, "indent_size");
    if (indent_size == null) {
      return null;
    }
    if (indent_size == "tab") {
      string? tab_width = resolve_property (relative_path, "tab_width");
      if (tab_width == null) {
        return null;
      }
      return int.parse (tab_width);
    }
    return int.parse (indent_size);
  }

  /** "space" resolves to true, "tab" (or any other value) to false, null if no matching section sets `indent_style` at all. */
  public bool? insert_spaces_for (string relative_path) {
    string? indent_style = resolve_property (relative_path, "indent_style");
    if (indent_style == null) {
      return null;
    }
    return indent_style == "space";
  }

  /** The resolved value of `key` for `relative_path` — sections matched in file order, last match wins, same rule `indent_size_for`/`insert_spaces_for` both need. Null if none of them set `key`. */
  private string? resolve_property (string relative_path, string key) {
    string? value = null;

    for (int i = 0; i < sections.length; i++) {
      var section = sections[i];
      if (!section.pattern.match (relative_path)) {
        continue;
      }
      if (section.properties.contains (key)) {
        value = section.properties[key];
      }
    }

    return value;
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
