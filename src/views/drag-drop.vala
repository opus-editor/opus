/**
 * Payload for an in-app drag of a single file/folder path — a
 * FileTreeRow (a sidebar entry) or a TabPill (an open tab), dropped onto
 * a FileTreeView folder row or another TabPill (to reorder). A distinct
 * GType, not a plain string: Gtk.DropTarget matches by GType, and a plain
 * string would also match GtkTextView's own built-in text-drop handling
 * — libadwaita's own AdwTabBox (checked its real source, adw-tab-box.c)
 * hits the exact same concern and solves it the same way, unioning a
 * GType-typed content provider for its own AdwTabPage alongside its
 * plain text one. Nothing else in GTK declares interest in this type,
 * so this drag stays contained to whichever DropTarget is actually
 * built for it.
 */
public class FileDragPayload : Object {
    public string path { get; private set; }

    public FileDragPayload (string path) {
        this.path = path;
    }
}

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
 * make_source()'s own comment for why, and TabBarView's own use of this
 * (a fresh TabGhost) for a concrete example — matches how libadwaita's
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

/**
 * Shared machinery for starting an in-app file drag — used by both
 * FileTreeView (dragging a sidebar entry onto a folder) and TabBarView
 * (dragging a tab to reorder it, or onto the sidebar), so real GTK
 * drag-and-drop isn't wired up twice. Only the source side lives here:
 * each of those builds its own Gtk.DropTarget directly for whatever it
 * actually accepts drops of (nothing to share there — hover feedback is
 * specific to each one's own widgets).
 */
public class FileDrag : Object {
    /**
     * Makes `attach_to` a drag source. `resolve` is asked, right as the
     * drag actually starts, what's being dragged from that point — a
     * closure rather than a fixed candidate, since FileTreeView attaches
     * this once to its whole Gtk.ListView (matching its own established
     * pattern of one controller there instead of one per row — see
     * FileTreeView's other setup_*() methods) and only knows which row
     * that means via Gtk.ListView.pick() at drag time, not up front;
     * TabBarView attaches one per pill instead, where the path is fixed
     * and its resolver just ignores (x, y).
     *
     * The floating icon is a real widget (Gdk.DragIcon.child), not a
     * Gtk.WidgetPaintable snapshot, whenever `resolve` supplies one via
     * FileDragCandidate.icon_widget — checked directly against
     * libadwaita's own real drag-and-drop source (adw-tab-box.c's
     * create_drag_icon(), which builds a fresh AdwTab for exactly this
     * reason) rather than assumed: GTK's own native tab-drag ghost is
     * built the same way, not through a paintable of the dragged widget
     * itself. Falls back to a plain Gtk.WidgetPaintable of
     * `preview_widget` when no separate icon widget is given (fine for
     * FileTreeView's own sidebar rows — nothing about a row's current
     * look needs to be overridden for its drag icon).
     */
    public static Gtk.DragSource make_source (Gtk.Widget attach_to, owned FileDragResolver resolve) {
        var source = new Gtk.DragSource ();
        source.actions = Gdk.DragAction.MOVE;

        FileDragCandidate? candidate = null;
        double press_x = 0;
        double press_y = 0;
        source.prepare.connect ((x, y) => {
            candidate = resolve (x, y);
            press_x = x;
            press_y = y;
            if (candidate == null) {
                return null;
            }

            var value = Value (typeof (FileDragPayload));
            value.set_object (new FileDragPayload (candidate.path));
            return new Gdk.ContentProvider.for_value (value);
        });

        source.drag_begin.connect ((drag) => {
            if (candidate == null) {
                return;
            }

            // The hotspot (where within the icon the pointer stays glued)
            // is computed against preview_widget's own on-screen bounds,
            // not attach_to's — press_x/press_y are in attach_to's own
            // coordinates (e.g. the whole Gtk.ListView for FileTreeView,
            // not the specific row), so they need translating into
            // preview_widget's own local space first.
            int hot_x = 0;
            int hot_y = 0;
            Graphene.Rect bounds;
            if (candidate.preview_widget.compute_bounds (attach_to, out bounds)) {
                hot_x = (int) (press_x - bounds.origin.x);
                hot_y = (int) (press_y - bounds.origin.y);
            }

            if (candidate.icon_widget != null) {
                drag.set_hotspot (hot_x, hot_y);
                ((Gtk.DragIcon) Gtk.DragIcon.get_for_drag (drag)).child = candidate.icon_widget;
            } else {
                source.set_icon (new Gtk.WidgetPaintable (candidate.preview_widget), hot_x, hot_y);
            }
        });

        attach_to.add_controller (source);
        return source;
    }
}
