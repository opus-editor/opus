// Gtk.StyleContext itself was deprecated wholesale in GTK 4.10 (confirmed
// directly in the installed Gtk-4.0.gir: the whole class carries
// deprecated-version="4.10", not just some of its methods) — but its own
// deprecation note says "there is no replacement for querying the style
// machinery," and add_provider_for_display()/its _for_display sibling
// aren't about querying at all, they're the only way to install a
// display-wide CSS provider; nothing elsewhere in GTK4 replaces that.
// Every real call site in this project used the exact same three
// arguments (Gdk.Display.get_default(), the provider, PRIORITY_APPLICATION),
// so this raw binding — same technique file-tree/index.vala already uses
// for gtk_tree_list_model_new, sidestepping a vapi wart instead of living
// with a warning for something that isn't actually going away — both
// fixes the warning at its root and turns every call site into one line.
[CCode (cname = "gtk_style_context_add_provider_for_display")]
private extern static void add_provider_for_display_raw (Gdk.Display display, Gtk.StyleProvider provider, uint priority);

namespace GlobalCss {
  /**
   * Installs the .css file at `resource_path` as an application-priority,
   * display-wide style provider — the one-liner every View's own
   * install_css() reduces to. A resource path, not a `string css` taking
   * inline CSS text: Blueprint can't describe a stylesheet itself (only a
   * widget tree, plus `styles [...]` referencing classes another provider
   * defines), so an actual separate .css file, loaded by resource, is
   * this architecture's own equivalent of Blueprint for CSS — visual
   * rules stay out of the .vala "ViewModel" the same way layout already
   * does.
   */
  public void install_from_resource (string resource_path) {
    var provider = new Gtk.CssProvider ();
    provider.load_from_resource (resource_path);
    add_provider_for_display_raw (Gdk.Display.get_default (), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
  }
}
