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

  public const string DEFAULT_THEME_SYNTAX = "opus-editor/github-theme";

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

  /** See SessionStore. */
  public bool save_session {
    get { return read_bool ("window.save_session", false); }
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

  /**
   * `editor.word_wrap` for files highlighted as `language` (a package
   * name): a `"language.<name>": { "editor.word_wrap": … }` block's
   * own value when the file has one, else the plain key. VS Code's
   * `[markdown]` blocks, by the name Opus's own languages go by.
   */
  public bool word_wrap_for (string? language) {
    var node = language_block (language)?.get_member ("editor.word_wrap");
    if (node == null || node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (bool)) {
      return word_wrap;
    }
    return node.get_boolean ();
  }

  /**
   * Whether Tab inserts spaces in files highlighted as `language`:
   * `editor.indent_style`, "space" or "tab", a `language.<name>` block's
   * own value first. Spaces with neither, VS Code's own default. The
   * file's .editorconfig has the last word (see EditorView.EditorPane.TabDocument).
   */
  public bool insert_spaces_for (string? language) {
    var style = indent_style_in (language_block (language)) ?? indent_style_in (root);
    return style != "tab";
  }

  /** `editor.indent_style` in `object`, "space" or "tab"; null for anything else. */
  private static string? indent_style_in (Json.Object? object) {
    var node = object?.get_member ("editor.indent_style");
    if (node == null || node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (string)) {
      return null;
    }
    unowned string style = node.get_string ();
    return style == "space" || style == "tab" ? style : null;
  }

  /**
   * Columns per indent level in files highlighted as `language`:
   * `editor.indent_size`, a whole number above zero, a `language.<name>`
   * block's own value first. 4 with neither, VS Code's own `tabSize`.
   */
  public int indent_size_for (string? language) {
    return indent_size_in (language_block (language)) ?? indent_size_in (root) ?? 4;
  }

  private static int? indent_size_in (Json.Object? object) {
    var node = object?.get_member ("editor.indent_size");
    if (node == null || node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (int64) || node.get_int () <= 0) {
      return null;
    }
    return (int) node.get_int ();
  }

  /**
   * The ids of the functions run over a file right before it is saved,
   * in order (`"editor.on_save": ["trim-trailing-whitespace", …]`): a
   * `language.<name>` block's own list when it has one, else the plain
   * key's; none with neither. The folder's .editorconfig adds or removes
   * its own two on top (see EditorView.EditorPane.TabDocument).
   */
  public string[] on_save_for (string? language) {
    return read_string_list (language_block (language), "editor.on_save") ?? read_string_list (root, "editor.on_save") ?? new string[0];
  }

  /**
   * The columns the editor draws a ruler at (`"editor.rulers": [80, 120]`),
   * VS Code's own setting without its per-ruler colors: a `language.<name>`
   * block's own list when it has one, else the plain key's; none with
   * neither. The first one also tints everything to its right.
   */
  public int[] rulers_for (string? language) {
    int[] columns;
    if (read_int_list (language_block (language), "editor.rulers", out columns) || read_int_list (root, "editor.rulers", out columns)) {
      return columns;
    }
    return {};
  }

  /**
   * `editorconfig.max_line_length`: whether a file's own `max_line_length`
   * from .editorconfig is its ruler, in place of `editor.rulers`. Off by
   * default, as in VS Code, whose extension never reads that property.
   * A `language.<name>` block may set it for one language.
   */
  public bool editorconfig_max_line_length_for (string? language) {
    var node = language_block (language)?.get_member ("editorconfig.max_line_length");
    if (node == null || node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (bool)) {
      return read_bool ("editorconfig.max_line_length", false);
    }
    return node.get_boolean ();
  }

  /** The `"language.<name>": { … }` object, null without one. */
  private Json.Object? language_block (string? language) {
    if (language == null) {
      return null;
    }
    var block = root.get_member ("language." + language);
    return block != null && block.get_node_type () == Json.NodeType.OBJECT ? block.get_object () : null;
  }

  /** Whether `object` has `key` as an array; `list` is its whole numbers above zero, anything else left out. An empty int array has no "null" of its own to tell absence apart, hence the bool. */
  private static bool read_int_list (Json.Object? object, string key, out int[] list) {
    list = {};
    var node = object?.get_member (key);
    if (node == null || node.get_node_type () != Json.NodeType.ARRAY) {
      return false;
    }
    int[] found = {};
    foreach (var element in node.get_array ().get_elements ()) {
      if (element.get_node_type () == Json.NodeType.VALUE && element.get_value_type () == typeof (int64) && element.get_int () > 0) {
        found += (int) element.get_int ();
      }
    }
    list = found;
    return true;
  }

  /** `key`'s array of strings in `object`, the non-strings left out; null without an array. */
  private static string[]? read_string_list (Json.Object? object, string key) {
    var node = object?.get_member (key);
    if (node == null || node.get_node_type () != Json.NodeType.ARRAY) {
      return null;
    }
    string[] list = {};
    foreach (var element in node.get_array ().get_elements ()) {
      if (element.get_node_type () == Json.NodeType.VALUE && element.get_value_type () == typeof (string)) {
        list += element.get_string ();
      }
    }
    return list;
  }

  /** The syntax theme the editor wears, `owner/theme` (`opus-editor/github-theme`): the folder `themes/syntax/<owner>/<theme>/`, whose manifest picks the light or the dark file for the app's mode. Not in the generated settings.json yet: there is one bundled theme to choose from. */
  public string theme_syntax {
    owned get { return read_string ("theme.syntax") ?? DEFAULT_THEME_SYNTAX; }
  }

  /** VS Code's own `scm.defaultViewSortKey` ("name"/"path"/"status") — GitView.ChangeList's own sort order for the Unstaged/Staged lists. An unrecognized value (a typo, same as any other key here) falls back to "path", same as VS Code's own default. */
  public string changes_sort {
    owned get { return read_string ("git.changes_sort") ?? "path"; }
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
  "window.save_session": false,
  "editor.font_family": null,
  "editor.font_size": %d,
  "editor.font_weight": "normal",
  "editor.font_ligatures": false,
  "editor.line_height": 1,
  "editor.letter_spacing": 0,
  "editor.word_wrap": false,
  "editor.indent_style": "space",
  "editor.indent_size": 4,
  "editor.on_save": [],
  "editor.rulers": [],
  "editorconfig.max_line_length": false,
  "git.changes_sort": "path"
}
""".printf (system_monospace_font_size ());
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
