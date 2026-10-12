namespace FileSettings {
  /** What a provider has to say about one file — a null field is nothing to say, and the host's own default stands. */
  public class Values : Object {
    public int? indent_size = null;
    public bool? insert_spaces = null;
    public Document.LineEnding? line_ending = null;
    public bool? trim_trailing_whitespace = null;
    public bool? insert_final_newline = null;
    public Document.Charset? charset = null;

    /** Every field `other` sets, taken over this one's. */
    public void take (Values other) {
      if (other.indent_size != null) {
        indent_size = other.indent_size;
      }
      if (other.insert_spaces != null) {
        insert_spaces = other.insert_spaces;
      }
      if (other.line_ending != null) {
        line_ending = other.line_ending;
      }
      if (other.trim_trailing_whitespace != null) {
        trim_trailing_whitespace = other.trim_trailing_whitespace;
      }
      if (other.insert_final_newline != null) {
        insert_final_newline = other.insert_final_newline;
      }
      if (other.charset != null) {
        charset = other.charset;
      }
    }
  }
}
