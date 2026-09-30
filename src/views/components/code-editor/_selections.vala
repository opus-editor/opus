/**
 * Every cursor's *selection*, primary included, hand-painted here —
 * not through a `Gtk.TextTag`'s own background: GTK/Pango only paint
 * a tag's background behind glyphs a line actually lays out, and a
 * fully-selected empty line (or the trailing newline of a selected
 * non-empty one) lays out none, so the tag would apply but stay
 * invisible there. Painting every selection by hand from the raw
 * `Cursor[]` `CodeEditorCursors.render_cursors()` hands to
 * `set_selections()` sidesteps that entirely, and as a side benefit
 * draws pixel-identical boxes for every line instead of GTK's own
 * per-line background boxes, which leave a hairline gap between
 * consecutive selected lines (each one sized to that line's own font
 * ascent+descent, not the fuller line-box `get_iter_location()`
 * returns — confirmed by hand: the gap persists even with no
 * `line-height` CSS override at all, so it isn't this app's own
 * doing).
 *
 * Takes `Cursor` (`models/cursor.vala`) directly rather than a
 * View-local offset-pair type: a "selection" isn't its own concept
 * here any more than it is in VS Code's own real cursor model
 * (checked its source, common/cursor/oneCursor.ts +
 * common/cursorCommon.ts's own `SingleCursorState`) — a cursor is an
 * anchor plus a moving position, and `Cursor.selection_start`/
 * `selection_end`/`is_empty` (all plain getters over those same two
 * offsets, see that class's own doc comment) are exactly VS Code's
 * `SingleCursorState.selection`/`hasSelection()`, derived the same
 * way. Same reasoning `CodeEditorChangeGutter.set_hunks()` already has
 * for taking `GitDiff.Hunk[]` straight from `models/` instead of its
 * own gutter-local copy.
 *
 * The real, native `selection_bound`↔`insert` range still moves
 * normally for the primary cursor (copy/cut/drag/IM and every native
 * selection keybinding all still depend on it) — only its *painting*
 * is suppressed, via a CSS rule on GtkTextView's own `selection` node
 * (see `CodeEditor.install_css()`), the same kind of
 * paint-only suppression `CodeEditorSourceView`'s own
 * `cursor_visible = false` does for the caret.
 *
 * Plural, same reasoning `CodeEditorCursors` gives for its own name
 * (see its doc comment): one instance manages however many
 * selections currently exist — one per cursor — not one instance per
 * selection. Owned directly by `CodeEditorSourceView` rather than a
 * sibling `CodeEditor` composes (unlike `CodeEditorCursors`/
 * `CodeEditorSearch`/`CodeEditorChangeGutter`): painting only happens
 * from inside `CodeEditorSourceView.snapshot_layer()`'s own override,
 * which nothing outside that class can hook into.
 */
public class CodeEditorSelections : Object {
  private CodeEditorSourceView text_view;
  private Cursor[] cursors = {};
  private Gdk.RGBA color;
  private Gdk.RGBA focused_color;
  private Gdk.RGBA backdrop_color;

  public CodeEditorSelections (CodeEditorSourceView text_view) {
    this.text_view = text_view;

    // GTK's own native selection grays out whenever the window is
    // inactive (state_flags_changed fires on text_view itself; BACKDROP
    // propagates down from the toplevel window) — reproduced here for
    // the hand-painted selection the same way.
    text_view.state_flags_changed.connect ((previous_state) => update_color ());

    // Own registration, same shape VS Code's registerThemingParticipant
    // gets in viewCursors.ts (checked its source) — this class reacts to
    // the app's theme for the one color it paints with, no separate
    // "theme" object reaching in from outside.
    var style_manager = Adw.StyleManager.get_default ();
    style_manager.notify["dark"].connect (() => apply_theme_colors ());
    apply_theme_colors ();
  }

  /** The live cursor set, straight from `CodeEditorCursors.render_cursors()` — empty (`is_empty`) ones included, skipped here rather than pre-filtered by the caller. Call whenever the cursor set changes. */
  public void set_selections (Cursor[] new_cursors) {
    cursors = new_cursors;
    text_view.queue_draw ();
  }

  private void apply_theme_colors () {
    focused_color = SystemColor.from_accent ().transparentize (0.35f).to_rgba ();

    // Mirrors GTK's own ratio between its default (backdrop) and
    // :focus-within selection colors: an opaque, fully desaturated
    // color at half the alpha of the focused one.
    backdrop_color = SystemColor.from_accent ()
      .desaturate ()
      .transparentize (focused_color.alpha * 0.5f)
      .to_rgba ();

    update_color ();
  }

  private void update_color () {
    bool backdrop = (text_view.get_state_flags () & Gtk.StateFlags.BACKDROP) != 0;
    color = backdrop ? backdrop_color : focused_color;
    text_view.queue_draw ();
  }

  /**
   * One rect per visible line per selection. A line contributes
   * either:
   *  - a plain rect from its own segment's start/end pixel position
   *    (the common case: some or all of the line's real characters
   *    are selected), or
   *  - one space-wide marker at the segment's (zero-width) position,
   *    when the line itself contributes no selected characters but
   *    its own trailing newline is still part of the selection — a
   *    fully empty selected line is the main case, but a non-empty
   *    line whose selection ends exactly at its last real character
   *    (selecting on through the newline into the next line) hits
   *    the exact same zero-width case for the same reason.
   * `line < last_line` is what tells the two apart from `line ==
   * last_line`: a `Gtk.TextIter` at a line's own start position
   * always belongs to *that* line, never the previous one's end, so
   * `end_iter.get_line ()` already comes out one line further
   * whenever the selection's own end offset includes a newline.
   */
  public void draw (Gtk.Snapshot snapshot) {
    if (cursors.length == 0 || color.alpha == 0) {
      return;
    }

    var buffer = text_view.buffer;

    Gdk.Rectangle visible_rect;
    text_view.get_visible_rect (out visible_rect);

    Gtk.TextIter top_iter;
    int top_y;
    text_view.get_line_at_y (out top_iter, visible_rect.y, out top_y);
    Gtk.TextIter bottom_iter;
    int bottom_y;
    text_view.get_line_at_y (out bottom_iter, visible_rect.y + visible_rect.height, out bottom_y);

    int line_count = buffer.get_line_count ();
    int visible_first_line = top_iter.get_line ().clamp (0, line_count - 1);
    int visible_last_line = bottom_iter.get_line ().clamp (0, line_count - 1);

    float marker_width = text_view.measure_space_width ();

    foreach (var cursor in cursors) {
      if (cursor.is_empty) {
        continue;
      }

      Gtk.TextIter start_iter;
      buffer.get_iter_at_offset (out start_iter, cursor.selection_start);
      Gtk.TextIter end_iter;
      buffer.get_iter_at_offset (out end_iter, cursor.selection_end);

      int first_line = start_iter.get_line ();
      int last_line = end_iter.get_line ();

      int from_line = int.max (first_line, visible_first_line);
      int to_line = int.min (last_line, visible_last_line);

      for (int line = from_line; line <= to_line; line++) {
        bool newline_included = line < last_line;

        Gtk.TextIter segment_start = start_iter;
        if (line != first_line) {
          buffer.get_iter_at_line (out segment_start, line);
        }

        // Not `segment_end.forward_to_line_end ()`: on an empty line,
        // get_iter_at_line() already sits right on the paragraph
        // delimiter, and forward_to_line_end()'s own contract is to
        // then skip forward to the *next* line's delimiter instead
        // (checked its doc comment) — silently comparing against the
        // wrong line entirely. Stepping back one char from the next
        // line's own start lands on the same position without that
        // footgun, for an empty or non-empty line alike.
        Gtk.TextIter segment_end;
        if (line == last_line) {
          segment_end = end_iter;
        } else {
          buffer.get_iter_at_line (out segment_end, line + 1);
          segment_end.backward_char ();
        }

        Gdk.Rectangle start_rect;
        text_view.get_iter_location (segment_start, out start_rect);

        if (segment_start.equal (segment_end)) {
          if (!newline_included) {
            continue;
          }

          var marker_rect = Graphene.Rect ();
          marker_rect.init (start_rect.x, start_rect.y, marker_width, start_rect.height);
          snapshot.append_color (color, marker_rect);
          continue;
        }

        Gdk.Rectangle end_rect;
        text_view.get_iter_location (segment_end, out end_rect);

        var rect = Graphene.Rect ();
        rect.init (start_rect.x, start_rect.y, end_rect.x - start_rect.x, start_rect.height);
        snapshot.append_color (color, rect);
      }
    }
  }
}
