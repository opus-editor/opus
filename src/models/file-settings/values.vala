namespace FileSettings {
  /** What a provider has to say about one file — a null field is nothing to say, and the host's own default stands. */
  public class Values : Object {
    public int? indent_size = null;
    /** How wide a literal tab renders; defaults to the indent size when nothing says. */
    public int? tab_width = null;
    public bool? insert_spaces = null;
    public Document.LineEnding? line_ending = null;
    public bool? trim_trailing_whitespace = null;
    public bool? insert_final_newline = null;
    public Document.Charset? charset = null;
    /** The longest line the project wants, in columns; nothing for `off`. */
    public int? max_line_length = null;

    /** Every field `other` sets, taken over this one's. */
    public void take (Values other) {
      if (other.indent_size != null) {
        indent_size = other.indent_size;
      }
      if (other.tab_width != null) {
        tab_width = other.tab_width;
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
      if (other.max_line_length != null) {
        max_line_length = other.max_line_length;
      }
    }
  }
}
