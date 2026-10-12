/**
 * A theme folder's `theme.json`: the name shown for it and which file
 * holds each variant. The same shape for a syntax theme
 * (`themes/syntax/<owner>/<theme>/`) and a UI theme (`themes/ui/<id>/`);
 * a folder may carry only one variant. `owner/theme` is the theme's id —
 * what settings.json names.
 */
public class ThemeManifest : Object {
  public const string FILE = "theme.json";

  public string directory { get; private set; }
  public string id { get; private set; }
  public string name { get; private set; }
  /** Full paths; null for a variant the theme doesn't have. */
  public string? light { get; private set; }
  public string? dark { get; private set; }

  public static ThemeManifest load (string directory) throws ThemeError {
    var path = Path.build_filename (directory, FILE);
    string json;
    try {
      FileUtils.get_contents (path, out json);
    } catch (FileError e) {
      throw new ThemeError.INVALID ("%s: %s", path, e.message);
    }
    return parse (directory, json);
  }

  /** Split out from {@link load} so a manifest can be tested as plain text. */
  public static ThemeManifest parse (string directory, string json) throws ThemeError {
    var parser = new Json.Parser ();
    try {
      parser.load_from_data (json);
    } catch (Error e) {
      throw new ThemeError.INVALID ("%s: not valid JSON: %s", Path.build_filename (directory, FILE), e.message);
    }
    var root = parser.get_root ();
    if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
      throw new ThemeError.INVALID ("%s: the manifest must be a JSON object", Path.build_filename (directory, FILE));
    }
    var object = root.get_object ();

    var manifest = new ThemeManifest ();
    manifest.directory = directory;
    manifest.id = Path.build_filename (Path.get_basename (Path.get_dirname (directory)), Path.get_basename (directory));
    manifest.name = optional_string (directory, object, "name") ?? Path.get_basename (directory);
    manifest.light = file_of (directory, object, "light");
    manifest.dark = file_of (directory, object, "dark");
    if (manifest.light == null && manifest.dark == null) {
      throw new ThemeError.INVALID ("%s: a theme needs a \"light\" or a \"dark\" file", Path.build_filename (directory, FILE));
    }
    return manifest;
  }

  /** The file for the mode, null when the theme has no such variant. */
  public string? file_for (bool dark) {
    return dark ? this.dark : light;
  }

  private static string? file_of (string directory, Json.Object object, string key) throws ThemeError {
    var name = optional_string (directory, object, key);
    return name == null ? null : Path.build_filename (directory, name);
  }

  private static string? optional_string (string directory, Json.Object object, string key) throws ThemeError {
    if (!object.has_member (key)) {
      return null;
    }
    var node = object.get_member (key);
    if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (string)) {
      throw new ThemeError.INVALID ("%s: \"%s\" must be a string", Path.build_filename (directory, FILE), key);
    }
    return node.get_string ();
  }
}
