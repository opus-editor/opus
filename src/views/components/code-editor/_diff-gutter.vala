/**
 * The gutter of an inline diff: the old line number, the new one, and a
 * `+`/`-` marker — three GtkSource.GutterRendererText columns answering
 * per buffer line out of a GitDiff.FileDiff, in place of GtkSourceView's
 * own number column (CodeEditor.show_diff() turns that off). Colors are
 * read back from CSS the way CodeEditorChangeGutter reads its own: the
 * marker column toggles `git-added`/`git-removed` on itself, and the
 * line backgrounds come off two zero-sized swatch overlays on the text
 * view carrying `diff-added-line`/`diff-removed-line` (code-editor.css).
 */
public class CodeEditorDiffGutter : Object {
  private const int XPAD = 4;

  private CodeEditorDiffGutterColumn old_numbers;
  private CodeEditorDiffGutterColumn new_numbers;
  private CodeEditorDiffGutterColumn markers;
  /** The swatches the added/removed row bands are painted from (`diff-added-line`/`diff-removed-line`, code-editor.css). */
  public Gtk.Widget added_swatch { get; private set; default = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { can_target = false }; }
  public Gtk.Widget removed_swatch { get; private set; default = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { can_target = false }; }
  private GitDiff.FileDiff? diff = null;

  public CodeEditorDiffGutter (GtkSource.View text_view) {
    old_numbers = new CodeEditorDiffGutterColumn (this, (line) => line.old_number > 0 ? line.old_number.to_string () : "", false);
    new_numbers = new CodeEditorDiffGutterColumn (this, (line) => line.new_number > 0 ? line.new_number.to_string () : "", false);
    markers = new CodeEditorDiffGutterColumn (this, (line) => line.kind == GitDiff.LineKind.ADDED ? "+" : line.kind == GitDiff.LineKind.REMOVED ? "-" : "", true);
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


}

/** One column of CodeEditorDiffGutter. `cell_text` says what a diff line shows here; a `colored` column paints added/removed cells in the git tones. */
public class CodeEditorDiffGutterColumn : GtkSource.GutterRendererText {
  public delegate string CellText (GitDiff.DiffLine line);

  private unowned CodeEditorDiffGutter owner;
  private CellText cell_text;
  private bool colored;
  private Gdk.RGBA color_added;
  private Gdk.RGBA color_removed;

  public CodeEditorDiffGutterColumn (CodeEditorDiffGutter owner, owned CellText cell_text, bool colored) {
    this.owner = owner;
    this.cell_text = (owned) cell_text;
    this.colored = colored;
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
    if (colored) {
      color_added = resolve ("git-added");
      color_removed = resolve ("git-removed");
    }
  }

  private Gdk.RGBA resolve (string tone_class) {
    add_css_class (tone_class);
    var color = get_color ();
    remove_css_class (tone_class);
    return color;
  }

  public override void query_data (GLib.Object lines, uint line) {
    var diff_line = owner.line_at (line);
    if (diff_line == null) {
      set_text ("", -1);
      return;
    }
    var text = cell_text (diff_line);
    if (!colored || diff_line.kind == GitDiff.LineKind.CONTEXT) {
      set_text (text, -1);
      return;
    }
    var color = diff_line.kind == GitDiff.LineKind.ADDED ? color_added : color_removed;
    set_markup ("<span foreground=\"%s\" weight=\"bold\">%s</span>".printf (hex (color), Markup.escape_text (text)), -1);
  }

  /** Pango wants "#rrggbb"; a mixed CSS color can come back a hair outside 0..1, so each channel is clamped. */
  private static string hex (Gdk.RGBA color) {
    return "#%02x%02x%02x".printf (channel (color.red), channel (color.green), channel (color.blue));
  }

  private static int channel (float value) {
    return ((int) (value * 255 + 0.5f)).clamp (0, 255);
  }
}
