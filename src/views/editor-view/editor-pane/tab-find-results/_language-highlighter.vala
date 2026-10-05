namespace EditorView.EditorPane {
  /**
   * Paints one file's own language syntax highlighting onto a range of
   * TabFindResults' results buffer. Each block of result lines is
   * parsed on its own, as if it were the whole file: tree-sitter
   * recovers from the cut-off start and end well enough to color what
   * is there, though a block that opens in the middle of a string or
   * a comment can't know it.
   */
  public class TabFindResultsLanguageHighlighter : Object {
    private GtkSource.Buffer target;
    private SyntaxTags tags;

    public TabFindResultsLanguageHighlighter (GtkSource.Buffer target) {
      this.target = target;
      tags = new SyntaxTags (target);
    }

    /**
     * Paints `snippet` (one block's own lines joined with "\n", no
     * gutter prefix) as `path`'s own language, onto `target` at the
     * offsets `line_start_offsets` gives — `line_start_offsets[i]` is
     * where snippet line `i`'s own content begins in `target`. A
     * no-op when no language package claims `path`.
     */
    public void highlight (string path, string snippet, int[] line_start_offsets) {
      var language = Syntax.Languages.instance.detect (path);
      if (language == null || line_start_offsets.length == 0) {
        return;
      }

      var document = new Syntax.SyntaxDocument (language, Syntax.Languages.instance);
      document.set_text (snippet);
      foreach (var span in document.highlights (0, line_start_offsets.length - 1)) {
        paint (span, line_start_offsets);
      }
    }

    /**
     * One line at a time: the "  N: " gutter prefix sits between
     * consecutive lines in `target`, so a span covering several
     * snippet lines painted as one range would run straight through
     * it.
     */
    private void paint (Syntax.HighlightSpan span, int[] line_start_offsets) {
      var tag = tags.tag_for (span.style);
      if (tag == null) {
        return;
      }
      for (uint32 row = span.start_row; row <= span.end_row && row < line_start_offsets.length; row++) {
        Gtk.TextIter line_start;
        target.get_iter_at_offset (out line_start, line_start_offsets[row]);

        var start = line_start;
        if (row == span.start_row) {
          start.set_line_index (line_start.get_line_index () + (int) span.start_column);
        }
        var end = line_start;
        if (row == span.end_row) {
          end.set_line_index (line_start.get_line_index () + (int) span.end_column);
        } else if (!end.ends_line ()) {
          end.forward_to_line_end ();
        }
        target.apply_tag (tag, start, end);
      }
    }
  }
}
