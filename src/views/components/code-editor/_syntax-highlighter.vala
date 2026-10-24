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
 *
 * Parsing is done a few milliseconds at a time. An edit to an ordinary
 * file finishes inside the first slice; opening a file of several
 * megabytes takes many, with the window answering in between and the
 * text painted from the previous parse until the new one is done.
 */
public class CodeEditorSyntaxHighlighter : Object {
  // Enough that an ordinary scroll step lands on text already painted.
  private const int MARGIN_ROWS = 40;
  private const int NONE = -1;
  // Short enough to fit, with painting, in the 16 ms of one frame.
  private const int64 PARSE_SLICE_USEC = 5000;
  // Between GTK's redraw (HIGH_IDLE + 20) and Gtk.TextView measuring
  // the lines of a freshly loaded buffer (HIGH_IDLE + 25): the window
  // is drawn and answers input ahead of a slice, but a large file's
  // measuring, which goes on for seconds, doesn't hold parsing up.
  private const int PARSE_PRIORITY = Priority.HIGH_IDLE + 22;

  private Gtk.TextView text_view;
  private Gtk.TextBuffer buffer;
  private SyntaxTags tags;
  private Syntax.SyntaxDocument? document;
  private bool text_stale = false;
  // A parse ran out of its slice and has to be carried on.
  private bool parsing = false;
  // The one contiguous run of rows whose tags match the current text.
  private int painted_first = NONE;
  private int painted_last = NONE;
  // The idle a long parse goes on in, and the tick callback a repaint waits for.
  private uint refresh_id = 0;
  private uint tick_id = 0;

  public CodeEditorSyntaxHighlighter (GtkSource.View text_view, Gtk.Adjustment vadjustment) {
    this.text_view = text_view;
    buffer = text_view.buffer;
    tags = new SyntaxTags (buffer);
    tags.repaint_needed.connect (() => {
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

  /** See CodeEditor.close(). */
  public void close () {
    tags.close ();
    if (refresh_id != 0) {
      Source.remove (refresh_id);
      refresh_id = 0;
    }
    if (tick_id != 0) {
      text_view.remove_tick_callback (tick_id);
      tick_id = 0;
    }
  }

  /** What the buffer's text is written in — null for none, which leaves it unpainted. Takes effect on the text the buffer holds at the next frame, so it can be called right before loading a new one; on a view not realized yet, right away. */
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

  /** How many indent levels a line broken off at character `offset` should have beyond the line it is broken from — 0 with no language, or while a large file is still being parsed. */
  public int new_line_indent_change (int offset) {
    return trees_are_current () ? document.new_line_indent_change (offset) : 0;
  }

  /** Whether the line `offset` is on now starts with something that closes a block, and how many `levels` it should then have beyond the line `reference_offset` is on. */
  public bool outdent_change (int offset, int reference_offset, out int levels) {
    levels = 0;
    return trees_are_current () && document.outdent_change (offset, reference_offset, out levels);
  }

  /** Whether the text's language has a way to list symbols at all. */
  public bool lists_symbols {
    get { return document != null && document.lists_symbols; }
  }

  /** The definitions in the text as it is now. False while a huge file is still being read: they aren't known yet. */
  public bool symbols (out Syntax.Symbol[] symbols) {
    symbols = {};
    if (!trees_are_current ()) {
      return false;
    }
    symbols = document.symbols ();
    return true;
  }

  /** Brings the document up to the buffer's text if a slice is enough for that — an edit to anything but a huge file — and says whether it got there. */
  private bool trees_are_current () {
    if (document == null) {
      return false;
    }
    if (text_stale) {
      parse_changed_text ();
    }
    return !parsing;
  }

  private void parse_changed_text () {
    parsing = !document.set_text (buffer.text, PARSE_SLICE_USEC);
    text_stale = false;
    painted_first = NONE;
    painted_last = NONE;
  }

  /** The style key painted at `offset`, or "" where nothing is. */
  public string style_key_at (int offset) {
    Gtk.TextIter iter;
    buffer.get_iter_at_offset (out iter, offset);
    return tags.style_key_at (iter) ?? "";
  }

  /**
   * Before GTK next paints the view, in the same frame: a tick
   * callback, which the frame clock runs in its update phase, ahead of
   * layout and paint. An idle wouldn't do, whatever its priority: a
   * click or a keystroke is delivered inside the frame clock's own
   * cycle, which goes on to lay out and paint without returning to the
   * main loop, so an idle set from its handler only runs after that
   * frame — the text drawn once in the wrong colors, then again in the
   * right ones. A view not realized yet has no frame to wait for and
   * is painted right away, at its top (see rows_to_show).
   */
  private void schedule_refresh () {
    if (tick_id != 0) {
      return;
    }
    if (!text_view.get_realized ()) {
      refresh_now ();
      return;
    }
    tick_id = text_view.add_tick_callback (() => {
      tick_id = 0;
      refresh_now ();
      return false;
    });
  }

  private bool refresh () {
    refresh_id = 0;
    refresh_now ();
    return Source.REMOVE;
  }

  private void refresh_now () {
    if (document == null) {
      return;
    }

    bool was_parsing = parsing;
    if (text_stale) {
      parse_changed_text ();
    } else if (parsing) {
      parsing = !document.resume (PARSE_SLICE_USEC);
      if (!parsing) {
        // What is on screen was painted from the previous parse.
        painted_first = NONE;
        painted_last = NONE;
      }
    }

    // While a parse is still going, nothing new can be said about the
    // text: what the previous trees give is painted once, not once a
    // slice.
    if (!(parsing && was_parsing)) {
      int first;
      int last;
      rows_to_show (out first, out last);
      paint_missing (first, last);
    }
    if (parsing) {
      continue_parsing ();
    }
  }

  /** Behind GTK's own redraw and input handling, unlike schedule_refresh(): the point of slicing is that the window gets a turn between slices. */
  private void continue_parsing () {
    if (refresh_id == 0) {
      refresh_id = Idle.add_full (PARSE_PRIORITY, refresh);
    }
  }

  /**
   * Before the view's first allocation — a tab just opened, its first
   * frame not drawn yet — the visible rect means nothing, and GTK draws
   * that frame right after laying out, with no turn for this idle in
   * between: the top of the text is painted on the guess that this is
   * where the view opens, so the first frame already has its colors.
   */
  private void rows_to_show (out int first, out int last) {
    int last_row = buffer.get_line_count () - 1;
    if (text_view.get_height () == 0) {
      first = 0;
      last = int.min (last_row, MARGIN_ROWS * 3);
      return;
    }
    Gdk.Rectangle visible;
    text_view.get_visible_rect (out visible);
    Gtk.TextIter top;
    Gtk.TextIter bottom;
    text_view.get_line_at_y (out top, visible.y, null);
    text_view.get_line_at_y (out bottom, visible.y + visible.height, null);
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
      var tag = tags.tag_for (span.capture, span.language);
      Gtk.TextIter span_start;
      Gtk.TextIter span_end;
      buffer.get_iter_at_line_index (out span_start, (int) span.start_row, (int) span.start_column);
      buffer.get_iter_at_line_index (out span_end, (int) span.end_row, (int) span.end_column);
      buffer.apply_tag (tag, span_start, span_end);
    }
  }
}
