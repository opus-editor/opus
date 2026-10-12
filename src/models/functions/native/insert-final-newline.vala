namespace Functions.Native {
  /** A newline at the end of the text when its last line has content — never a second one, and nothing after a blank last line (VS Code's insertFinalNewline). */
  public class InsertFinalNewline : Object, IRunner {
    public string[] run (Input input) throws FunctionError {
      string[] output = {};
      foreach (var segment in input.segments) {
        output += with_final_newline (segment.text);
      }
      return output;
    }

    public static string with_final_newline (string text) {
      var last_line = text.substring (text.last_index_of_char ('\n') + 1);
      return last_line.strip () == "" ? text : text + "\n";
    }
  }
}
