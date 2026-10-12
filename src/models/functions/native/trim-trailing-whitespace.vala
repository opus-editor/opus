namespace Functions.Native {
  /**
   * The blanks at the end of every line, gone. A line a cursor is on
   * keeps what lies before the cursor — VS Code's trimTrailingWhitespace
   * rule, for the command run mid-typing; the save runs it with no
   * cursors and clears everything.
   */
  public class TrimTrailingWhitespace : Object, IRunner {
    public string[] run (Input input) throws FunctionError {
      string[] output = {};
      foreach (var segment in input.segments) {
        output += trimmed (segment, input.cursors);
      }
      return output;
    }

    public static string trimmed (LuaSandbox.Segment segment, LuaSandbox.Caret[] cursors) {
      var result = new StringBuilder ();
      int line_start = segment.start;
      var lines = segment.text.split ("\n");
      for (int i = 0; i < lines.length; i++) {
        if (i > 0) {
          result.append_c ('\n');
        }
        int length = lines[i].char_count ();
        int keep = content_length (lines[i]);
        foreach (var cursor in cursors) {
          if (cursor.position >= line_start && cursor.position <= line_start + length) {
            keep = int.max (keep, cursor.position - line_start);
          }
        }
        result.append (lines[i].substring (0, lines[i].index_of_nth_char (keep)));
        line_start += length + 1;
      }
      return result.str;
    }

    /** How many characters of `line` remain once its trailing blanks go. */
    private static int content_length (string line) {
      int keep = 0;
      int index = 0;
      int seen = 0;
      unichar c;
      while (line.get_next_char (ref index, out c)) {
        seen++;
        if (!c.isspace ()) {
          keep = seen;
        }
      }
      return keep;
    }
  }
}
