/**
 * The real GTK-backed text widget {@link CodeEditor} wraps: a
 * `GtkSource.View` subclass that hand-draws every cursor's caret itself —
 * primary included — instead of splitting the work between GTK's native
 * caret and custom-drawn secondary ones.
 *
 * `CodeEditor` sets `cursor_visible = false` on this view, which
 * suppresses only the native caret's *painting* — the real `insert`/
 * `selection_bound` marks it wraps still move normally, so IM
 * composition, bracket-matching and accessibility all keep working
 * unaffected. Scroll-to-cursor does *not*: that one lives in GTK's own
 * native keybinding handlers (gtk_text_view_move_cursor() and friends,
 * each ending in scroll_mark_onscreen()), which CodeEditorInput's own
 * CAPTURE-phase key controller stops from ever running for a claimed
 * key — see reveal_iter()'s own doc comment for the replacement.
 *
 * Every caret users actually see, including the primary one, is painted
 * here through the same code path, with the same color and the same
 * blink timer, so they're guaranteed identical — matching VS Code's own
 * default multi-cursor appearance (`editorMultiCursor.primary.foreground`/
 * `.secondary.foreground` both default to the same `editorCursor.
 * foreground`) rather than trying to approximate it from two different
 * rendering systems.
 *
 * Every cursor's *selection*, primary included, is hand-painted the same
 * way as the carets above — see CodeEditorSelections' own doc comment
 * (_selections.vala) for why, and why that's its own class rather than
 * more private state/methods on this one: it needs nothing from this
 * class beyond the same plain pixel queries CodeEditorCursors/
 * CodeEditorSearch already call on it as a sibling sub-component.
 *
 * The real, native `selection_bound`↔`insert` range still moves normally
 * for the primary cursor (copy/cut/drag/IM and every native selection
 * keybinding all still depend on it) — only its *painting* is
 * suppressed, via a CSS rule on GtkTextView's own `selection` node (see
 * `CodeEditor.install_css()`), the same kind of paint-only
 * suppression `cursor_visible = false` already does for the caret above.
 */
/** reveal_iter()'s own vertical behavior — mirrors VS Code's VerticalRevealType (viewLines.ts), the parameter over one real `_revealPosition`-equivalent rather than a family of near-duplicate methods. */
public enum RevealMode {
  /** Scroll only if the line is above or below the viewport, by the minimum needed, with one extra line of padding below so the last line never sits right under the scrollbar — ordinary typing and cursor movement (CodeEditorCursors.reveal_cursors()). */
  SIMPLE,
  /** No-op if the line is already inside the viewport; otherwise center it — a jump to a wholly different position (CodeEditor.reveal_offset(), Find Results). */
  CENTER_IF_OUTSIDE,
}

public class CodeEditorSourceView : GtkSource.View, IDisplayRows {
  // Matches VS Code's own default (ViewCursors.BLINK_INTERVAL in
  // src/vs/editor/browser/viewParts/viewCursors/viewCursors.ts) — a
  // plain on/off toggle, not the smooth/phase/expand fade styles VS
  // Code also offers as alternatives to its "blink" default.
  private const uint BLINK_INTERVAL_MS = 500;

  // How far past the visible range indent guides look for
  // interpolation context (see draw_indent_guides()) — a blank run
  // of lines taller than this just loses its guide past the edge,
  // same as IndentGuides already treats the real top/bottom of a file.
  private const int INDENT_GUIDE_CONTEXT_LINES = 300;
  private const float INDENT_GUIDE_ALPHA = 0.075f;
  private const float ACTIVE_INDENT_GUIDE_ALPHA = 0.15f;

  // How many characters to measure at once for the per-character
  // guide width (see draw_indent_guides()) — long enough that
  // Pango's own integer-pixel rounding of the sample's total width
  // is a negligible fraction of one column, unlike measuring a
  // single character.
  // VS Code measures the same way for the same reason (its own
  // charWidthReader.ts repeats a character 256 times, reads the
  // rendered width, and divides by 256).
  private const int CHAR_WIDTH_SAMPLE_LENGTH = 256;

  private int[] caret_offsets = {};
  private int bold_line_number = -1;
  private bool blink_visible = true;
  private uint blink_timeout_id = 0;
  private uint overscroll_idle_id = 0;
  private int? drop_indicator_offset = null;
  private int indent_size = 4; // matches EditorView.EditorPane.TabDocument.DEFAULT_INDENT_SIZE, overwritten by set_indent_size() once a document's actually loaded
  private CodeEditorSelections selections;

  /** Whether draw_indent_guides() runs at all — off for content whose leading whitespace isn't indentation (Find Results' own "  N: " line prefixes). */
  public bool show_indent_guides { get; set; default = true; }

  /**
   * A caret means "typing lands here" — showing one while this view
   * doesn't actually hold keyboard focus would be misleading (e.g.
   * opening a file with a single click in the sidebar: EditorController.
   * open() deliberately leaves focus in the file tree so arrow keys
   * keep navigating it, but the active document's cursor still exists
   * and gets rendered into caret_offsets same as ever). Gate painting
   * on has_focus rather than have CursorController suppress the
   * render itself — it never imports Gtk, so it has no notion of focus
   * at all, and the cursor state it computes is correct regardless.
   */
  public CodeEditorSourceView () {
    selections = new CodeEditorSelections (this);

    notify["has-focus"].connect (() => {
      if (has_focus) {
        reset_blink (); // solid immediately, not mid-blink from whenever focus happened to return
      } else {
        // The caret isn't painted without focus: no point ticking for it.
        stop_blinking ();
        queue_draw ();
      }
    });

    // The block-vs-bar shape depends on this session-wide flag —
    // reset_blink() both redraws and makes the caret solid right on
    // toggle, instead of possibly landing mid-blink-off.
    insert_mode_handler = Session.get_default ().notify["insert-mode"].connect (() => reset_blink ());
  }

  private ulong insert_mode_handler;

  /** See CodeEditor.close(). */
  public void close () {
    Session.get_default ().disconnect (insert_mode_handler);
    stop_blinking ();
    if (overscroll_idle_id != 0) {
      Source.remove (overscroll_idle_id);
      overscroll_idle_id = 0;
    }
    selections.close ();
  }

  /** A view in a hidden tab has nothing to blink for. */
  public override void unmap () {
    stop_blinking ();
    base.unmap ();
  }

  /** The codepoint offsets to paint a caret at on the next draw — one per cursor, primary included. Call whenever the cursor set changes, then `reset_blink()`. */
  public void set_carets (int[] offsets) {
    caret_offsets = offsets;
    redraw_line_numbers_if_line_changed ();
  }

  /**
   * GtkSourceView's line-number renderer bolds the insert mark's line,
   * but only redraws on a cursor move while `cursor-visible` or
   * `highlight-current-line` is on — both are off here (every caret is
   * hand-drawn), so the bold number would stay behind on plain arrow
   * navigation. Each renderer is asked directly: a gutter's own
   * queue_draw() doesn't reach its children.
   */
  private void redraw_line_numbers_if_line_changed () {
    Gtk.TextIter insert;
    buffer.get_iter_at_mark (out insert, buffer.get_insert ());
    int line = insert.get_line ();
    if (line == bold_line_number) {
      return;
    }
    bold_line_number = line;

    var gutter = get_gutter (Gtk.TextWindowType.LEFT);
    for (var renderer = gutter.get_first_child (); renderer != null; renderer = renderer.get_next_sibling ()) {
      renderer.queue_draw ();
    }
  }

  /** Pass-through to the selections sub-component (_selections.vala) — see its own set_selections(). */
  public void set_selections (Cursor[] cursors) {
    selections.set_selections (cursors);
  }

  /** The buffer offset under widget-relative (x, y) — the one pixel→offset query every gesture on this view needs (clicks, Alt+drag, drag-and-drop), so it lives here once rather than in each gesture's own class. */
  public int offset_at (double widget_x, double widget_y) {
    int buffer_x;
    int buffer_y;
    window_to_buffer_coords (Gtk.TextWindowType.WIDGET, (int) widget_x, (int) widget_y, out buffer_x, out buffer_y);

    Gtk.TextIter iter;
    get_iter_at_location (out iter, buffer_x, buffer_y);
    return iter.get_offset ();
  }

  // Vertical padding (SIMPLE): one extra row below the target so it
  // never sits right under the horizontal scrollbar (viewLines.ts:739–743).
  private const int SIMPLE_BOTTOM_PADDING_ROWS = 1;
  // How many reveal_iter() passes reveal_settled() allows — see its doc
  // comment for what a second pass is for.
  private const int REVEAL_SETTLE_PASSES = 3;
  // Horizontal padding (both modes): never an alignment, just enough
  // slack past the edge for the target not to hug it exactly
  // (viewLines.ts:784–830 — HORIZONTAL_EXTRA_PX / revealHorizontalRightPadding).
  private const int HORIZONTAL_LEFT_PADDING_PX = 30;
  private const int HORIZONTAL_RIGHT_PADDING_PX = 15;

  /**
   * Scrolls `iter` into view instantly — a hand-written replacement for
   * `Gtk.TextView.scroll_to_iter()`/`scroll_to_mark()`, needed for three
   * real, verified reasons (not a style preference):
   *
   * 1. Both GTK methods go through `gtk_adjustment_animate_to_value()`
   *    while the view is realized — a visible glide no caller here
   *    actually wants (confirmed directly: Find Results' own jump used
   *    to visibly "scroll into place" instead of landing immediately).
   * 2. Both apply `use_align`'s `xalign`/`yalign` to *both* axes at
   *    once — passing `xalign = 0` to center vertically also pins the
   *    horizontal scroll to the clicked column's own left edge whenever
   *    the buffer's widest line allows it, which is a real, confirmed
   *    bug (RC1 in the plan this method implements), not a hypothetical
   *    one. GTK's own pair has no "vertical center, horizontal minimal"
   *    combination at all.
   * 3. `scroll_to_iter()`'s own docs warn it "may not have the desired
   *    effect" before GTK's own idle line-height validation catches up
   *    — confirmed directly (RC3 in the same plan): called right after
   *    a re-parent, it silently validated against a zero-height
   *    allocation and produced no scroll at all. Writing the adjustment
   *    values directly sidesteps that whole mechanism — the same fix
   *    GNOME Text Editor's and Builder's own `jump_to_iter()` make for
   *    the identical reason ("without any of the scrolling animation").
   *
   * Horizontal reveal is always minimal (never an alignment) regardless
   * of `mode` — VS Code treats the two axes independently (viewLines.ts),
   * and RC1 above is exactly what pairing a vertical alignment with a
   * horizontal one caused.
   *
   * Sound even against a layout GTK hasn't fully validated yet: the
   * target row's band (row_band()) and `get_visible_rect()`'s own
   * `y`/`height` are both read from the same underlying line-height sums
   * at the moment of the call, so the *delta* between them is
   * self-consistent regardless of how much of the buffer is validated —
   * only the two rectangles' own relationship matters here, never an
   * absolute position. Vertically it is the row's full band, not
   * `get_iter_location()`'s glyph box, so the padding row and the
   * "already visible" test agree with the painted rows at any
   * `editor.line_height`; under word wrap that band is the caret's own
   * display row, so a paragraph taller than the viewport reveals the
   * right row of it.
   *
   * Returns whether either adjustment actually moved — what
   * reveal_settled() loops on.
   */
  public bool reveal_iter (Gtk.TextIter iter, RevealMode mode) {
    Gdk.Rectangle visible_rect;
    get_visible_rect (out visible_rect);
    int row_top;
    int row_bottom;
    row_band (iter, out row_top, out row_bottom);
    int row_height = row_bottom - row_top;
    int visible_bottom = visible_rect.y + visible_rect.height;

    double new_vvalue = vadjustment.value;
    switch (mode) {
      case RevealMode.SIMPLE:
        int bottom_padding = row_height * SIMPLE_BOTTOM_PADDING_ROWS;
        if (row_top < visible_rect.y) {
          new_vvalue -= visible_rect.y - row_top;
        } else if (row_bottom + bottom_padding > visible_bottom) {
          new_vvalue += row_bottom + bottom_padding - visible_bottom;
        }
        break;
      case RevealMode.CENTER_IF_OUTSIDE:
        bool already_visible = row_top >= visible_rect.y && row_bottom <= visible_bottom;
        if (!already_visible) {
          new_vvalue += (row_top + row_height / 2.0) - (visible_rect.y + visible_rect.height / 2.0);
        }
        break;
    }
    double vvalue_before = vadjustment.value;
    vadjustment.value = double.max (vadjustment.lower, double.min (new_vvalue, vadjustment.upper - vadjustment.page_size));

    Gdk.Rectangle iter_rect;
    get_iter_location (iter, out iter_rect);
    double new_hvalue = hadjustment.value;
    if (iter_rect.x < visible_rect.x + HORIZONTAL_LEFT_PADDING_PX) {
      new_hvalue -= visible_rect.x - iter_rect.x + HORIZONTAL_LEFT_PADDING_PX;
    } else if (iter_rect.x + iter_rect.width + HORIZONTAL_RIGHT_PADDING_PX > visible_rect.x + visible_rect.width) {
      new_hvalue += iter_rect.x + iter_rect.width + HORIZONTAL_RIGHT_PADDING_PX - (visible_rect.x + visible_rect.width);
    }
    double hvalue_before = hadjustment.value;
    hadjustment.value = double.max (hadjustment.lower, double.min (new_hvalue, hadjustment.upper - hadjustment.page_size));

    return vadjustment.value != vvalue_before || hadjustment.value != hvalue_before;
  }

  /**
   * reveal_iter() until it stops moving the viewport, at most
   * REVEAL_SETTLE_PASSES times. One pass is exact whenever `iter`'s
   * row already has its real height — every one-row edit or move, the
   * common case, where the heights above the caret are untouched by
   * the edit. A target further down than GTK has validated reports a
   * `y` that is short by every never-measured row in between; but
   * writing a scroll value makes GtkTextView validate the rows it just
   * scrolled onto and refresh the adjustment's `upper`, synchronously
   * inside the setter (gtk_text_view_value_changed() →
   * validate_onscreen() + update_adjustments(), checked in
   * gtktextview.c), so each further pass reads better geometry. Bounded
   * rather than exact: a far target (a long paste, an undo across many
   * screens) can need more passes than this, and gets its correction
   * from the caller's deferred follow-up instead (see
   * CodeEditorCursors.reveal_cursors()).
   */
  public void reveal_settled (Gtk.TextIter iter, RevealMode mode) {
    for (int pass = 0; pass < REVEAL_SETTLE_PASSES; pass++) {
      if (!reveal_iter (iter, mode)) {
        return;
      }
    }
  }

  /**
   * Columns per indent level, resolved by EditorController from the
   * linked folder's .editorconfig, per file — drives both the
   * indent guides' own spacing and, via `tab_width`, how wide a
   * literal `\t` character actually renders (`indent_width` is left
   * at its own default of -1, GtkSource.View's own "follow
   * tab_width" value, rather than set separately here).
   */
  public void set_indent_size (int size) {
    indent_size = size;
    tab_width = (uint) size;
    queue_draw ();
  }

  /**
   * "Scroll beyond last line": without this, once the document's own
   * last line reaches the bottom of the viewport there's nothing left
   * to scroll, so a short file (or scrolling all the way down a long
   * one) pins the last line to the very bottom edge of the window —
   * both VS Code and GNOME Text Editor instead leave room to keep
   * scrolling until only the last line remains, right at the top.
   *
   * `size_allocate` fires repeatedly while a window resize is still in
   * progress (every intermediate frame, not just the final size) —
   * recomputing on every single one would mean redoing this on every
   * pixel dragged. GNOME Text Editor's own EditorSourceView (src/
   * editor-source-view.c) debounces the exact same way: base class
   * first, then queue at most one GLib.Idle recompute per batch of
   * allocations, guarded by overscroll_idle_id so a second
   * size_allocate before the idle has run doesn't queue a duplicate.
   */
  public override void size_allocate (int width, int height, int baseline) {
    base.size_allocate (width, height, baseline);

    if (overscroll_idle_id != 0) {
      return;
    }
    overscroll_idle_id = Idle.add (() => {
      overscroll_idle_id = 0;
      update_overscroll_margin ();
      return Source.REMOVE;
    });
  }

  /**
   * VS Code's own formula (viewLayout.ts, _getContentHeight): extra
   * space = visible height minus one line's height, clamped to never
   * go negative — scrolled all the way down, exactly one line of real
   * content stays visible at the top instead of the document either
   * vanishing entirely or leaving an arbitrary fraction of empty
   * viewport (GNOME Text Editor's own simpler alternative is a flat
   * 75% of the viewport height, unconditionally — VS Code's is
   * pixel-exact to "one line remains" instead, which is why this
   * measures a real line via get_iter_location() rather than using a
   * fraction).
   */
  private void update_overscroll_margin () {
    if (!get_mapped ()) {
      return;
    }

    Gdk.Rectangle visible_rect;
    get_visible_rect (out visible_rect);

    Gtk.TextIter start_iter;
    buffer.get_start_iter (out start_iter);
    Gdk.Rectangle line_rect;
    get_iter_location (start_iter, out line_rect);

    bottom_margin = int.max (0, visible_rect.height - line_rect.height);
  }

  /**
   * Restarts the blink cycle so every caret is solid right after a
   * cursor-affecting change, then resumes blinking on the interval
   * above — the hand-drawn equivalent of `Gtk.TextView.
   * reset_cursor_blink()`, which stops being meaningful once the
   * native caret is never painted at all. Respects the desktop's own
   * "reduce motion"/no-blink accessibility preference
   * (`Gtk.Settings.gtk-cursor-blink`) by simply not starting the timer
   * when it's off — carets stay solid instead.
   */
  public void reset_blink () {
    blink_visible = true;
    stop_blinking ();

    if (Gtk.Settings.get_default ().gtk_cursor_blink) {
      blink_timeout_id = Timeout.add (BLINK_INTERVAL_MS, on_blink_tick);
    }

    queue_draw ();
  }

  private bool on_blink_tick () {
    blink_visible = !blink_visible;
    queue_draw ();
    return true;
  }

  private void stop_blinking () {
    if (blink_timeout_id != 0) {
      Source.remove (blink_timeout_id);
      blink_timeout_id = 0;
    }
  }

  public override void snapshot_layer (Gtk.TextViewLayer layer, Gtk.Snapshot snapshot) {
    base.snapshot_layer (layer, snapshot);

    if (layer == Gtk.TextViewLayer.BELOW_TEXT) {
      if (show_indent_guides) {
        draw_indent_guides (snapshot);
      }
      selections.draw (snapshot);
      return;
    }

    if (layer != Gtk.TextViewLayer.ABOVE_TEXT) {
      return;
    }

    draw_drop_indicator (snapshot);

    if (!blink_visible || !has_focus) {
      return;
    }

    // Read the theme's resolved foreground color fresh on every
    // paint rather than caching it from a theme-change callback —
    // CSS re-cascading on a light/dark switch isn't guaranteed to
    // have already settled by the time such a callback runs, but it
    // always has by the time an actual draw happens.
    var color = get_color ();

    foreach (var offset in caret_offsets) {
      Gtk.TextIter iter;
      buffer.get_iter_at_offset (out iter, offset);

      Gdk.Rectangle strong;
      Gdk.Rectangle weak;
      get_cursor_locations (iter, out strong, out weak);

      if (!Session.get_default ().insert_mode) {
        var rect = Graphene.Rect ();
        rect.init (strong.x, strong.y, 2, strong.height);
        snapshot.append_color (color, rect);
        continue;
      }

      draw_overtype_block (snapshot, iter, strong, color);
    }
  }

  /**
   * The block-cursor's own rect (same caret color the bar uses) at
   * `strong`, sized to whatever's actually under the cursor — a tab, a
   * newline, or nothing (end of buffer/empty line) all fall back to a
   * single-space-wide block with no glyph redrawn inside it; any real
   * character is measured the same way draw_indent_guides() already
   * measures per-character width elsewhere in this class, applied here
   * to just the one character under the caret.
   */
  private void draw_overtype_block (Gtk.Snapshot snapshot, Gtk.TextIter iter, Gdk.Rectangle strong, Gdk.RGBA caret_color) {
    unichar ch = iter.get_char (); // 0 at end-of-buffer/no real character there
    bool has_glyph = ch != 0 && ch != '\n' && ch != '\t';

    float width;
    if (has_glyph) {
      Gtk.TextIter next = iter;
      next.forward_char ();
      Gdk.Rectangle next_strong;
      Gdk.Rectangle next_weak;
      get_cursor_locations (next, out next_strong, out next_weak);
      // When `iter` is the last glyph of a wrapped display row, `next`
      // sits at the start of the row below: its x is the left margin,
      // and the difference would come out negative — which
      // graphene_rect_init normalizes into a bar from the margin to
      // the caret. The glyph's own box is the right width there.
      width = next_strong.y == strong.y ? next_strong.x - strong.x : glyph_width (iter);
    } else {
      width = measure_space_width ();
    }

    var block_rect = Graphene.Rect ();
    block_rect.init (strong.x, strong.y, width, strong.height);
    snapshot.append_color (caret_color, block_rect);

    if (!has_glyph) {
      return;
    }

    var glyph_layout = create_pango_layout (ch.to_string ());
    var point = Graphene.Point ();
    point.init (strong.x, strong.y);

    snapshot.save ();
    snapshot.translate (point);
    snapshot.append_layout (glyph_layout, inverted_glyph_color (caret_color));
    snapshot.restore ();
  }

  /**
   * The start of the display row after `on_row`'s, or false when that
   * row is its paragraph's last. A "display row" is one wrapped line
   * on screen; with wrap_mode NONE every paragraph is exactly one.
   * Never crosses into the next paragraph: `forward_display_line()`
   * itself walks on through the whole buffer, so the paragraph check
   * is what makes this a per-paragraph row iterator.
   */
  public bool next_row_start (Gtk.TextIter on_row, out Gtk.TextIter next) {
    next = on_row;
    return forward_display_line (ref next) && next.get_line () == on_row.get_line ();
  }

  /**
   * The vertical band [top, bottom) of the display row `on_row` sits
   * on: contiguous with the neighbouring rows, line-height included.
   * Not `get_iter_location()`'s rectangle — that's the glyph box, 16px
   * high inside a 23px row at `editor.line_height: 1.5`, so anything
   * sized from it leaves a gap between consecutive rows. The extra
   * leading GTK adds for line-height sits half above and half below
   * each row's glyphs (the same symmetry GtkSourceView's own gutter
   * assumes in `_gtk_source_gutter_lines_new()`), so a row's band is
   * its glyph top minus that half, down to the next row's; the
   * paragraph's own `get_line_yrange()` closes the first and last.
   *
   * Except for a paragraph GTK hasn't measured yet: `get_line_yrange()`
   * reports height 0 for a line with no layout data — every line
   * Enter has just created, until the frame's validation — while its
   * glyph box (from the paragraph's own PangoLayout, computed on
   * demand) is already real. The last row's bottom then comes from
   * that box plus the same leading, which is what lets a reveal of
   * the brand-new line scroll synchronously, in the same frame as the
   * edit, instead of seeing a zero-height row and leaving the whole
   * scroll to a later pass (a visible second jump — found live).
   */
  public void row_band (Gtk.TextIter on_row, out int top, out int bottom) {
    int paragraph_top;
    int paragraph_height;
    get_line_yrange (on_row, out paragraph_top, out paragraph_height);

    var paragraph_start = on_row;
    paragraph_start.set_line_offset (0);
    int half_leading = glyph_top (paragraph_start) - paragraph_top;

    top = glyph_top (on_row) - half_leading;

    Gtk.TextIter next;
    if (next_row_start (on_row, out next)) {
      bottom = glyph_top (next) - half_leading;
    } else if (paragraph_height > 0) {
      bottom = paragraph_top + paragraph_height;
    } else {
      bottom = glyph_bottom (on_row) + half_leading;
    }
  }

  // ---- IDisplayRows: the View's own display rows, for CursorCollection.move_by_row(). ----
  //
  // Offsets only, never a y coordinate: a pixel-y lookup
  // (get_iter_at_position/get_line_at_y) goes through the btree's
  // line-height cache, which is only validated for what's on screen —
  // and the caret can well be off-screen when an arrow key arrives.
  // forward/backward_display_line work per paragraph on its own
  // PangoLayout, lazily, so they don't care.

  public void row_bounds (int offset, out int start, out int end) {
    var row_start = row_start_iter (offset);
    start = row_start.get_offset ();
    end = row_end_iter (row_start).get_offset ();
  }

  public bool row_above (int offset, out int start, out int end) {
    // From the row's start, not from `offset`: on the buffer's first
    // paragraph, backward_display_line() doesn't leave the iter alone —
    // it moves it to that paragraph's own start and reports success —
    // so from mid-row it would land on the very same row.
    var it = row_start_iter (offset);
    if (!backward_display_line (ref it)) {
      start = 0;
      end = 0;
      return false;
    }
    row_bounds (it.get_offset (), out start, out end);
    return true;
  }

  public bool row_below (int offset, out int start, out int end) {
    var row_start = row_start_iter (offset);
    var it = row_start;
    bool moved = forward_display_line (ref it);
    // forward_display_line() reports false both when nothing moved and
    // when it moved onto the end iter — which is a real, empty last
    // row whenever the text ends in a newline.
    bool onto_empty_last_row = !moved && it.is_end () && it.starts_line () && !it.equal (row_start);
    if (!moved && !onto_empty_last_row) {
      start = 0;
      end = 0;
      return false;
    }
    row_bounds (it.get_offset (), out start, out end);
    return true;
  }

  private Gtk.TextIter row_start_iter (int offset) {
    Gtk.TextIter it;
    buffer.get_iter_at_offset (out it, offset);
    backward_display_line_start (ref it);
    return it;
  }

  /** The row's last caret position: before the next row's first character (where GTK's own End lands — see IDisplayRows' doc comment), or the paragraph's end on its last row. */
  private Gtk.TextIter row_end_iter (Gtk.TextIter row_start) {
    Gtk.TextIter next;
    if (next_row_start (row_start, out next)) {
      next.backward_char ();
      return next;
    }
    var end = row_start;
    if (!end.ends_line ()) {
      end.forward_to_line_end ();
    }
    return end;
  }

  private int glyph_top (Gtk.TextIter iter) {
    Gdk.Rectangle rect;
    get_iter_location (iter, out rect);
    return rect.y;
  }

  private int glyph_bottom (Gtk.TextIter iter) {
    Gdk.Rectangle rect;
    get_iter_location (iter, out rect);
    return rect.y + rect.height;
  }

  /** The glyph box width at `iter`, a space's width for a glyph Pango lays out zero-wide (a trailing space absorbed by a wrap). */
  private float glyph_width (Gtk.TextIter iter) {
    Gdk.Rectangle rect;
    get_iter_location (iter, out rect);
    return rect.width > 0 ? rect.width : measure_space_width ();
  }

  /** A single space's rendered width in this monospace font — every glyph-less fallback (an empty line, end of buffer, overtype's own no-glyph case, CodeEditorSelections' own empty-line marker) is sized to this. */
  public float measure_space_width () {
    var layout = create_pango_layout (" ");
    int w;
    int h;
    layout.get_pixel_size (out w, out h);
    return w;
  }

  /**
   * The buffer's own real background, as its GtkSource.StyleScheme
   * defines it (get_style("text").background) — confirmed against
   * GTK's own native overwrite-mode rendering (gtk/gtktextlayout.c,
   * gtk/gskpango.c): the plain CSS background-color on GtkTextView's
   * own "text" node is transparent by design in Adwaita, so this is
   * the real, public equivalent for a GtkSourceView specifically.
   * Falls back to the caret color's own arithmetic inverse only if
   * the scheme has no such style set.
   */
  private Gdk.RGBA inverted_glyph_color (Gdk.RGBA caret_color) {
    var scheme = ((GtkSource.Buffer) buffer).style_scheme;
    var style = scheme != null ? scheme.get_style ("text") : null;
    if (style != null && style.background_set) {
      Gdk.RGBA parsed = { 0, 0, 0, 1 };
      if (parsed.parse (style.background)) {
        return parsed;
      }
    }

    var inverted = caret_color;
    inverted.red = 1.0f - caret_color.red;
    inverted.green = 1.0f - caret_color.green;
    inverted.blue = 1.0f - caret_color.blue;
    return inverted;
  }

  /**
   * Where CodeEditor's own reimplemented drag-and-drop (see its own
   * DragSource/DropTarget setup) currently wants the drop indicator
   * shown, or null to hide it — driven entirely by real motion/leave/
   * drop events on our own DropTarget. GTK's native drag-and-drop
   * indicator can't be used at all: it gates its own visibility on
   * `cursor_visible(text_view)`, a private function returning
   * `use_caret || priv->cursor_visible` — unconditionally false in
   * Opus's configuration (`cursor_visible = false`, to suppress the
   * native caret entirely — see this class's own doc comment), so it
   * could never be made to appear without reintroducing a duplicate
   * native caret or mutating a desktop-wide accessibility setting
   * shared by every GTK app on the system. Both rejected — this is why
   * Opus reimplements the whole drag-and-drop interaction itself
   * rather than only its rendering.
   */
  public void set_drop_indicator (int? offset) {
    drop_indicator_offset = offset;
    queue_draw ();
  }

  /**
   * Vertical indent-guide lines, painted behind the text (BELOW_TEXT
   * layer) so glyphs draw over them, same as VS Code. Only ever
   * analyzes a bounded window of buffer text around what's actually
   * visible — INDENT_GUIDE_CONTEXT_LINES of slack each side, not the
   * whole buffer — since this runs on every repaint (scroll, cursor
   * blink, edits) and re-parsing an entire large file that often
   * would be wasteful.
   *
   * Column-to-pixel math is done by hand (line-start x from
   * get_iter_location(), plus `level * indent_size` character
   * widths) rather than looking up a real Gtk.TextIter at that
   * column: a blank line has no character there for
   * get_iter_at_line_offset() to find — it would just clamp back to
   * column 0 — but a guide still needs to draw through it at its
   * interpolated depth.
   */
  private void draw_indent_guides (Gtk.Snapshot snapshot) {
    Gdk.Rectangle visible_rect;
    get_visible_rect (out visible_rect);

    Gtk.TextIter top_iter;
    int top_y;
    get_line_at_y (out top_iter, visible_rect.y, out top_y);
    Gtk.TextIter bottom_iter;
    int bottom_y;
    get_line_at_y (out bottom_iter, visible_rect.y + visible_rect.height, out bottom_y);

    int line_count = buffer.get_line_count ();
    int visible_first_line = top_iter.get_line ().clamp (0, line_count - 1);
    int visible_last_line = bottom_iter.get_line ().clamp (0, line_count - 1);
    int window_start_line = int.max (0, visible_first_line - INDENT_GUIDE_CONTEXT_LINES);
    int window_end_line = int.min (line_count - 1, visible_last_line + INDENT_GUIDE_CONTEXT_LINES);

    Gtk.TextIter window_start_iter;
    buffer.get_iter_at_line (out window_start_iter, window_start_line);
    Gtk.TextIter window_end_iter;
    buffer.get_iter_at_line (out window_end_iter, window_end_line);
    window_end_iter.forward_to_line_end ();

    var guides = new IndentGuides (buffer.get_text (window_start_iter, window_end_iter, true), indent_size);

    int active_start_line = -1;
    int active_end_line = -1;
    int active_level = 0;
    if (caret_offsets.length > 0) {
      Gtk.TextIter cursor_iter;
      buffer.get_iter_at_offset (out cursor_iter, caret_offsets[0]);

      int local_start;
      int local_end;
      int level;
      guides.active_guide (cursor_iter.get_line () - window_start_line, out local_start, out local_end, out level);
      if (level > 0) {
        active_start_line = local_start + window_start_line;
        active_end_line = local_end + window_start_line;
        active_level = level;
      }
    }

    // The view is monospace, so one glyph's width stands in for
    // every character's — the same metric VS Code itself calls
    // spaceWidth for this exact purpose. Measured over a long
    // sample and averaged, not from a single character: a
    // single-space Pango layout reports a width measurably wider
    // than this font's real per-character advance (9px vs. an
    // actual ~7.56px, measured over 34 characters) — a fixed
    // per-glyph error that `(level - 1) * indent_size * char_width`
    // then multiplies by `level`, so guides drifted further off
    // with every deeper level instead of by a constant amount.
    var layout = create_pango_layout (string.nfill (CHAR_WIDTH_SAMPLE_LENGTH, '0'));
    int sample_width;
    int sample_height;
    layout.get_pixel_size (out sample_width, out sample_height);
    float char_width = sample_width / (float) CHAR_WIDTH_SAMPLE_LENGTH;

    var guide_color = get_color ();
    guide_color.alpha = INDENT_GUIDE_ALPHA;
    var active_color = get_color ();
    active_color.alpha = ACTIVE_INDENT_GUIDE_ALPHA;

    var levels = guides.levels_for_lines (visible_first_line - window_start_line, visible_last_line - window_start_line);

    for (int line = visible_first_line; line <= visible_last_line; line++) {
      int level_count = levels[line - visible_first_line];
      if (level_count == 0) {
        continue;
      }

      Gtk.TextIter line_start_iter;
      buffer.get_iter_at_line (out line_start_iter, line);
      Gdk.Rectangle line_rect;
      get_iter_location (line_start_iter, out line_rect);
      // The first display row's band only, even for a line that wraps
      // into several: a continuation row starts at the left margin
      // (there's no wrapping indent yet), so a guide through it would
      // cut straight through that row's own text — VS Code blocks the
      // guide on exactly those rows too (IndentGuideRepeatOption.
      // BlockSubsequent in viewModelLines.ts).
      int top;
      int bottom;
      row_band (line_start_iter, out top, out bottom);

      for (int level = 1; level <= level_count; level++) {
        float x = line_rect.x + (level - 1) * indent_size * char_width;
        bool is_active = level == active_level && line >= active_start_line && line <= active_end_line;

        var rect = Graphene.Rect ();
        rect.init (x, top, 1, bottom - top);
        snapshot.append_color (is_active ? active_color : guide_color, rect);
      }
    }
  }

  /**
   * Painted the same way as a real caret (same shape) but never
   * blinking and in the theme's accent color, so it reads as "this is
   * where it lands," not as one more actual cursor.
   */
  private void draw_drop_indicator (Gtk.Snapshot snapshot) {
    if (drop_indicator_offset == null) {
      return;
    }

    Gtk.TextIter iter;
    buffer.get_iter_at_offset (out iter, drop_indicator_offset);

    Gdk.Rectangle strong;
    Gdk.Rectangle weak;
    get_cursor_locations (iter, out strong, out weak);

    var rect = Graphene.Rect ();
    rect.init (strong.x, strong.y, 2, strong.height);
    // Null only if the platform doesn't support accent colors at
    // all (get_system_supports_accent_colors()) — the normal caret
    // color is a reasonable fallback rather than skipping the
    // indicator entirely. Deliberately the *method* form, not the
    // `accent_color_rgba` *property* — the property form is broken
    // against this system's installed libadwaita 1.7.6 headers (a
    // real vapi/header mismatch: "too many arguments to function
    // `adw_style_manager_get_accent_color_rgba`" at the C level).
    var accent = Adw.StyleManager.get_default ().get_accent_color_rgba ();
    snapshot.append_color (accent ?? get_color (), rect);
  }

}
