namespace Functions {
  public errordomain FunctionError {
    /** The script failed — the message names file and line. */
    SCRIPT,
    /** The function ran past its instruction limit. */
    TIMEOUT,
    /** Not one string back per segment in. */
    BAD_OUTPUT,
    /** The function can't work on this file: no language, or one where it would do harm. */
    UNSUPPORTED,
  }

  /**
   * What a function receives: the segments to transform (the whole
   * text as one, or each selection), plus everything around them. The
   * same for a Lua script and a native function; only the former sees
   * it as a table.
   */
  public class Input : Object {
    /** "document" or "selection". */
    public string kind { get; set; default = "document"; }
    public LuaSandbox.Segment[] segments = {};
    public string text { get; set; default = ""; }
    public LuaSandbox.Caret[] cursors = {};
    /** The document's language package name, "" with none. */
    public string language { get; set; default = ""; }
    public string path { get; set; default = ""; }
    public bool insert_spaces { get; set; default = true; }
    public int indent_size { get; set; default = 2; }

    /** The whole `text` as the one segment, for a document-scoped run. */
    public static Input of_document (string text) {
      return new Input () {
        segments = { LuaSandbox.Segment () { text = text, start = 0, end = text.char_count () } },
        text = text,
        cursors = {},
      };
    }

    public LuaSandbox.TransformInput to_transform_input () {
      return LuaSandbox.TransformInput () {
        kind = kind, segments = segments, text = text, cursors = cursors, language = language, path = path,
      };
    }
  }

  /** What runs a function: a Lua script, or Vala code for the ones that need the syntax model. */
  public interface IRunner : Object {
    /** One string per segment of `input`, in order. */
    public abstract string[] run (Input input) throws FunctionError;
  }

  /** One entry of the `|` list, from a package or the native catalog. */
  public class Function : Object {
    public string id { get; private set; }
    public string name { get; private set; }
    public string description { get; private set; }
    public Scope input { get; private set; }
    public string[] languages { get; private set; }
    public IRunner runner { get; private set; }

    public Function (string id, string name, string description, Scope input, string[] languages, IRunner runner) {
      this.id = id;
      this.name = name;
      this.description = description;
      this.input = input;
      this.languages = languages;
      this.runner = runner;
    }

    /** Listed for `language` (a package name, or null for a file with none) — always, with no `languages` of its own. */
    public bool applies_to (string? language) {
      return languages.length == 0 || (language != null && language in languages);
    }
  }
}
