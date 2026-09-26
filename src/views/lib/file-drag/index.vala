/**
 * Shared machinery for starting an in-app file drag — used by both
 * EditorView.FileTree (dragging a sidebar entry onto a folder) and EditorView.TabBar
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
   * closure rather than a fixed candidate, since EditorView.FileTree attaches
   * this once to its whole Gtk.ListView (matching its own established
   * pattern of one controller there instead of one per row — see
   * EditorView.FileTree's other setup_*() methods) and only knows which row
   * that means via Gtk.ListView.pick() at drag time, not up front;
   * EditorView.TabBar attaches one per pill instead, where the path is fixed
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
   * EditorView.FileTree's own sidebar rows — nothing about a row's current
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
      // coordinates (e.g. the whole Gtk.ListView for EditorView.FileTree,
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
