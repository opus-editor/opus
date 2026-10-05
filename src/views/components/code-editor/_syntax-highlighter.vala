/**
 * Keeps the buffer's syntax highlighting current: holds the
 * Syntax.SyntaxDocument for whatever language the editor is showing,
 * feeds it the text whenever the buffer changes, and paints the spans
 * it answers with as SyntaxTags.
 *
 * Only the rows on screen (plus a margin) are ever painted. A buffer
 * change repaints them and forgets everything else; scrolling paints
 * what comes into view. Tags left on rows nobody is looking at are
 * stale until then, which costs nothing — they're repainted before
 * they can be seen.
 */
public class CodeEditorSyntaxHighlighter : Object {
  // Enough that an ordinary scroll step lands on text already painted.
  private const int MARGIN_ROWS = 40;
  private const int NONE = -1;

  private Gtk.TextView text_view;
  private Gtk.TextBuffer buffer;
  private SyntaxTags tags;
  private Syntax.SyntaxDocument? document;
  private bool text_stale = false;
  // The one contiguous run of rows whose tags match the current text.
  private int painted_first = NONE;
  private int painted_last = NONE;
  private uint refresh_id = 0;

  public CodeEditorSyntaxHighlighter (GtkSource.View text_view, Gtk.Adjustment vadjustment) {
    this.text_view = text_view;
    buffer = text_view.buffer;
    tags = new SyntaxTags (buffer);
    tags.restyled.connect (() => {
      painted_first = NONE;
      painted_last = NONE;
      schedule_refresh ();
    });

    buffer.changed.connect (() => {
      text_stale = true;
      schedule_refresh ();
    });
    vadjustment.value_changed.connect (schedule_refresh);
    // Its page size: the first allocation, and every resize after.
    vadjustment.changed.connect (schedule_refresh);
  }

  /** What the buffer's text is written in — null for none, which leaves it unpainted. Takes effect on the text the buffer holds once this main-loop turn is over, so it can be called right before loading a new one. */
  public void set_language (Syntax.LoadedLanguage? language) {
    document = language == null ? null : new Syntax.SyntaxDocument (language, Syntax.Languages.instance);
    text_stale = true;
    painted_first = NONE;
    painted_last = NONE;
    if (language == null) {
      unpaint ();
    }
    schedule_refresh ();
  }

  private void unpaint () {
    Gtk.TextIter start;
    Gtk.TextIter end;
    buffer.get_bounds (out start, out end);
    tags.clear (start, end);
  }

  /** The style key painted at `offset`, or "" where nothing is. */
  public string style_key_at (int offset) {
    Gtk.TextIter iter;
    buffer.get_iter_at_offset (out iter, offset);
    return tags.style_key_at (iter) ?? "";
  }

  /**
   * Ahead of GTK's own layout and redraw in the same main-loop turn,
   * so a keystroke is never drawn once in the wrong color and again
   * in the right one.
   */
  private void schedule_refresh () {
    if (refresh_id == 0) {
      refresh_id = Idle.add_full (Priority.HIGH_IDLE, refresh);
    }
  }

  private bool refresh () {
    refresh_id = 0;
    if (document == null) {
      return Source.REMOVE;
    }

    if (text_stale) {
      document.set_text (buffer.text);
      text_stale = false;
      painted_first = NONE;
      painted_last = NONE;
    }

    int first;
    int last;
    rows_to_show (out first, out last);
    paint_missing (first, last);
    return Source.REMOVE;
  }

  private void rows_to_show (out int first, out int last) {
    Gdk.Rectangle visible;
    text_view.get_visible_rect (out visible);
    Gtk.TextIter top;
    Gtk.TextIter bottom;
    text_view.get_line_at_y (out top, visible.y, null);
    text_view.get_line_at_y (out bottom, visible.y + visible.height, null);

    int last_row = buffer.get_line_count () - 1;
    first = int.max (0, top.get_line () - MARGIN_ROWS);
    last = int.min (last_row, bottom.get_line () + MARGIN_ROWS);
  }

  /** Paints the rows of `first`..`last` that aren't painted yet, growing the painted run — or starting it over when the two don't touch. */
  private void paint_missing (int first, int last) {
    bool apart = painted_first == NONE || first > painted_last + 1 || last < painted_first - 1;
    bool around = first < painted_first && last > painted_last;
    if (apart || around) {
      paint (first, last);
      painted_first = first;
      painted_last = last;
      return;
    }

    if (first < painted_first) {
      paint (first, painted_first - 1);
      painted_first = first;
    }
    if (last > painted_last) {
      paint (painted_last + 1, last);
      painted_last = last;
    }
  }

  private void paint (int first, int last) {
    Gtk.TextIter start;
    Gtk.TextIter end;
    buffer.get_iter_at_line (out start, first);
    if (last + 1 < buffer.get_line_count ()) {
      buffer.get_iter_at_line (out end, last + 1);
    } else {
      buffer.get_end_iter (out end);
    }
    tags.clear (start, end);

    foreach (var span in document.highlights (first, last)) {
      var tag = tags.tag_for (span.style);
      if (tag == null) {
        continue;
      }
      Gtk.TextIter span_start;
      Gtk.TextIter span_end;
      buffer.get_iter_at_line_index (out span_start, (int) span.start_row, (int) span.start_column);
      buffer.get_iter_at_line_index (out span_end, (int) span.end_row, (int) span.end_column);
      buffer.apply_tag (tag, span_start, span_end);
    }
  }
}
