namespace EditorView {
  /**
   * Dragging a row here is a Cut+Paste in one gesture — split out of the
   * real EditorView.FileTree's setup_drag_drop(), which mixed this into the
   * same class as rendering/selection. Wires both sides on `tree.widget`
   * itself, not per-row (matching every other primary-button controller
   * ExplorerPaneTree's own click handlers use — a per-row gesture would race
   * GtkListView's built-in click handling the same way those already found
   * out): FileDrag.make_source() resolves the dragged row on drag-start;
   * the Gtk.DropTarget highlights the hovered folder, auto-expands it after
   * a delay, and emits moved_via_drag on drop for ExplorerPane to turn into
   * an actual move.
   */
  public class ExplorerPaneDragDrop : Object {
    // Long enough that just passing over a folder while aiming for one of
    // its own children doesn't auto-expand every folder along the way;
    // short enough that deliberately hovering to reveal nested content
    // doesn't feel like waiting.
    private const uint HOVER_EXPAND_MS = 1500;

    private ExplorerPaneTree tree;
    private Gtk.Widget? drag_hover_widget = null;
    private uint hover_expand_timeout_id = 0;

    /**
     * `source_path` was dropped onto `target_path` (a directory — the
     * workspace root included). Not fired for a folder dropped onto itself,
     * or back into the directory it's already in — both are treated as the
     * user changing their mind mid-drag, not a real move attempt.
     */
    public signal void moved_via_drag (string source_path, string target_path);

    public ExplorerPaneDragDrop (ExplorerPaneTree tree) {
      this.tree = tree;

      FileDrag.make_source (tree.widget, (x, y) => {
        var widget = tree.row_widget_at (x, y);
        var row = tree.row_at (x, y);
        if (widget == null || row == null || row.bound_node == null) {
          return null;
        }
        return new FileDragCandidate (row.bound_node.path, widget);
      });

      var drop_target = new Gtk.DropTarget (typeof (FileDragPayload), Gdk.DragAction.MOVE);
      drop_target.motion.connect (on_drag_motion);
      drop_target.leave.connect (on_drag_leave);
      drop_target.drop.connect (on_drag_drop);
      tree.widget.add_controller (drop_target);
    }

    /**
     * Highlights the folder row directly under the pointer and starts (or
     * restarts, on moving to a different row) the auto-expand timer for it.
     * Only a directory — or the tree's own background, meaning the
     * workspace root — is a valid drop target; hovering a file row shows
     * the "no drop" cursor and never highlights, since dropping there would
     * just be rejected by on_drag_drop() below.
     */
    private Gdk.DragAction on_drag_motion (double x, double y) {
      var widget = tree.row_widget_at (x, y);
      var node = tree.node_at (x, y);

      var target_widget = (node != null && node.is_directory) ? tree.native_row_widget (widget) : null;
      if (target_widget != drag_hover_widget) {
        tree.set_drag_hover (drag_hover_widget, false);
        drag_hover_widget = target_widget;
        tree.set_drag_hover (drag_hover_widget, true);
      }
      reset_hover_expand_timer (tree.row_at (x, y), node);

      if (widget == null) {
        return Gdk.DragAction.MOVE; // background — drop lands in the workspace root
      }
      return node != null && node.is_directory ? Gdk.DragAction.MOVE : 0;
    }

    private void on_drag_leave () {
      tree.set_drag_hover (drag_hover_widget, false);
      drag_hover_widget = null;
      cancel_hover_expand_timer ();
    }

    /** Schedules HOVER_EXPAND_MS from now to expand `row`, unless it's already expanded (or isn't a directory) — cancels whatever was already pending for the previous row first, so only ever the *current* hover can fire. */
    private void reset_hover_expand_timer (ExplorerPaneTreeRow? row, FileNode? node) {
      cancel_hover_expand_timer ();
      if (row == null || row.bound_row == null || node == null || !node.is_directory || row.bound_row.expanded) {
        return;
      }

      var list_row = row.bound_row;
      hover_expand_timeout_id = Timeout.add (HOVER_EXPAND_MS, () => {
        hover_expand_timeout_id = 0;
        tree.set_expanded (list_row, node, true);
        return Source.REMOVE;
      });
    }

    private void cancel_hover_expand_timer () {
      if (hover_expand_timeout_id != 0) {
        Source.remove (hover_expand_timeout_id);
        hover_expand_timeout_id = 0;
      }
    }

    private bool on_drag_drop (Value value, double x, double y) {
      tree.set_drag_hover (drag_hover_widget, false);
      drag_hover_widget = null;
      cancel_hover_expand_timer ();

      var payload = value.get_object () as FileDragPayload;
      if (payload == null) {
        return false;
      }

      var target = tree.node_at (x, y);
      if (target != null && !target.is_directory) {
        return false;
      }

      // Dropped a folder directly onto itself — almost always the user
      // starting a drag, changing their mind, and letting go right back
      // where they picked it up, not a real move attempt.
      if (target != null && target.path == payload.path) {
        return true;
      }

      var target_path = target == null ? tree.root_node.path : target.path;

      // Dropped back into the folder it's already in — also a no-op.
      if (Path.get_dirname (payload.path) == target_path) {
        return true;
      }

      moved_via_drag (payload.path, target_path);
      return true;
    }
  }
}
