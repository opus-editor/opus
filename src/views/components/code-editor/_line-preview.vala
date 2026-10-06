/**
 * A look at a line without going to it: the view scrolls there and the
 * line is tinted from edge to edge, while the cursors stay where they
 * are. What the Command Bar's `#` list does for the row under its
 * cursor, as VS Code does — and why ending the preview can put the
 * view back where it started.
 */
public class CodeEditorLinePreview : Object {
  private const string TAG_NAME = "opus-line-preview";

  private CodeEditorSourceView text_view;
  private Gtk.Adjustment vadjustment;
  private Gtk.TextTag tag;
  private bool active = false;
  private int shown_line = 0;
  private double scroll_before = 0;

  /** The 1-based line being previewed, 0 when none is. */
  public int line {
    get { return shown_line; }
  }

  public CodeEditorLinePreview (CodeEditorSourceView text_view, Gtk.Adjustment vadjustment) {
    this.text_view = text_view;
    this.vadjustment = vadjustment;

    tag = new Gtk.TextTag (TAG_NAME);
    text_view.buffer.tag_table.add (tag);

    var style_manager = Adw.StyleManager.get_default ();
    dark_handler = style_manager.notify["dark"].connect (() => apply_theme_colors (style_manager.dark));
    apply_theme_colors (style_manager.dark);
  }

  private ulong dark_handler;

  /** See CodeEditor.close(). */
  public void close () {
    Adw.StyleManager.get_default ().disconnect (dark_handler);
  }

  private void apply_theme_colors (bool dark) {
    var background = SystemColor.from_accent ().desaturate (dark ? 0.10f : 0.05f).to_rgba ();
    background.alpha = 0.25f;
    // The paragraph's background, not the text's: it reaches both edges of the view however short the line is.
    tag.paragraph_background_rgba = background;
  }

  /** Scrolls to the 1-based `line` and tints it. The first call of a preview remembers where the view was. */
  public void show (int line) {
    if (!active) {
      scroll_before = vadjustment.value;
      active = true;
    }
    untint ();

    Gtk.TextIter start;
    text_view.buffer.get_iter_at_line (out start, line - 1);
    var end = start;
    end.forward_line ();
    text_view.buffer.apply_tag (tag, start, end);
    shown_line = line;
    text_view.reveal_settled (start, RevealMode.CENTER_IF_OUTSIDE);
  }

  /** Ends the preview. `restore_scroll` puts the view back where the preview found it — for a preview given up, not one followed. */
  public void end (bool restore_scroll) {
    if (!active) {
      return;
    }
    untint ();
    active = false;
    if (restore_scroll) {
      vadjustment.value = scroll_before;
    }
  }

  private void untint () {
    Gtk.TextIter start, end;
    text_view.buffer.get_bounds (out start, out end);
    text_view.buffer.remove_tag (tag, start, end);
    shown_line = 0;
  }
}
