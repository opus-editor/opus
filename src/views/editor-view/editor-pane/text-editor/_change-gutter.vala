/**
 * Colored change-indicator bars in the gutter, one per GitDiff.Hunk —
 * colors come from `.change-gutter.git-added`/`git-modified`/
 * `git-removed` (text-editor.css), the same shared, pure-hue
 * `--git-*-color` tokens (common.css) the explorer dot's own git-*
 * rules and the tab label's own git-* rules mix too — not
 * GtkSourceView's own bundled diff:*-line style-scheme colors, which
 * have no relation to the rest of Opus's own git-status color
 * language. A hunk that still differs from the index (unstaged work on
 * top) draws at that base color; one already fully captured by what's
 * staged draws further dimmed on top of it (DIMMED_ALPHA_FACTOR) — this
 * one state is plain alpha math in Vala, not a second CSS class combo,
 * since it's the gutter's own per-hunk runtime data with no dot/tab
 * equivalent. Read via Gtk.Widget.get_color(), the only way to pull a
 * real CSS color into Gsk/Gtk.Snapshot painting instead of a widget's
 * own background.
 */
namespace EditorView.EditorPane_ {
  public class TextEditorChangeGutter : GtkSource.GutterRenderer {
    private const int BAR_WIDTH = 3;
    // Right-side-only breathing room before the text starts — GtkSource.
    // GutterRenderer's own xpad is symmetric (both sides), so this is
    // just extra width on the renderer's own cell instead: the bar/
    // triangle are still drawn at x=0..BAR_WIDTH, leaving this much
    // blank space to their right. Matches BAR_WIDTH itself rather than
    // the wider gap first tried — that read as a gap in the gutter, not
    // breathing room for the bar.
    private const int RIGHT_MARGIN = 3;
    // Multiplies the already-50%-transparent resolved color (common.css)
    // for a dimmed (already-staged) hunk — not an absolute alpha value.
    private const float DIMMED_ALPHA_FACTOR = 0.5f;
    // Half-height of the REMOVED marker's triangle, centered on the
    // boundary line's own top edge.
    private const float REMOVED_TRIANGLE_HALF_HEIGHT = 4;

    private GitDiff.Hunk[] hunks = {};
    private Gdk.RGBA color_added;
    private Gdk.RGBA color_modified;
    private Gdk.RGBA color_removed;

    construct {
      set_size_request (BAR_WIDTH + RIGHT_MARGIN, -1);
      // Permanent, like .decoration-dot/.tab-pill are permanent classes
      // on their own widgets — only the git-* class toggles per color
      // resolved below.
      add_css_class ("change-gutter");
      // Colors aren't resolved here: this widget has no parent yet at
      // construct time (TextEditor's constructor calls `new
      // TextEditorChangeGutter ()` before ever inserting it into the
      // real Gutter), so its style context has nothing real to cascade
      // from and get_color () would just return GTK's bare default
      // (white) — confirmed live. begin () is only ever called once
      // this renderer is actually attached and being asked to paint, so
      // colors are (re)resolved there instead, on every redraw pass.
      Adw.StyleManager.get_default ().notify["dark"].connect (() => queue_draw ());
    }

    public override void begin (GtkSource.GutterLines lines) {
      reload_colors ();
    }

    /** Resolves each of the three `.change-gutter.git-*` classes (text-editor.css) to a real color: temporarily add the git-* class, read back this widget's own resolved CSS `color`, remove it again. */
    private void reload_colors () {
      color_added = resolve_tone_color ("git-added");
      color_modified = resolve_tone_color ("git-modified");
      color_removed = resolve_tone_color ("git-removed");
    }

    private Gdk.RGBA resolve_tone_color (string tone_class) {
      add_css_class (tone_class);
      var color = get_color ();
      remove_css_class (tone_class);
      return color;
    }

    public void set_hunks (GitDiff.Hunk[] new_hunks) {
      hunks = new_hunks;
      queue_draw ();
    }

    public override void snapshot_line (Gtk.Snapshot snapshot, GtkSource.GutterLines lines, uint line) {
      foreach (var hunk in hunks) {
        if (!hunk_covers_line (hunk, line)) {
          continue;
        }

        var color = style_color_for (hunk.kind, hunk.solid);
        if (hunk.kind == GitDiff.HunkKind.REMOVED) {
          draw_removed_marker (snapshot, lines, line, color);
        } else {
          draw_bar (snapshot, lines, line, color);
        }
        return;
      }
    }

    private void draw_bar (Gtk.Snapshot snapshot, GtkSource.GutterLines lines, uint line, Gdk.RGBA color) {
      double y, height;
      lines.get_line_extent (line, GtkSource.GutterRendererAlignmentMode.CELL, out y, out height);

      var rect = Graphene.Rect ();
      rect.init (0, (float) y, BAR_WIDTH, (float) height);
      snapshot.append_color (color, rect);
    }

    /** A pure deletion has no real current-buffer line range to span (see Hunk's own doc comment) — a small triangle notch at the boundary line's own top edge instead of a full-height bar, same convention other editors use for this case. */
    private void draw_removed_marker (Gtk.Snapshot snapshot, GtkSource.GutterLines lines, uint line, Gdk.RGBA color) {
      double y, height;
      lines.get_line_extent (line, GtkSource.GutterRendererAlignmentMode.CELL, out y, out height);

      var builder = new Gsk.PathBuilder ();
      builder.move_to (0, (float) y - REMOVED_TRIANGLE_HALF_HEIGHT);
      builder.line_to (0, (float) y + REMOVED_TRIANGLE_HALF_HEIGHT);
      builder.line_to (BAR_WIDTH, (float) y);
      builder.close ();
      snapshot.append_fill (builder.to_path (), Gsk.FillRule.WINDING, color);
    }

    private bool hunk_covers_line (GitDiff.Hunk hunk, uint line) {
      // A REMOVED hunk has no real current-buffer range — draw a
      // single-line marker at its boundary line instead (see Hunk's own
      // doc comment).
      if (hunk.kind == GitDiff.HunkKind.REMOVED) {
        return line == hunk.current_start;
      }
      return line >= hunk.current_start && line < hunk.current_start + hunk.current_count;
    }

    private Gdk.RGBA style_color_for (GitDiff.HunkKind kind, bool solid) {
      var color = kind == GitDiff.HunkKind.ADDED ? color_added
        : kind == GitDiff.HunkKind.REMOVED ? color_removed : color_modified;
      if (!solid) {
        color.alpha *= DIMMED_ALPHA_FACTOR;
      }
      return color;
    }
  }
}
