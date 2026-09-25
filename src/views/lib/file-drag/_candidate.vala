/**
 * What's being dragged. `preview_widget` is the *real* widget being
 * dragged — its on-screen bounds are what the drag's hotspot (where
 * within the icon the pointer stays glued) is computed against, whether
 * or not it's also what gets shown as the icon. `icon_widget`, if given,
 * is a separate, purpose-built widget shown as the floating icon instead
 * of a live snapshot of `preview_widget` itself — needed wherever the
 * real widget's own current visual state (e.g. a tab pill's dimmed,
 * non-active look) shouldn't carry over into the drag icon; a plain
 * Gtk.WidgetPaintable can't cleanly override that. See FileDrag.
 * make_source()'s own comment for why, and EditorView.TabBar's own use of this
 * (a fresh EditorView.TabBarGhost) for a concrete example — matches how libadwaita's
 * own AdwTabBox does this too (a real, separate AdwTab as the drag icon,
 * not a paintable of the dragged one).
 */
public class FileDragCandidate : Object {
    public string path;
    public Gtk.Widget preview_widget;
    public Gtk.Widget? icon_widget;

    public FileDragCandidate (string path, Gtk.Widget preview_widget, Gtk.Widget? icon_widget = null) {
        this.path = path;
        this.preview_widget = preview_widget;
        this.icon_widget = icon_widget;
    }
}

/** Resolves what's being dragged from a point local to whatever widget FileDrag.make_source() was attached to — null means nothing draggable there. */
public delegate FileDragCandidate? FileDragResolver (double x, double y);
