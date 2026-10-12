namespace Functions {
  public errordomain ManifestError {
    UNREADABLE,
    INVALID,
  }

  /** What a function takes: the whole document, the selections, or either — the selections when there are any. */
  public enum Scope {
    DOCUMENT,
    SELECTION,
    BOTH;

    public static Scope parse (string value) throws ManifestError {
      switch (value) {
        case "document": return DOCUMENT;
        case "selection": return SELECTION;
        case "both": return BOTH;
        default: throw new ManifestError.INVALID ("\"input\" must be \"document\", \"selection\" or \"both\", not \"%s\"", value);
      }
    }
  }

  /**
   * A function package's `function.json`: what the `|` list shows and
   * which script runs. The folder's name is the id — what another
   * folder of the same name overrides.
   */
  public class Manifest : Object {
    public const string FILE = "function.json";

    public string directory { get; private set; }
    public string id { get; private set; }
    public string name { get; private set; }
    public string description { get; private set; default = ""; }
    /** The script, as a full path. */
    public string entry { get; private set; }
    public Scope input { get; private set; default = Scope.BOTH; }
    /** Package names of the languages it is listed for; empty for every file. */
    public string[] languages { get; private set; }

    public static Manifest load (string directory) throws ManifestError {
      var path = Path.build_filename (directory, FILE);
      string json;
      try {
        FileUtils.get_contents (path, out json);
      } catch (FileError e) {
        throw new ManifestError.UNREADABLE ("%s: %s", path, e.message);
      }
      return parse (directory, json);
    }

    /** Split out from {@link load} so a manifest can be tested as plain text. */
    public static Manifest parse (string directory, string json) throws ManifestError {
      var parser = new Json.Parser ();
      try {
        parser.load_from_data (json);
      } catch (Error e) {
        throw new ManifestError.INVALID ("not valid JSON: %s", e.message);
      }
      var root = parser.get_root ();
      if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
        throw new ManifestError.INVALID ("the manifest must be a JSON object");
      }
      var object = root.get_object ();

      var manifest = new Manifest ();
      manifest.directory = directory;
      manifest.id = Path.get_basename (directory);
      manifest.name = required_string (object, "name");
      manifest.description = optional_string (object, "description") ?? "";
      manifest.entry = Path.build_filename (directory, optional_string (object, "entry") ?? "main.lua");
      var type = optional_string (object, "type") ?? "transform";
      if (type != "transform") {
        throw new ManifestError.INVALID ("\"type\" must be \"transform\", not \"%s\"", type);
      }
      manifest.input = Scope.parse (optional_string (object, "input") ?? "both");
      manifest.languages = string_array (object, "languages");
      return manifest;
    }

    private static string required_string (Json.Object object, string key) throws ManifestError {
      var value = optional_string (object, key);
      if (value == null || value == "") {
        throw new ManifestError.INVALID ("\"%s\" is required", key);
      }
      return value;
    }

    private static string? optional_string (Json.Object object, string key) throws ManifestError {
      if (!object.has_member (key)) {
        return null;
      }
      var node = object.get_member (key);
      if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (string)) {
        throw new ManifestError.INVALID ("\"%s\" must be a string", key);
      }
      return node.get_string ();
    }

    private static string[] string_array (Json.Object object, string key) throws ManifestError {
      string[] values = {};
      if (!object.has_member (key)) {
        return values;
      }
      var node = object.get_member (key);
      if (node.get_node_type () != Json.NodeType.ARRAY) {
        throw new ManifestError.INVALID ("\"%s\" must be an array of strings", key);
      }
      foreach (var element in node.get_array ().get_elements ()) {
        if (element.get_node_type () != Json.NodeType.VALUE || element.get_value_type () != typeof (string)) {
          throw new ManifestError.INVALID ("\"%s\" must be an array of strings", key);
        }
        values += element.get_string ();
      }
      return values;
    }
  }
}
