/**
 * A multi-line text box that grows with its text — from `min_height` up
 * to `max_lines` of the view's own real line height, scrolling past that
 * — with a placeholder while empty. Its own widget because the obvious
 * arrangement, a Gtk.TextView straight inside a Gtk.ScrolledWindow,
 * scrolls to the cursor, animated, before the box has grown around a new
 * line, and GtkTextView's size_allocate leaves its adjustment alone
 * while that animation runs: the grown box kept the old page size and
 * sat scrolled by a few pixels, the first line cut off. text-area.blp
 * has the arrangement that sidesteps it; keep_cursor_visible() is the
 * scrolling that arrangement then owes.
 */
public class TextArea : Gtk.Widget {
  private Gtk.Overlay overlay;
  private Gtk.ScrolledWindow scrolled;
  private Gtk.TextView view;
  private Gtk.Label placeholder_label;
  private uint cursor_id = 0;

  /** The whole text, "" when empty. */
  public string text {
    owned get { return view.buffer.text; }
    set { view.buffer.text = value; }
  }

  /** Shown, dimmed, while the text is empty. */
  public string placeholder {
    get { return placeholder_label.label; }
    set { placeholder_label.label = value; }
  }

  /** How many lines the box grows to before it scrolls. */
  public int max_lines { get; set; default = 12; }

  /** The box's height with little or no text, in px. */
  public int min_height {
    get { return scrolled.height_request; }
    set { scrolled.height_request = value; }
  }

  /** The text changed — typed, or set through `text`. */
  public signal void changed ();

  static construct {
    set_css_name ("textarea");
  }

  public TextArea () {
    layout_manager = new Gtk.BinLayout ();

    var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/components/text-area.ui");
    overlay = (Gtk.Overlay) builder.get_object ("overlay");
    scrolled = (Gtk.ScrolledWindow) builder.get_object ("scrolled");
    view = (Gtk.TextView) builder.get_object ("view");
    placeholder_label = (Gtk.Label) builder.get_object ("placeholder_label");
    overlay.set_parent (this);

    view.buffer.changed.connect (() => {
      placeholder_label.visible = view.buffer.text == "";
      update_max_height ();
      changed ();
    });
    // A line's real height is only known once the view is laid out in a window.
    view.map.connect (update_max_height);
    notify["max-lines"].connect (update_max_height);
    // After a cursor move, and after the viewport takes a new height
    // (upper changes inside its size_allocate, so the scroll itself
    // waits for the idle: set there and then, the viewport had already
    // placed the view for this frame and swallowed the re-allocation).
    view.buffer.notify["cursor-position"].connect (schedule_cursor);
    scrolled.vadjustment.notify["upper"].connect (schedule_cursor);

    GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/text-area.css");
  }

  public override void dispose () {
    if (cursor_id != 0) {
      Source.remove (cursor_id);
      cursor_id = 0;
    }
    Gtk.Widget? child;
    while ((child = get_first_child ()) != null) {
      child.unparent ();
    }
    base.dispose ();
  }

  /** Focuses the real inner view, not this composite widget itself. */
  public override bool grab_focus () {
    return view.grab_focus ();
  }

  /** max_lines of the view's real line height (the first line's, CSS line-height included), plus its margins — what propagate-natural-height grows the box up to. */
  private void update_max_height () {
    Gtk.TextIter start;
    view.buffer.get_start_iter (out start);
    int y, line_height;
    view.get_line_yrange (start, out y, out line_height);
    if (line_height <= 0) {
      return;
    }
    int max_height = max_lines * line_height + view.top_margin + view.bottom_margin;
    if (max_height != scrolled.max_content_height) {
      scrolled.max_content_height = max_height;
    }
  }

  private void schedule_cursor () {
    if (cursor_id != 0) {
      return;
    }
    cursor_id = Idle.add (() => {
      cursor_id = 0;
      keep_cursor_visible ();
      return Source.REMOVE;
    });
  }

  /** The viewport, not the view, is what scrolls past the limit, and it knows nothing of the cursor — once the layout has settled, it is scrolled the least that brings the cursor's line back in. A direct set, never an animation. */
  private void keep_cursor_visible () {
    var buffer = view.buffer;
    Gtk.TextIter cursor;
    buffer.get_iter_at_mark (out cursor, buffer.get_insert ());
    Gdk.Rectangle location;
    view.get_iter_location (cursor, out location);
    var adjustment = scrolled.vadjustment;
    double top = location.y;
    double bottom = location.y + location.height + view.top_margin + view.bottom_margin;
    if (bottom > adjustment.value + adjustment.page_size) {
      adjustment.value = bottom - adjustment.page_size;
    } else if (top < adjustment.value) {
      adjustment.value = top;
    }
  }
}
