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
   *
   * `on_window_drop`, if given, fires for a drop outside every window of
   * this app, told apart by the FileDragRootWindowDrop the drag then
   * offers alongside the payload (a drop on the desktop or on another
   * GTK app's bare window reads it, or performs), by a cancel with ERROR
   * (Wayland's only word for "no one took it", never NO_TARGET), and by
   * MainWindow's own catch-all target, which marks the payload `accepted`
   * so a drop inside one of ours doesn't count.
   */
  public static Gtk.DragSource make_source (Gtk.Widget attach_to, owned FileDragResolver resolve, owned FileDragWindowDrop? on_window_drop = null) {
    var source = new Gtk.DragSource ();
    source.actions = Gdk.DragAction.MOVE;

    FileDragCandidate? candidate = null;
    FileDragPayload? payload = null;
    FileDragRootWindowDrop? root_drop = null;
    bool drop_performed = false;
    double press_x = 0;
    double press_y = 0;
    source.prepare.connect ((x, y) => {
      candidate = resolve (x, y);
      payload = null;
      root_drop = null;
      drop_performed = false;
      press_x = x;
      press_y = y;
      if (candidate == null) {
        return null;
      }

      payload = new FileDragPayload (candidate.paths) { window_drop = on_window_drop != null };
      var value = Value (typeof (FileDragPayload));
      value.set_object (payload);
      var provider = new Gdk.ContentProvider.for_value (value);
      if (on_window_drop == null) {
        return provider;
      }
      root_drop = new FileDragRootWindowDrop ();
      return new Gdk.ContentProvider.union ({ provider, root_drop });
    });

    source.drag_begin.connect ((drag) => {
      if (candidate == null) {
        return;
      }
      drag.drop_performed.connect (() => drop_performed = true);

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
        show_icon (drag, candidate, hot_x, hot_y);
      } else {
        source.set_icon (new Gtk.WidgetPaintable (candidate.preview_widget), hot_x, hot_y);
      }
    });

    source.drag_end.connect ((drag, delete_data) => {
      if (on_window_drop == null || payload == null) {
        return;
      }
      if ((drop_performed || root_drop.read) && !payload.accepted) {
        on_window_drop (candidate);
      }
    });
    source.drag_cancel.connect ((drag, reason) => {
      if (on_window_drop == null) {
        return false;
      }
      if (reason != Gdk.DragCancelReason.NO_TARGET && reason != Gdk.DragCancelReason.ERROR) {
        return false;
      }
      on_window_drop (candidate);
      // Handled: GTK then ends the drag as a success, no "snap back".
      return true;
    });

    attach_to.add_controller (source);
    return source;
  }

  /** `candidate.icon_widget` as the real widget under the pointer, glued at (`hot_x`, `hot_y`). */
  private static void show_icon (Gdk.Drag drag, FileDragCandidate candidate, int hot_x, int hot_y) {
    drag.set_hotspot (hot_x, hot_y);
    var icon = DragIcons.for_drag (drag);
    // The icon is its own root, so the theme's variables reach it only
    // through its own `dark` class (see tools/compile-ui-theme.py) —
    // set before the child goes in, or its first style is the light
    // one and the switch to dark plays as a CSS transition.
    var window = candidate.preview_widget.get_root () as Gtk.Widget;
    if (window != null && window.has_css_class ("dark")) {
      icon.add_css_class ("dark");
    }
    icon.child = candidate.icon_widget;
  }
}
