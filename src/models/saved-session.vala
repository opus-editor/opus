public errordomain SessionError {
  INVALID,
}

/** One file tab of a saved session: the file, and how it was being looked at. */
public class SessionTab : Object {
  public string path { get; private set; }
  /** The primary cursor: 1-based line, 0-based column in characters. */
  public int line { get; private set; }
  public int column { get; private set; }
  /** The first line showing, 1-based. */
  public int top_line { get; private set; }
  public bool preview { get; private set; }

  public SessionTab (string path, int line, int column, int top_line, bool preview) {
    this.path = path;
    this.line = line;
    this.column = column;
    this.top_line = top_line;
    this.preview = preview;
  }
}

/**
 * What `window.save_session` brings back: the folder a window had
 * linked, its file tabs in the order of the tab bar, and which was
 * active. Written and read as JSON; SessionStore says where.
 */
public class SavedSession : Object {
  public string folder { get; private set; }
  /** The active tab's path, or null when none of the tabs was. */
  public string? active { get; private set; }
  public GenericArray<SessionTab> tabs { get; private set; }

  public SavedSession (string folder, GenericArray<SessionTab> tabs, string? active) {
    this.folder = folder;
    this.tabs = tabs;
    this.active = active;
  }

  public string to_json () {
    var builder = new Json.Builder ();
    builder.begin_object ();
    builder.set_member_name ("folder").add_string_value (folder);
    if (active != null) {
      builder.set_member_name ("active").add_string_value (active);
    }
    builder.set_member_name ("tabs").begin_array ();
    foreach (var tab in tabs) {
      builder.begin_object ();
      builder.set_member_name ("path").add_string_value (tab.path);
      builder.set_member_name ("line").add_int_value (tab.line);
      builder.set_member_name ("column").add_int_value (tab.column);
      builder.set_member_name ("top_line").add_int_value (tab.top_line);
      if (tab.preview) {
        builder.set_member_name ("preview").add_boolean_value (true);
      }
      builder.end_object ();
    }
    builder.end_array ();
    builder.end_object ();

    var generator = new Json.Generator ();
    generator.root = builder.get_root ();
    generator.pretty = true;
    generator.indent = 2;
    return generator.to_data (null) + "\n";
  }

  /** The session `json` describes. A tab out of shape is an error; what is missing on disk is dealt with by {@link restorable}. */
  public static SavedSession parse (string json) throws SessionError {
    var parser = new Json.Parser ();
    try {
      parser.load_from_data (json);
    } catch (Error e) {
      throw new SessionError.INVALID ("not valid JSON: %s", e.message);
    }
    var root = parser.get_root ();
    if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
      throw new SessionError.INVALID ("the session must be a JSON object");
    }
    var object = root.get_object ();

    var folder = string_member (object, "folder", "");
    if (folder == null) {
      throw new SessionError.INVALID ("\"folder\" must be a string");
    }
    var active = object.has_member ("active") ? string_member (object, "active", "") : null;
    var tabs = new GenericArray<SessionTab> ();
    if (object.has_member ("tabs")) {
      var node = object.get_member ("tabs");
      if (node.get_node_type () != Json.NodeType.ARRAY) {
        throw new SessionError.INVALID ("\"tabs\" must be an array");
      }
      var array = node.get_array ();
      for (uint i = 0; i < array.get_length (); i++) {
        tabs.add (tab_of (array.get_element (i), "tabs[%u]".printf (i)));
      }
    }
    return new SavedSession (folder, tabs, active);
  }

  private static SessionTab tab_of (Json.Node node, string where) throws SessionError {
    if (node.get_node_type () != Json.NodeType.OBJECT) {
      throw new SessionError.INVALID ("%s must be an object", where);
    }
    var object = node.get_object ();
    var path = string_member (object, "path", where + ".");
    if (path == null) {
      throw new SessionError.INVALID ("%s.path must be a string", where);
    }
    return new SessionTab (
      path,
      int.max (1, int_member (object, "line", 1, where)),
      int.max (0, int_member (object, "column", 0, where)),
      int.max (1, int_member (object, "top_line", 1, where)),
      bool_member (object, "preview", where)
    );
  }

  /** Null when absent or not a string. */
  private static string? string_member (Json.Object object, string key, string where) {
    if (!object.has_member (key)) {
      return null;
    }
    var node = object.get_member (key);
    if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (string)) {
      return null;
    }
    return node.get_string ();
  }

  private static int int_member (Json.Object object, string key, int fallback, string where) throws SessionError {
    if (!object.has_member (key)) {
      return fallback;
    }
    var node = object.get_member (key);
    if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (int64)) {
      throw new SessionError.INVALID ("%s.%s must be a whole number", where, key);
    }
    return (int) node.get_int ();
  }

  private static bool bool_member (Json.Object object, string key, string where) throws SessionError {
    if (!object.has_member (key)) {
      return false;
    }
    var node = object.get_member (key);
    if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (bool)) {
      throw new SessionError.INVALID ("%s.%s must be true or false", where, key);
    }
    return node.get_boolean ();
  }

  /**
   * This session as it can be brought back now: without the tabs whose
   * files are gone, and with no active tab if that was one of them.
   * Null when the folder itself is gone — there is nothing to restore.
   */
  public SavedSession? restorable () {
    if (!FileUtils.test (folder, FileTest.IS_DIR)) {
      return null;
    }
    var kept = new GenericArray<SessionTab> ();
    string? kept_active = null;
    foreach (var tab in tabs) {
      if (!FileUtils.test (tab.path, FileTest.IS_REGULAR)) {
        continue;
      }
      kept.add (tab);
      if (tab.path == active) {
        kept_active = active;
      }
    }
    return new SavedSession (folder, kept, kept_active);
  }
}
