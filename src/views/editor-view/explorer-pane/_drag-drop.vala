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
   * an actual move. Hovering a *file* instead redirects to its own parent
   * folder — highlighted and dropped onto the same way — since a file has
   * nowhere of its own to receive a drop; see drag_target_node()'s own
   * doc comment.
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
     * `source_paths` were dropped onto `target_path` (a directory — the
     * workspace root included): the dragged row, or the whole selection it
     * was part of, less what already sits there or would land inside
     * itself. Not fired when nothing is left — a folder let go onto itself,
     * or back into the directory it's already in, is the user changing
     * their mind mid-drag, not a move.
     */
    public signal void moved_via_drag (string[] source_paths, string target_path);

    public ExplorerPaneDragDrop (ExplorerPaneTree tree) {
      this.tree = tree;

      FileDrag.make_source (tree.widget, (x, y) => {
        var widget = tree.row_widget_at (x, y);
        var row = tree.row_at (x, y);
        if (widget == null || row == null || row.bound_node == null) {
          return null;
        }
        return new FileDragCandidate (dragged_paths (row.bound_node), widget);
      });

      var drop_target = new Gtk.DropTarget (typeof (FileDragPayload), Gdk.DragAction.MOVE);
      drop_target.motion.connect (on_drag_motion);
      drop_target.leave.connect (on_drag_leave);
      drop_target.drop.connect (on_drag_drop);
      tree.widget.add_controller (drop_target);
    }

    /**
     * Highlights whatever row represents the actual drop target (see
     * drag_target_widget()'s own doc comment) and starts (or restarts, on
     * moving to a different row) the auto-expand timer for it. Every hover
     * is now a valid drop target — a directory, a file (redirects to its
     * own parent), or the tree's own background (the workspace root) — so
     * this always allows MOVE, unlike a plain Gtk.DropTarget's own default
     * of rejecting whatever its snapshot function doesn't explicitly opt
     * into.
     */
    private Gdk.DragAction on_drag_motion (double x, double y) {
      var widget = tree.row_widget_at (x, y);
      var node = tree.node_at (x, y);

      var target_widget = drag_target_widget (widget, node);
      if (target_widget != drag_hover_widget) {
        tree.set_drag_hover (drag_hover_widget, false);
        drag_hover_widget = target_widget;
        tree.set_drag_hover (drag_hover_widget, true);
      }
      reset_hover_expand_timer (tree.row_at (x, y), node);

      return Gdk.DragAction.MOVE;
    }

    /**
     * The row to highlight for whatever's currently under the pointer —
     * `node`'s own row for a directory (already the widget the pointer hit
     * directly, `widget_at_pointer`, no separate lookup needed), its
     * *parent's* row for a file (a file has nowhere of its own to receive
     * a drop — see drag_target_path()), or nothing whenever there's no
     * row to point at (`node == null`, the tree's own background, meaning
     * the workspace root, which isn't a row itself). A file's own parent
     * is always already realized as a real row: the file being visible at
     * all already means that parent is expanded.
     */
    private Gtk.Widget? drag_target_widget (Gtk.Widget? widget_at_pointer, FileNode? node) {
      if (node == null) {
        return null;
      }
      if (node.is_directory) {
        return tree.native_row_widget (widget_at_pointer);
      }
      return tree.native_row_widget (tree.row_widget_for_path (Path.get_dirname (node.path)));
    }

    /** The directory a drop under `node` actually lands in: `node` itself if it's already a directory, its own parent if it's a file, or the workspace root over the tree's empty background (`node == null`). */
    private string drag_target_path (FileNode? node) {
      if (node == null) {
        return tree.root_node.path;
      }
      return node.is_directory ? node.path : Path.get_dirname (node.path);
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

    /** The dragged row's path alone — or, when that row is one of several selected, every selected path, a folder's contents counted once. */
    private string[] dragged_paths (FileNode picked) {
      if (!tree.is_in_multi_selection (picked)) {
        return { picked.path };
      }
      string[] paths = {};
      foreach (var node in tree.selected_nodes ()) {
        paths += node.path;
      }
      return FileTree.top_level (paths);
    }

    private bool on_drag_drop (Value value, double x, double y) {
      tree.set_drag_hover (drag_hover_widget, false);
      drag_hover_widget = null;
      cancel_hover_expand_timer ();

      var payload = value.get_object () as FileDragPayload;
      if (payload == null) {
        return false;
      }
      payload.accepted = true;

      var target = tree.node_at (x, y);
      var target_path = drag_target_path (target);

      // Left out of a drop: a folder let go onto itself, or anywhere
      // inside itself; and anything dropped back into the folder it is
      // already in (a file onto itself, or onto a sibling, resolves to
      // that same parent). With one path that is the user changing their
      // mind; within a selection the rest still moves.
      string[] moving = {};
      foreach (var path in payload.paths) {
        bool into_itself = target_path == path || target_path.has_prefix (path + "/");
        if (!into_itself && Path.get_dirname (path) != target_path) {
          moving += path;
        }
      }
      if (moving.length > 0) {
        moved_via_drag (moving, target_path);
      }
      return true;
    }
  }
}
