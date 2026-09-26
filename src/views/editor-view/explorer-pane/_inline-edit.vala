namespace EditorView {
  /**
   * The tree's own inline New File/Folder and Rename editing — split out of
   * the real EditorView.FileTree, which mixed this state into the same
   * class as rendering/selection. Reacts to ExplorerPaneTree's row_edit_committed/
   * row_edit_cancelled (re-emitted from whichever ExplorerPaneTreeRow is currently
   * being edited) and asks it to splice/remove/rebind the row being edited;
   * it never renders anything itself.
   */
  public class ExplorerPaneInlineEdit : Object {
    private ExplorerPaneTree tree;

    /** The placeholder (New File/Folder) or existing node (Rename) currently being edited, or null. */
    private FileNode? editing_node = null;

    /** Set only while editing_node is a not-yet-created placeholder — tells on_edit_committed/on_edit_cancelled this is a create, not a rename. */
    private string? pending_parent_path = null;

    /** A New File/Folder's name was confirmed non-empty — create it at `parent_path`. */
    public signal void create_entry_requested (string parent_path, string name, bool is_directory);

    /** An existing entry's new name was confirmed, and differs from its current one. */
    public signal void rename_entry_requested (string path, string new_name);

    public ExplorerPaneInlineEdit (ExplorerPaneTree tree) {
      this.tree = tree;
      tree.row_edit_committed.connect (on_edit_committed);
      tree.row_edit_cancelled.connect (on_edit_cancelled);
    }

    /**
     * Starts naming a New File/Folder inline: expands `target` first if it's
     * a collapsed folder, then splices a placeholder FileNode — rendered as
     * an editable row by ExplorerPaneTreeRow.bind() — into that directory's store.
     */
    public void request_new_entry (FileNode? target, bool is_directory) {
      var parent = tree.resolve_parent (target);
      var store = tree.store_for (parent.path);
      if (store == null) {
        return;
      }

      var placeholder = new FileNode ("", "", is_directory);
      placeholder.is_editing_name = true;
      editing_node = placeholder;
      pending_parent_path = parent.path;
      tree.editing_active = true;

      // Directories first, then files (FileTree.precedes' own order): a new
      // folder goes at the very top, a new file after the last existing
      // directory — never position 0 regardless of kind.
      uint insert_index = 0;
      if (!is_directory) {
        while (insert_index < parent.children.length && parent.children[insert_index].is_directory) {
          insert_index++;
        }
      }
      store.insert (insert_index, placeholder);
    }

    /**
     * Starts renaming `target` inline: ExplorerPaneTreeRow.bind() pre-fills and fully
     * selects its current name once is_editing_name is set. pending_parent_path
     * stays null here — that's what tells on_edit_committed/on_edit_cancelled
     * this is a rename, not a create.
     */
    public void request_rename (FileNode target) {
      editing_node = target;
      tree.editing_active = true;
      target.is_editing_name = true;
      tree.rebind (target);
    }

    /**
     * ExplorerPaneTreeRow doesn't distinguish a New File/Folder commit from a Rename
     * one — pending_parent_path being set says which this is. Deferred to
     * the next main-loop iteration, not run directly: this fires from the
     * edit entry's own focus-leave, still inside GTK's own dispatch of
     * whatever click caused it — removing the placeholder's row from its
     * ListStore synchronously from in there tears down a widget GTK is
     * still mid-way through processing that same click against (found the
     * hard way, in the real EditorView.FileTree: a repeated
     * `gtk_widget_get_parent: assertion 'GTK_IS_WIDGET (widget)' failed` crash).
     */
    private void on_edit_committed (string name) {
      Idle.add (() => {
        if (editing_node == null) {
          return Source.REMOVE;
        }
        if (pending_parent_path != null) {
          create_entry_requested (pending_parent_path, name, editing_node.is_directory);
        } else if (name != editing_node.name) {
          rename_entry_requested (editing_node.path, name);
        } else {
          cancel_rename (); // committed but unchanged — same as cancelling
        }
        return Source.REMOVE;
      });
    }

    /** Deferred for the same reason on_edit_committed() is — see its comment. */
    private void on_edit_cancelled () {
      Idle.add (() => {
        if (pending_parent_path != null) {
          discard_pending_entry ();
        } else if (editing_node != null) {
          cancel_rename ();
        }
        return Source.REMOVE;
      });
    }

    /** Removes the still-pending New File/Folder placeholder — after a cancelled edit, or called by ExplorerPane when creating it on disk failed. */
    public void discard_pending_entry () {
      if (editing_node == null || pending_parent_path == null) {
        return;
      }

      var store = tree.store_for (pending_parent_path);
      uint position = 0;
      if (store != null && store.find (editing_node, out position)) {
        store.remove (position);
      }

      clear_editing_state ();
    }

    /** Reverts the still-pending Rename back to a normal display row — after a cancelled/no-op edit, or called by ExplorerPane when renaming on disk failed. */
    public void cancel_rename () {
      if (editing_node == null) {
        return;
      }

      var node = editing_node;
      clear_editing_state ();
      node.is_editing_name = false;
      tree.rebind (node);
    }

    /**
     * Called by ExplorerPane once refresh_children() actually synced
     * `parent_path`'s row to the new, saved state — clears whichever of the
     * now-fulfilled pending placeholder or renaming node belongs to that
     * directory, since the fresh children array never includes a
     * placeholder and already has the renamed node's own replacement.
     */
    public void on_children_refreshed (string parent_path) {
      if (pending_parent_path == parent_path) {
        clear_editing_state ();
      } else if (editing_node != null && Path.get_dirname (editing_node.path) == parent_path) {
        editing_node = null;
      }
    }

    private void clear_editing_state () {
      editing_node = null;
      pending_parent_path = null;
      tree.editing_active = false;
    }
  }
}
