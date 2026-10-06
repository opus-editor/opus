/**
 * The user's own preferences — settings.json, a plain JSON file the user
 * edits by hand, not GLib.Settings/dconf: these are preferences, not
 * window state, and a file the user can open and edit directly in Opus
 * itself is the point (VS Code's own settings.json, which this is
 * deliberately modeled after).
 *
 * An instance is that file's image in memory: built from it, read
 * through one typed property per key, written back by save(), refreshed
 * by reload(). Every property falls back to its default when the key is
 * missing or has the wrong type — this is hand-edited user input, so a
 * typo in one key degrades that one key, never the editor around it.
 */
public class UserSettings : Object {
  // GNOME Text Editor's own real fallback (editor-application.c: system_font_name
  // defaults to "Monospace 11") for when org.gnome.desktop.interface isn't
  // installed at all — a headless/minimal system, not a real desktop.
  private const int FALLBACK_FONT_SIZE = 11;

  public const string DEFAULT_THEME_LIGHT = "github/theme-light";
  public const string DEFAULT_THEME_DARK = "github/theme-dark";

  private Json.Object root;

  /** settings.json's own path. */
  public string path { get; private set; }

  /** A value may read differently now — a property was set, or reload() read the file again. Doesn't say which. */
  public signal void changed ();

  /**
   * Reads settings.json under `config_dir`, creating it (and its parent
   * directory) with default content first if it isn't there. `config_dir`
   * is the caller's own Environment.get_user_config_dir() for a real
   * run, an isolated temp directory in a test — never read from here, so
   * this stays a plain, testable Model with no environment access of
   * its own. A file that can't be created, read or parsed leaves every
   * property at its default.
   */
  public UserSettings (string config_dir) {
    path = Path.build_filename (config_dir, "opus", "settings.json");
    try {
      ensure_exists ();
    } catch (Error e) {
      Logger.warn ("couldn't create settings.json: %s".printf (e.message));
    }
    root = read_root () ?? new Json.Object ();
  }

  /** See LastFolder. */
  public bool restore_folder {
    get { return read_bool ("window.restore_folder", false); }
  }

  public string? font_family {
    owned get { return read_string ("editor.font_family"); }
  }

  public int font_size {
    get {
      // The system's own size is only looked up when the file doesn't set one.
      if (!has_number ("editor.font_size")) {
        return system_monospace_font_size ();
      }
      return (int) read_number ("editor.font_size", 0);
    }
  }

  public string font_weight {
    owned get { return read_string ("editor.font_weight") ?? "normal"; }
  }

  public bool font_ligatures {
    get { return read_bool ("editor.font_ligatures", false); }
  }

  /** 1 — GTK's own real "normal": a line-height multiplier of 1 is exactly the font's own single-line metrics, no override applied. */
  public double line_height {
    get { return read_number ("editor.line_height", 1); }
  }

  public double letter_spacing {
    get { return read_number ("editor.letter_spacing", 0); }
  }

  /** VS Code's own `editor.wordWrap` ('off'/'on' only — see CodeEditor.apply_settings()'s own doc comment for why this app's wrap support is a plain bool, not VS Code's full off/on/wordWrapColumn/bounded enum). Setting it only changes this image — save() is what writes the file. */
  public bool word_wrap {
    get { return read_bool ("editor.word_wrap", false); }
    set {
      root.set_boolean_member ("editor.word_wrap", value);
      changed ();
    }
  }

  /** The theme the editor wears while the app is light — a file under a `themes` directory, as its path from there without the `.json` (`github/theme-light`). */
  public string theme_light {
    owned get { return read_string ("editor.theme_light") ?? DEFAULT_THEME_LIGHT; }
  }

  /** Its counterpart for while the app is dark. */
  public string theme_dark {
    owned get { return read_string ("editor.theme_dark") ?? DEFAULT_THEME_DARK; }
  }

  /** Creates settings.json with default content if it isn't there — an existing file, and whatever the user already changed in it, is left untouched. */
  public void ensure_exists () throws Error {
    if (FileUtils.test (path, FileTest.EXISTS)) {
      return;
    }
    DirUtils.create_with_parents (Path.get_dirname (path), 0755);
    FileUtils.set_contents (path, default_content ());
  }

  /** Writes this image to settings.json, pretty-printed — every key the file had is kept, known to Opus or not. */
  public void save () throws Error {
    var node = new Json.Node (Json.NodeType.OBJECT);
    node.set_object (root);
    FileUtils.set_contents (path, Json.to_string (node, true) + "\n");
  }

  /** Reads settings.json again. A file that can't be read, or isn't a JSON object right now (saved halfway through an edit), leaves this image as it was. */
  public void reload () {
    var fresh = read_root ();
    if (fresh == null) {
      return;
    }
    root = fresh;
    changed ();
  }

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
  "window.restore_folder": false,
  "editor.font_family": null,
  "editor.font_size": %d,
  "editor.font_weight": "normal",
  "editor.font_ligatures": false,
  "editor.line_height": 1,
  "editor.letter_spacing": 0,
  "editor.word_wrap": false,
  "editor.theme_light": "%s",
  "editor.theme_dark": "%s"
}
""".printf (system_monospace_font_size (), DEFAULT_THEME_LIGHT, DEFAULT_THEME_DARK);
  }

  private Json.Object? read_root () {
    string contents;
    try {
      FileUtils.get_contents (path, out contents);
    } catch (Error e) {
      Logger.warn ("couldn't read settings.json: %s".printf (e.message));
      return null;
    }

    var parser = new Json.Parser ();
    try {
      parser.load_from_data (contents);
    } catch (Error e) {
      Logger.warn ("settings.json isn't valid JSON: %s".printf (e.message));
      return null;
    }

    var node = parser.get_root ();
    return node != null && node.get_node_type () == Json.NodeType.OBJECT ? node.get_object () : null;
  }

  private Json.Node? read_value (string key) {
    var node = root.get_member (key);
    return node != null && node.get_node_type () == Json.NodeType.VALUE ? node : null;
  }

  private string? read_string (string key) {
    var node = read_value (key);
    return node != null && node.get_value_type () == typeof (string) ? node.get_string () : null;
  }

  private bool read_bool (string key, bool fallback) {
    var node = read_value (key);
    if (node == null || node.get_value_type () != typeof (bool)) {
      return fallback;
    }
    return node.get_boolean ();
  }

  private bool has_number (string key) {
    var node = read_value (key);
    return node != null && (node.get_value_type () == typeof (int64) || node.get_value_type () == typeof (double));
  }

  private double read_number (string key, double fallback) {
    if (!has_number (key)) {
      return fallback;
    }
    var node = read_value (key);
    return node.get_value_type () == typeof (int64) ? (double) node.get_int () : node.get_double ();
  }
}
