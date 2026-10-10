namespace GitView {
  /**
   * The lane colors, resolved from CSS once per theme: eight zero-sized
   * boxes carrying `graph-lane-0..7` (tree-pane.css), read back with
   * Gtk.Widget.get_color() — the same trick CodeEditorChangeGutter uses,
   * minus the class toggling, which inside a snapshot() would invalidate
   * the very style being read. Sits in the pane's own box, invisible by
   * size, so it follows the window's light/dark class like any widget.
   */
  public class TreePanePalette : Object {
    private Gtk.Box box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
    private Gtk.Widget[] swatches = {};
    private Gtk.Box background_swatch = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);

    public Gtk.Widget widget { get { return box; } }

    public TreePanePalette () {
      for (int i = 0; i < GitTree.Graph.COLOR_COUNT; i++) {
        var swatch = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        swatch.add_css_class ("graph-lane-%d".printf (i));
        box.append (swatch);
        swatches += swatch;
      }
      background_swatch.add_css_class ("graph-background");
      box.append (background_swatch);
    }

    public Gdk.RGBA color (int index) {
      return swatches[index % swatches.length].get_color ();
    }

    /** The list's own background (`graph-background`, tree-pane.css) — what a node drawn over a lane line is cleared with. */
    public Gdk.RGBA background () {
      return background_swatch.get_color ();
    }
  }
}
