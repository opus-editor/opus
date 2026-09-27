/**
 * A frozen, independent copy of a {@link TabBarPill}'s appearance, used as
 * the real widget {@link Gdk.DragIcon} shows floating under the pointer
 * while a tab is being dragged (see {@link EditorView.TabBar}'s setup_drag_source()
 * — the same technique GTK's own native tab drag, and libadwaita's own
 * AdwTabBox, use for theirs, checked directly against its real source).
 * Deliberately not a live mirror of the dragged pill (e.g. via
 * {@link Gtk.WidgetPaintable}): a mirror reflects whatever the source
 * widget currently renders, live — including, for an inactive tab, the
 * dimmed opacity `_pill.vala` applies via `.tab-pill:not(.active)`, which
 * no per-drag override on the mirror itself can cleanly undo. Built once
 * from the dragged pill's label/state at drag start and thrown away on
 * drop; never touches the original pill.
 */
namespace EditorView.EditorPane_ {
  public class TabBarGhost : Object {
    private TabBarPill pill;

    public Gtk.Widget widget { get { return pill.widget; } }

    public TabBarGhost (string file_name, string folder_name, bool preview, bool modified) {
      pill = new TabBarPill ();
      pill.set_label (file_name, folder_name);
      pill.set_preview (preview);
      pill.set_modified (modified);
      // Always rendered as if active: a dragged tab reads as "the one
      // you're doing something with" regardless of which tab was
      // actually focused before the drag started.
      pill.set_active (true);

      pill.widget.can_target = false;
      pill.widget.add_css_class ("tab-drag-ghost");
      // GTK's CSS parser doesn't support the "light-dark()" function (a
      // real web-CSS feature, but not this one's), so there's no way to
      // express both colors in one rule the way var(--*) tokens do —
      // picked once here instead, matching whatever's current when the
      // drag starts (a drag is too short-lived for a live theme switch
      // mid-drag to matter).
      pill.widget.add_css_class (Adw.StyleManager.get_default ().dark ? "tab-drag-ghost-dark" : "tab-drag-ghost-light");
    }
  }
}
