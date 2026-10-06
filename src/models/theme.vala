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
 * Under `palette`, names for colors: wherever a style takes a color,
 * it may name one of these instead of spelling it out. A name is told
 * from a color by not starting with `#`. Two names need no palette:
 * `editor.foreground` and `editor.background` stand for the editor's
 * own text and background colors, whatever those are — a style using
 * them exists (so its capture counts) and leaves that side alone.
 *
 * Under `languages`, the same again per language package: styles that
 * hold in that language only. Each is kept under the key
 * Syntax.CaptureStyles.language_key() gives it, next to the general
 * ones, so whatever paints by key needs to know nothing about them.
 *
 * Bundled themes and the user's own are the same file in two
 * directories; a theme is known by its path inside one, without the
 * `.json` — `github/theme-light` for the light one of the `github`
 * folder.
 */
public class Theme : Object {
  private const string COLOR_PREFIX = "#";
  private const string EDITOR_FOREGROUND = "editor.foreground";
  private const string EDITOR_BACKGROUND = "editor.background";

  public string name { get; private set; }

  private HashTable<string, ThemeStyle> styles = new HashTable<string, ThemeStyle> (str_hash, str_equal);
  // Only while the file is being read: styles end up holding the colors themselves.
  private HashTable<string, string> palette = new HashTable<string, string> (str_hash, str_equal);
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
    theme.read_palette (object_member (root, "palette"));
    theme.read_syntax (object_member (root, "syntax"));
    theme.read_languages (object_member (root, "languages"));
    theme.palette.remove_all ();
    return theme;
  }

  /** Null for a key the theme doesn't define. A style of one language is under its Syntax.CaptureStyles.language_key(). */
  public ThemeStyle? style (string key) {
    return styles[key];
  }

  /** Every syntax key the theme defines, the ones of a single language included — what capture names get resolved against. */
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

  private void read_palette (Json.Object? named) throws ThemeError {
    if (named == null) {
      return;
    }
    foreach (unowned string name in named.get_members ()) {
      if (name == "" || name.has_prefix (COLOR_PREFIX)) {
        throw new ThemeError.INVALID ("palette: \"%s\" can't be a color's name", name);
      }
      var node = named.get_member (name);
      if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (string) || !is_color (node.get_string ())) {
        throw new ThemeError.INVALID ("palette.%s must be a color written #rrggbb or #rrggbbaa", name);
      }
      palette[name] = node.get_string ();
    }
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

  // A language the theme names needn't exist: its package may be one this machine doesn't have.
  private void read_languages (Json.Object? languages) throws ThemeError {
    if (languages == null) {
      return;
    }
    foreach (unowned string language in languages.get_members ()) {
      if (!Syntax.CaptureStyles.can_have_styles (language)) {
        throw new ThemeError.INVALID ("languages: \"%s\" can't be a language's name", language);
      }
      var node = languages.get_member (language);
      if (node.get_node_type () != Json.NodeType.OBJECT) {
        throw new ThemeError.INVALID ("languages.%s must be an object", language);
      }
      read_language (language, node.get_object ());
    }
  }

  private void read_language (string language, Json.Object own) throws ThemeError {
    foreach (unowned string key in own.get_members ()) {
      var node = own.get_member (key);
      if (node.get_node_type () != Json.NodeType.OBJECT) {
        throw new ThemeError.INVALID ("languages.%s.%s must be an object", language, key);
      }
      styles[Syntax.CaptureStyles.language_key (language, key)] = style_of (node.get_object (), "languages.%s.%s".printf (language, key));
    }
  }

  private ThemeStyle style_of (Json.Object object, string where) throws ThemeError {
    var style = new ThemeStyle ();
    if (object.has_member ("foreground")) {
      style.foreground = color_of (object, "foreground", EDITOR_FOREGROUND, where + ".foreground");
    }
    if (object.has_member ("background")) {
      style.background = color_of (object, "background", EDITOR_BACKGROUND, where + ".background");
    }
    style.bold = flag_of (object, "bold", where);
    style.italic = flag_of (object, "italic", where);
    style.underline = flag_of (object, "underline", where);
    style.strikethrough = flag_of (object, "strikethrough", where);
    return style;
  }

  /** Null for `editors_own`, the editor's color for this side — unless the palette gives that name a color of its own. */
  private string? color_of (Json.Object object, string key, string editors_own, string where) throws ThemeError {
    var node = object.get_member (key);
    if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (string)) {
      throw new ThemeError.INVALID ("%s must be a color written #rrggbb or #rrggbbaa, or the name of one in the palette", where);
    }
    var written = node.get_string ();
    if (written.has_prefix (COLOR_PREFIX)) {
      if (!is_color (written)) {
        throw new ThemeError.INVALID ("%s must be a color written #rrggbb or #rrggbbaa", where);
      }
      return written;
    }
    if (palette.contains (written)) {
      return palette[written];
    }
    if (written == editors_own) {
      return null;
    }
    if (written == EDITOR_FOREGROUND || written == EDITOR_BACKGROUND) {
      throw new ThemeError.INVALID ("%s: \"%s\" is the editor's own %s, which can't be a %s", where, written, written == EDITOR_FOREGROUND ? "text color" : "background", key);
    }
    throw new ThemeError.INVALID ("%s: the palette has no color named \"%s\"", where, written);
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
