public errordomain ThemeError {
  NOT_FOUND,
  INVALID,
}

/** How one syntax style is painted. A null color leaves that side to the editor's own. */
public class ThemeStyle : Object {
  public string? foreground { get; internal set; }
  public string? background { get; internal set; }
  public bool bold { get; internal set; }
  public bool italic { get; internal set; }
  public bool underline { get; internal set; }
  public bool strikethrough { get; internal set; }
}

/**
 * The editor's syntax colors, read from one JSON file: under `syntax`,
 * one style per capture name a highlights query may use. A theme
 * doesn't list every capture — a query's `keyword.control.return` is painted with the
 * theme's `keyword` when it defines nothing closer (see
 * Syntax.CaptureStyles).
 *
 * Bundled themes and the user's own are the same file in two
 * directories; a theme is known by its file name.
 */
public class Theme : Object {
  public string name { get; private set; }

  private HashTable<string, ThemeStyle> styles = new HashTable<string, ThemeStyle> (str_hash, str_equal);
  private static Regex? color_regex;

  private Theme (string name) {
    this.name = name;
  }

  /** A theme that styles nothing — what the editor falls back on when none can be loaded. */
  public Theme.empty () {
    this ("");
  }

  /** `<name>.json` from the last of `directories` that has it, so a later directory overrides an earlier one. */
  public static Theme load (string[] directories, string name) throws ThemeError {
    for (int i = directories.length - 1; i >= 0; i--) {
      var path = Path.build_filename (directories[i], name + ".json");
      if (!FileUtils.test (path, FileTest.IS_REGULAR)) {
        continue;
      }
      string contents;
      try {
        FileUtils.get_contents (path, out contents);
      } catch (FileError e) {
        throw new ThemeError.INVALID ("%s: %s", path, e.message);
      }
      return parse (name, contents);
    }
    throw new ThemeError.NOT_FOUND ("no theme named \"%s\"", name);
  }

  /** Split out from {@link load} so a theme can be tested as plain text. */
  public static Theme parse (string name, string json) throws ThemeError {
    var root = parse_root (json);
    var theme = new Theme (name);
    theme.read_syntax (object_member (root, "syntax"));
    return theme;
  }

  /** Null for a key the theme doesn't define. */
  public ThemeStyle? style (string key) {
    return styles[key];
  }

  /** Every syntax key the theme defines — what capture names get resolved against. */
  public string[] style_keys () {
    string[] keys = {};
    foreach (unowned string key in styles.get_keys ()) {
      keys += key;
    }
    return keys;
  }

  private static Json.Object parse_root (string json) throws ThemeError {
    var parser = new Json.Parser ();
    try {
      parser.load_from_data (json);
    } catch (Error e) {
      throw new ThemeError.INVALID ("not valid JSON: %s", e.message);
    }
    var root = parser.get_root ();
    if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
      throw new ThemeError.INVALID ("the theme must be a JSON object");
    }
    return root.get_object ();
  }

  /** Null when `key` is absent. */
  private static Json.Object? object_member (Json.Object parent, string key) throws ThemeError {
    if (!parent.has_member (key)) {
      return null;
    }
    var node = parent.get_member (key);
    if (node.get_node_type () != Json.NodeType.OBJECT) {
      throw new ThemeError.INVALID ("\"%s\" must be an object", key);
    }
    return node.get_object ();
  }

  private void read_syntax (Json.Object? syntax) throws ThemeError {
    if (syntax == null) {
      return;
    }
    foreach (unowned string key in syntax.get_members ()) {
      var node = syntax.get_member (key);
      if (node.get_node_type () != Json.NodeType.OBJECT) {
        throw new ThemeError.INVALID ("syntax.%s must be an object", key);
      }
      styles[key] = style_of (node.get_object (), "syntax." + key);
    }
  }

  private static ThemeStyle style_of (Json.Object object, string where) throws ThemeError {
    var style = new ThemeStyle ();
    if (object.has_member ("foreground")) {
      style.foreground = color_of (object, "foreground", where + ".foreground");
    }
    if (object.has_member ("background")) {
      style.background = color_of (object, "background", where + ".background");
    }
    style.bold = flag_of (object, "bold", where);
    style.italic = flag_of (object, "italic", where);
    style.underline = flag_of (object, "underline", where);
    style.strikethrough = flag_of (object, "strikethrough", where);
    return style;
  }

  private static string color_of (Json.Object object, string key, string where) throws ThemeError {
    var node = object.get_member (key);
    if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (string) || !is_color (node.get_string ())) {
      throw new ThemeError.INVALID ("%s must be a color written #rrggbb or #rrggbbaa", where);
    }
    return node.get_string ();
  }

  private static bool flag_of (Json.Object object, string key, string where) throws ThemeError {
    if (!object.has_member (key)) {
      return false;
    }
    var node = object.get_member (key);
    if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (bool)) {
      throw new ThemeError.INVALID ("%s.%s must be true or false", where, key);
    }
    return node.get_boolean ();
  }

  private static bool is_color (string text) {
    if (color_regex == null) {
      try {
        color_regex = new Regex ("^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$");
      } catch (RegexError e) {
        error ("unreachable: the color pattern failed to compile: %s", e.message);
      }
    }
    return color_regex.match (text);
  }
}
