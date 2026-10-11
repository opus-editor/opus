namespace GitDiff {
  /** One `<<<<<<<` … `>>>>>>>` block, in 0-based buffer lines. The content ranges exclude the marker lines; an empty range has `end < start`. */
  public class Conflict : Object {
    /** The `<<<<<<<` line. */
    public int start_line { get; construct; }
    /** The `|||||||` line (diff3 style), -1 without one. */
    public int base_line { get; construct; }
    /** The `=======` line. */
    public int splitter_line { get; construct; }
    /** The `>>>>>>>` line. */
    public int end_line { get; construct; }
    /** What follows `<<<<<<< ` — "HEAD", a branch. */
    public string current_label { get; construct; }
    /** What follows `>>>>>>> `. */
    public string incoming_label { get; construct; }

    public Conflict (int start_line, int base_line, int splitter_line, int end_line, string current_label, string incoming_label) {
      Object (start_line: start_line, base_line: base_line, splitter_line: splitter_line, end_line: end_line, current_label: current_label, incoming_label: incoming_label);
    }

    public int current_first { get { return start_line + 1; } }
    public int current_last { get { return (base_line >= 0 ? base_line : splitter_line) - 1; } }
    public int incoming_first { get { return splitter_line + 1; } }
    public int incoming_last { get { return end_line - 1; } }
  }

  /**
   * Finds git's conflict markers in a text — the same line-by-line rules
   * as VS Code's merge-conflict extension (mergeConflictParser.ts):
   * `<<<<<<<` opens, `|||||||` is the optional common ancestor, exactly
   * `=======` splits, `>>>>>>>` closes. A block missing its close by the
   * end, or cut off by a new `<<<<<<<`, is dropped; a `=======` inside a
   * block that already has its splitter is plain content.
   */
  public class ConflictParser : Object {
    private const string START = "<<<<<<<";
    private const string BASE = "|||||||";
    private const string SPLITTER = "=======";
    private const string END = ">>>>>>>";

    public static GenericArray<Conflict> parse (string text) {
      var found = new GenericArray<Conflict> ();
      int start = -1;
      int base_line = -1;
      int splitter = -1;
      string current_label = "";
      var lines = text.split ("\n");
      for (int i = 0; i < lines.length; i++) {
        var line = lines[i].has_suffix ("\r") ? lines[i].substring (0, lines[i].length - 1) : lines[i];
        if (line.has_prefix (START)) {
          start = i;
          base_line = -1;
          splitter = -1;
          current_label = line.substring (START.length).strip ();
        } else if (start >= 0 && splitter < 0 && line.has_prefix (BASE)) {
          base_line = i;
        } else if (start >= 0 && splitter < 0 && line == SPLITTER) {
          splitter = i;
        } else if (start >= 0 && splitter >= 0 && line.has_prefix (END)) {
          found.add (new Conflict (start, base_line, splitter, i, current_label, line.substring (END.length).strip ()));
          start = -1;
        }
      }
      return found;
    }

    public static bool contains_conflict (string text) {
      return parse (text).length > 0;
    }
  }
}
