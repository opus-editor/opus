/**
 * GNOME Builder's IdeScrollbar (src/libide/editor/ide-scrollbar.c, Nokse,
 * 2025), ported as is: a real Gtk.Scrollbar over the view in libadwaita's
 * overlay-indicator style, `.hovering` toggled by a motion controller
 * since the scrolled window no longer owns the bar (vscrollbar-policy
 * external), and the file's git changes painted under it before the bar
 * is snapshotted — one bar per hunk at its lines' share of the height,
 * SCROLLBAR_H_MARGIN wide at the left edge (6px here, 7 there), 2px at least. The colors are
 * the gutter's: the theme's git hues at its opacity, a staged hunk
 * dimmed further, as CodeEditorChangeGutter does.
 */
public class CodeEditorScrollbar : Gtk.Widget {
  private const int SCROLLBAR_V_MARGIN = 6;
  private const int SCROLLBAR_H_MARGIN = 6;
  private const int SLIDER_W = 3;
  private const float DIMMED_ALPHA_FACTOR = 0.5f;

  private Gtk.Scrollbar scrollbar;
  private CodeEditorSourceView view;
  private GitDiff.Hunk[] hunks = {};
  private ulong buffer_handler;
  private ulong margin_handler;

  static construct {
    set_layout_manager_type (typeof (Gtk.BinLayout));
    set_css_name ("editor-scrollbar");
  }

  public CodeEditorScrollbar (CodeEditorSourceView view, Gtk.Adjustment vadjustment) {
    this.view = view;
    halign = Gtk.Align.END;

    scrollbar = new Gtk.Scrollbar (Gtk.Orientation.VERTICAL, vadjustment);
    scrollbar.add_css_class ("overlay-indicator");
    scrollbar.set_parent (this);

    var motion = new Gtk.EventControllerMotion ();
    motion.enter.connect (() => scrollbar.add_css_class ("hovering"));
    motion.leave.connect (() => scrollbar.remove_css_class ("hovering"));
    scrollbar.add_controller (motion);

    buffer_handler = view.buffer.changed.connect (queue_draw);
    margin_handler = view.notify["bottom-margin"].connect (queue_draw);
  }

  public override void dispose () {
    scrollbar.unparent ();
    base.dispose ();
  }

  /** See CodeEditor.close(). */
  public void close () {
    view.buffer.disconnect (buffer_handler);
    view.disconnect (margin_handler);
  }

  public void set_hunks (GitDiff.Hunk[] hunks) {
    this.hunks = hunks;
    queue_draw ();
  }

  public override void snapshot (Gtk.Snapshot snapshot) {
    int total_lines = view.buffer.get_line_count ();
    double height = get_height ();
    double width = get_width ();
    double view_height = scrollbar.adjustment.upper;
    if (total_lines > 0 && view_height > 0) {
      double ratio = height / view_height;
      double top_margin = ratio * view.top_margin + SCROLLBAR_V_MARGIN;
      double bottom_margin = ratio * view.bottom_margin + SCROLLBAR_V_MARGIN;
      double line_height = (height - top_margin - bottom_margin) / total_lines;

      var added = resolve ("git-added");
      var modified = resolve ("git-modified");
      var removed = resolve ("git-removed");
      foreach (var hunk in hunks) {
        int start_y = (int) (top_margin + hunk.current_start * line_height);
        int end_y = (int) (top_margin + (hunk.current_start + hunk.current_count) * line_height);
        var color = hunk.kind == GitDiff.HunkKind.ADDED ? added : hunk.kind == GitDiff.HunkKind.REMOVED ? removed : modified;
        if (!hunk.solid) {
          color.alpha *= DIMMED_ALPHA_FACTOR;
        }
        snapshot_chunk (snapshot, color, start_y, end_y, width);
      }
    }
    snapshot_child (scrollbar, snapshot);
  }

  private static void snapshot_chunk (Gtk.Snapshot snapshot, Gdk.RGBA color, int start_y, int end_y, double width) {
    int chunk_height = int.max (end_y - start_y, 2);
    int chunk_width = int.min (SCROLLBAR_H_MARGIN, (int) ((width - SLIDER_W) / 2));
    var rect = Graphene.Rect ();
    rect.init (0, start_y, chunk_width, chunk_height);
    snapshot.append_color (color, rect);
  }

  /** The `editor-scrollbar.git-*` rules (code-editor.css) as real colors — the class toggled on, the resolved `color` read back, the class off again; the same way CodeEditorChangeGutter resolves its own. */
  private Gdk.RGBA resolve (string tone_class) {
    add_css_class (tone_class);
    var color = get_color ();
    remove_css_class (tone_class);
    return color;
  }
}
