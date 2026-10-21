/**
 * The gutter of an inline diff: the old line number, the new one, and a
 * `+`/`-` marker — three GtkSource.GutterRendererText columns answering
 * per buffer line out of a GitDiff.FileDiff, in place of GtkSourceView's
 * own number column (CodeEditor.show_diff() turns that off), all three
 * in the gutter's own plain text. Colors are read back from CSS the way
 * CodeEditorChangeGutter reads its own: the line backgrounds come off
 * two zero-sized swatch overlays on the text view carrying
 * `diff-added-line`/`diff-removed-line` (code-editor.css).
 * The words that changed inside a line pair (GitDiff.DiffLine.word_changes)
 * are two Gtk.TextTags over the row tint, colored off two more swatches
 * (`diff-added-word`/`diff-removed-word`) — a tag's background can't be
 * read from CSS at paint time the way a band's is, so refresh_colors()
 * re-reads them whenever the theme does.
 */
public class CodeEditorDiffGutter : Object {
  private const int XPAD = 4;

  private CodeEditorDiffGutterColumn old_numbers;
  private CodeEditorDiffGutterColumn new_numbers;
  private CodeEditorDiffGutterColumn markers;
  /** The swatches the added/removed row bands are painted from (`diff-added-line`/`diff-removed-line`, code-editor.css). */
  public Gtk.Widget added_swatch { get; private set; default = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { can_target = false }; }
  public Gtk.Widget removed_swatch { get; private set; default = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { can_target = false }; }
  private Gtk.Widget added_word_swatch = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { can_target = false };
  private Gtk.Widget removed_word_swatch = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { can_target = false };
  private Gtk.TextTag added_word_tag = new Gtk.TextTag ("diff-added-word") { background_set = true };
  private Gtk.TextTag removed_word_tag = new Gtk.TextTag ("diff-removed-word") { background_set = true };
  private Gtk.TextBuffer buffer;
  private GitDiff.FileDiff? diff = null;

  public CodeEditorDiffGutter (GtkSource.View text_view) {
    buffer = text_view.buffer;
    buffer.tag_table.add (added_word_tag);
    buffer.tag_table.add (removed_word_tag);
    added_word_swatch.add_css_class ("diff-added-word");
    removed_word_swatch.add_css_class ("diff-removed-word");
    text_view.add_overlay (added_word_swatch, 0, 0);
    text_view.add_overlay (removed_word_swatch, 0, 0);
    old_numbers = new CodeEditorDiffGutterColumn (this, (line) => line.old_number > 0 ? line.old_number.to_string () : "");
    new_numbers = new CodeEditorDiffGutterColumn (this, (line) => line.new_number > 0 ? line.new_number.to_string () : "");
    markers = new CodeEditorDiffGutterColumn (this, (line) => line.kind == GitDiff.LineKind.ADDED ? "+" : line.kind == GitDiff.LineKind.REMOVED ? "-" : "");
    added_swatch.add_css_class ("diff-added-line");
    removed_swatch.add_css_class ("diff-removed-line");
    text_view.add_overlay (added_swatch, 0, 0);
    text_view.add_overlay (removed_swatch, 0, 0);
  }

  public void attach (GtkSource.Gutter gutter) {
    gutter.insert (old_numbers, 0);
    gutter.insert (new_numbers, 1);
    gutter.insert (markers, 2);
  }

  public void detach (GtkSource.Gutter gutter) {
    gutter.remove (old_numbers);
    gutter.remove (new_numbers);
    gutter.remove (markers);
  }

  /** The lines the columns answer from; widths follow the largest number on each side. */
  public void set_diff (GitDiff.FileDiff diff) {
    this.diff = diff;
    int old_max = 0;
    int new_max = 0;
    for (uint i = 0; i < diff.lines.length; i++) {
      old_max = int.max (old_max, diff.lines[i].old_number);
      new_max = int.max (new_max, diff.lines[i].new_number);
    }
    old_numbers.fit (old_max.to_string ());
    new_numbers.fit (new_max.to_string ());
    markers.fit ("+");
    old_numbers.queue_draw ();
    new_numbers.queue_draw ();
    markers.queue_draw ();
  }

  public GitDiff.DiffLine? line_at (uint line) {
    return diff != null && line < diff.lines.length ? diff.lines[line] : null;
  }

  /** Tags each line's word_changes — once the diff's text is in the buffer, which set_diff() runs ahead of. Replacing the text drops the tags again, so nothing clears them. */
  public void apply_word_tags () {
    if (diff == null) {
      return;
    }
    refresh_colors ();
    for (uint line = 0; line < diff.lines.length; line++) {
      var diff_line = diff.lines[line];
      var tag = diff_line.kind == GitDiff.LineKind.ADDED ? added_word_tag : removed_word_tag;
      foreach (var range in diff_line.word_changes) {
        Gtk.TextIter start;
        Gtk.TextIter end;
        buffer.get_iter_at_line_offset (out start, (int) line, range.start);
        buffer.get_iter_at_line_offset (out end, (int) line, range.end);
        buffer.apply_tag (tag, start, end);
      }
    }
  }

  /** The tags' colors, read off their swatches now — on a theme change the band repaints itself, a tag has to be told. */
  public void refresh_colors () {
    added_word_tag.background_rgba = added_word_swatch.get_color ();
    removed_word_tag.background_rgba = removed_word_swatch.get_color ();
  }
}

/** One column of CodeEditorDiffGutter. `cell_text` says what a diff line shows here. */
public class CodeEditorDiffGutterColumn : GtkSource.GutterRendererText {
  public delegate string CellText (GitDiff.DiffLine line);

  private unowned CodeEditorDiffGutter owner;
  private CellText cell_text;

  public CodeEditorDiffGutterColumn (CodeEditorDiffGutter owner, owned CellText cell_text) {
    this.owner = owner;
    this.cell_text = (owned) cell_text;
    add_css_class ("diff-gutter");
    xpad = 4;
    xalign = 1.0f;
  }

  private string? pending_widest = null;

  /** Sizes the column for `widest`, so it doesn't jitter as lines with shorter numbers scroll by — applied at the next draw: measure() needs the renderer's own Pango layout, which only exists once it is drawing. */
  public void fit (string widest) {
    pending_widest = widest;
  }

  public override void begin (GtkSource.GutterLines lines) {
    base.begin (lines); // GutterRendererText's own begin() is where its Pango layout comes from
    if (pending_widest != null) {
      int width, height;
      measure (pending_widest, out width, out height);
      pending_widest = null;
      // Not set_size_request() right here: this runs inside a draw pass, and
      // a resize from within one is what GTK warns about.
      Idle.add (() => {
        set_size_request (width + 2 * xpad, -1);
        return Source.REMOVE;
      });
    }
  }

  public override void query_data (GLib.Object lines, uint line) {
    var diff_line = owner.line_at (line);
    set_text (diff_line == null ? "" : cell_text (diff_line), -1);
  }
}
