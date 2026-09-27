/**
 * The parsed, typed form of settings.json's `editor.*` keys — always
 * fully populated (each field falls back to the same default the file
 * itself ships with) so a caller never has to null-check a value the
 * user simply hasn't set yet.
 */
public class UserSettingsValues : Object {
  public string? font_family = null;
  public int font_size = UserSettings.system_monospace_font_size ();
  public string font_weight = "normal";
  public bool font_ligatures = false;
  /** 1 — GTK's own real "normal": a line-height multiplier of 1 is exactly the font's own single-line metrics, no override applied. */
  public double line_height = 1;
  public double letter_spacing = 0;
}

/**
 * The user's own editor preferences — a plain JSON file the user edits
 * by hand, not GLib.Settings/dconf: these are per-editor display knobs
 * (font, line height…), not window state, and a file the user can open
 * and edit directly in Opus itself is the point (VS Code's own
 * settings.json, which this is deliberately modeled after).
 */
public class UserSettings : Object {
  // GNOME Text Editor's own real fallback (editor-application.c: system_font_name
  // defaults to "Monospace 11") for when org.gnome.desktop.interface isn't
  // installed at all — a headless/minimal system, not a real desktop.
  private const int FALLBACK_FONT_SIZE = 11;

  private UserSettings () {}

  /**
   * The point size of `org.gnome.desktop.interface`'s own
   * "monospace-font-name" (e.g. "Roboto Mono 10" -> 10) — the same real,
   * live setting GNOME Text Editor itself reads for its default font
   * (checked its source: editor-application.c binds exactly this
   * schema/key). GTK's `monospace = true` alone only resolves fontconfig's
   * generic "monospace" *family*; the size still comes from the general
   * UI font absent this, so reading it directly is the only way to match
   * what the user actually configured as their monospace font's size.
   */
  public static int system_monospace_font_size () {
    var schema_source = SettingsSchemaSource.get_default ();
    if (schema_source == null || schema_source.lookup ("org.gnome.desktop.interface", true) == null) {
      return FALLBACK_FONT_SIZE;
    }

    var settings = new GLib.Settings ("org.gnome.desktop.interface");
    var parts = settings.get_string ("monospace-font-name").split (" ");
    if (parts.length == 0) {
      return FALLBACK_FONT_SIZE;
    }

    int64 size = 0;
    if (!int64.try_parse (parts[parts.length - 1], out size) || size <= 0) {
      return FALLBACK_FONT_SIZE;
    }
    return (int) size;
  }

  private static string default_content () {
    return """{
  "themes.syntaxHighlight": "Opus Colors",
  "editor.fontFamily": null,
  "editor.fontSize": %d,
  "editor.fontWeight": "normal",
  "editor.fontLigatures": false,
  "editor.lineHeight": 1,
  "editor.letterSpacing": 0
}
""".printf (system_monospace_font_size ());
  }

  /**
   * `settings.json`'s path under `config_dir` — the caller's own
   * Environment.get_user_config_dir() for a real run, an isolated temp
   * directory in a test, never read from here so this stays a plain,
   * testable Model with no environment access of its own.
   */
  public static string path (string config_dir) {
    return Path.build_filename (config_dir, "opus", "settings.json");
  }

  /**
   * Creates settings.json, and its parent directory, with default
   * content the first time this is called for a given `config_dir` —
   * an already-existing file, and whatever the user already changed in
   * it, is left untouched either way. Returns its path.
   */
  public static string ensure_exists (string config_dir) throws Error {
    var settings_path = path (config_dir);
    if (FileUtils.test (settings_path, FileTest.EXISTS)) {
      return settings_path;
    }

    DirUtils.create_with_parents (Path.get_dirname (settings_path), 0755);
    FileUtils.set_contents (settings_path, default_content ());
    return settings_path;
  }

  /**
   * Reads settings.json (creating it with defaults first if missing)
   * and parses its `editor.*` keys — a missing key, or the whole file
   * being unreadable or not valid JSON, each just fall back to
   * UserSettingsValues' own defaults rather than failing: this is
   * hand-edited user input, not a build artifact, so a typo in one key
   * degrades that one key, never the editor around it.
   */
  public static UserSettingsValues load (string config_dir) {
    var values = new UserSettingsValues ();

    string settings_path;
    try {
      settings_path = ensure_exists (config_dir);
    } catch (Error e) {
      Logger.warn ("couldn't create settings.json: %s".printf (e.message));
      return values;
    }

    string contents;
    try {
      FileUtils.get_contents (settings_path, out contents);
    } catch (Error e) {
      Logger.warn ("couldn't read settings.json: %s".printf (e.message));
      return values;
    }

    var parser = new Json.Parser ();
    try {
      parser.load_from_data (contents);
    } catch (Error e) {
      Logger.warn ("settings.json isn't valid JSON, using defaults: %s".printf (e.message));
      return values;
    }

    var root = parser.get_root ()?.get_object ();
    if (root == null) {
      return values;
    }

    values.font_family = string_member (root, "editor.fontFamily") ?? values.font_family;
    values.font_size = int_member (root, "editor.fontSize") ?? values.font_size;
    values.font_weight = string_member (root, "editor.fontWeight") ?? values.font_weight;
    values.font_ligatures = bool_member (root, "editor.fontLigatures") ?? values.font_ligatures;
    values.line_height = double_member (root, "editor.lineHeight") ?? values.line_height;
    values.letter_spacing = double_member (root, "editor.letterSpacing") ?? values.letter_spacing;
    return values;
  }

  private static Json.Node? value_member (Json.Object root, string key) {
    var node = root.get_member (key);
    return node != null && node.get_node_type () == Json.NodeType.VALUE ? node : null;
  }

  private static string? string_member (Json.Object root, string key) {
    var node = value_member (root, key);
    return node != null && node.get_value_type () == typeof (string) ? node.get_string () : null;
  }

  private static bool? bool_member (Json.Object root, string key) {
    var node = value_member (root, key);
    if (node == null || node.get_value_type () != typeof (bool)) {
      return null;
    }
    return node.get_boolean ();
  }

  private static int? int_member (Json.Object root, string key) {
    var value = double_member (root, key);
    if (value == null) {
      return null;
    }
    return (int) value;
  }

  private static double? double_member (Json.Object root, string key) {
    var node = value_member (root, key);
    if (node == null) {
      return null;
    }

    var type = node.get_value_type ();
    if (type == typeof (int64)) {
      return (double) node.get_int ();
    }
    if (type == typeof (double)) {
      return node.get_double ();
    }
    return null;
  }
}
