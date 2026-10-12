/**
 * The editor's own colors — cursor, selection, indent guides, search
 * matches — resolved from CSS: zero-sized overlays on the view carrying
 * `editor-*` classes (code-editor.css, which reads the theme's
 * `--opus-editor-*`), read back with Gtk.Widget.get_color() by whoever
 * paints. The TreePanePalette trick. Read when painting, never cached
 * from a theme-change callback: the cascade has always settled by the
 * time a draw happens.
 */
public class CodeEditorPalette : Object {
  private const string[] CLASSES = { "editor-cursor", "editor-selection", "editor-indent-guide", "editor-indent-guide-active", "editor-search-match", "editor-search-current", "editor-ruler", "editor-ruler-background" };

  private Gtk.Box[] swatches = {};

  public CodeEditorPalette (Gtk.TextView view) {
    foreach (var name in CLASSES) {
      var swatch = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { can_target = false };
      swatch.add_css_class (name);
      view.add_overlay (swatch, 0, 0);
      swatches += swatch;
    }
  }

  public Gdk.RGBA cursor () { return swatches[0].get_color (); }
  public Gdk.RGBA selection () { return swatches[1].get_color (); }
  public Gdk.RGBA indent_guide () { return swatches[2].get_color (); }
  public Gdk.RGBA indent_guide_active () { return swatches[3].get_color (); }
  public Gdk.RGBA search_match () { return swatches[4].get_color (); }
  public Gdk.RGBA search_current () { return swatches[5].get_color (); }
  public Gdk.RGBA ruler () { return swatches[6].get_color (); }
  public Gdk.RGBA ruler_background () { return swatches[7].get_color (); }
}
