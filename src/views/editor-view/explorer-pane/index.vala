namespace EditorView {
  /**
   * The sidebar's file tree, composition root for ExplorerPaneTree/
   * ExplorerPaneInlineEdit/ExplorerPaneDirWatcher/ExplorerPaneDragDrop — absorbs
   * the real FileTreeController entirely (its CRUD-to-Model translation,
   * context menu, and clipboard), the same way EditorPaneWidget absorbed
   * EditorController. Named ExplorerPane rather than FileTree: a bare
   * `new FileTree (root_path)` inside a class also named (even namespaced)
   * FileTree resolves to itself, not the Model — confirmed with a
   * standalone valac compile test, not assumed.
   *
   * Not ported: DevServer-only glue lives at the app composition level in
   * v1 (main.vala), not on FileTreeController itself, so there's nothing
   * of that sort to absorb here.
   */
  public class ExplorerPane : Object {
    private Gtk.Box root_box;
    private Gtk.Label root_label;
    private Gtk.ScrolledWindow scrolled_window;

    private FileTree model;
    private string root_path;

    private ExplorerPaneTree tree;
    private ExplorerPaneInlineEdit inline_edit;
    private ExplorerPaneDirWatcher dir_watcher;
    private ExplorerPaneDragDrop drag_drop;
    private FileDecoration.Registry decorations;
    private WorkspaceWatcher watcher;

    // The tree's own internal Cut/Copy clipboard — never the system
    // clipboard (copy_to_clipboard()/Copy Path are the only things that
    // touch that). Cutting dims the node (clipboard_node.is_cut, undone on
    // the next Cut/Copy or once pasted); copying doesn't dim anything and
    // survives multiple pastes, only a cut is consumed by its one paste.
    private FileNode? clipboard_node = null;

    public Gtk.Widget widget { get { return root_box; } }

    /** A file row was clicked. `open_permanent` is true for a double-click, false for a single-click (preview). */
    public signal void file_activated (string path, bool open_permanent);

    /** A New File was just created on disk (not a New Folder — nothing to open for those) — meant to be opened as a permanent tab right away. */
    public signal void file_created (string path);

    /** "Delete" was chosen for `path` — whether this needs an unsaved-changes confirmation first is the app's own call, since only it can see open tabs' state too; delete_entry() below does the actual deletion once that's decided. */
    public signal void delete_entry_requested (string path);

    /** `old_path` moved to `new_path` on disk — a Rename, or a Cut+Paste (menu or drag) actually moving something rather than copying it. */
    public signal void file_moved (string old_path, string new_path);

    public ExplorerPane (string root_path, WorkspaceWatcher watcher, FileDecoration.Registry decorations) throws Error {
      this.root_path = root_path;
      this.watcher = watcher;
      this.decorations = decorations;
      model = new FileTree (root_path);

      var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/editor-view/explorer-pane/index.ui");
      root_box = (Gtk.Box) builder.get_object ("root_box");
      root_label = (Gtk.Label) builder.get_object ("root_label");
      scrolled_window = (Gtk.ScrolledWindow) builder.get_object ("scrolled_window");

      tree = new ExplorerPaneTree ();
      scrolled_window.child = tree.widget;
      root_label.label = model.root.name;
      tree.populate (model.root);

      inline_edit = new ExplorerPaneInlineEdit (tree);
      dir_watcher = new ExplorerPaneDirWatcher (tree, watcher);
      drag_drop = new ExplorerPaneDragDrop (tree);

      tree.file_activated.connect ((path, open_permanent) => file_activated (path, open_permanent));
      tree.children_load_requested.connect (on_children_load_requested);
      tree.context_menu_requested.connect (show_context_menu);
      // Same two entry points the "Rename…"/"Delete" context menu items
      // already use (see show_context_menu()) — F2/Delete are just
      // another way to reach them, keyboard-only, no menu involved.
      tree.rename_requested.connect ((node) => inline_edit.request_rename (node));
      tree.delete_requested.connect ((node) => delete_entry_requested (node.path));

      inline_edit.create_entry_requested.connect (on_create_entry_requested);
      inline_edit.rename_entry_requested.connect (on_rename_entry_requested);

      watcher.directory_changed.connect (on_directory_changed);
      drag_drop.moved_via_drag.connect ((source_path, target_path) => do_paste (source_path, true, target_path));

      decorations.changed.connect (on_decorations_changed);
    }

    /** "Reveal in Sidebar" from a tab's context menu. */
    public void reveal_path (string path) {
      tree.reveal_path (path);
    }

    /** The width (in px) that would show every currently visible row's full label with nothing clipped — used to size the sidebar when first linking a folder. */
    public double get_optimal_width () {
      return tree.get_optimal_width ();
    }

    /** Re-reads every directory already loaded — for when change events may have been lost (the window was in the background, a watch failed to start). */
    public void resync () {
      var loaded_paths = new GenericArray<string> ();
      model.each_loaded_node ((node) => {
        if (node.is_directory && node.children_loaded) {
          loaded_paths.add (node.path);
        }
      });
      foreach (var path in loaded_paths) {
        on_directory_changed (path);
      }
    }

    /** Cancels every pending debounce timer, and disconnects from `watcher` and `decorations` (both owned by MainWindow, both outlive this pane) — call before discarding this pane (e.g. "Close Folder", or replacing it with a freshly-opened one). Without this, the closure this pane never held a matching disconnect for would keep it (and its whole FileTree) alive for as long as `decorations` itself is, and could still call tree.rebind() on a pane the rest of the app has already discarded. */
    public void close () {
      dir_watcher.close ();
      watcher.directory_changed.disconnect (on_directory_changed);
      decorations.changed.disconnect (on_decorations_changed);
    }

    /**
     * Answers ExplorerPaneTree.children_load_requested() synchronously —
     * the one place FileTree's own lazy, one-level-at-a-time scanning
     * actually gets triggered. A directory scanned on an earlier expand
     * is read again: nothing reports what changed inside an unwatched
     * one (ignored by git, or outside a repository) while it sat
     * collapsed.
     *
     * Also stamps each newly materialized child's own decoration from the
     * current snapshot — this fires strictly before any of those
     * children's rows ever bind (children_load_requested() runs
     * synchronously inside on_create_model_raw(), before it builds that
     * row's own ListStore), so the very first bind() any of them gets
     * already shows the right decoration, with no rebind() round-trip
     * needed.
     */
    private void on_children_load_requested (FileNode node) {
      try {
        if (node.children_loaded) {
          model.rescan_children (node);
        } else {
          model.ensure_children_loaded (node);
        }
      } catch (Error e) {
        show_error (_("Couldn’t read “%s”: %s").printf (node.name, e.message));
        return;
      }

      stamp_children_decorations (node);
    }

    private void stamp_children_decorations (FileNode node) {
      for (uint i = 0; i < node.children.length; i++) {
        var child = node.children[i];
        child.decoration = decorations.decoration_for (child.path, child.is_directory);
      }
    }

    /** A plugin's own decorations changed somewhere — re-stamps every already-materialized node from the fresh registry snapshot, pushing only the ones that actually changed into their own row (ExplorerPaneTree.rebind() is a no-op for anything not currently expanded/visible). */
    private void on_decorations_changed () {
      model.each_loaded_node ((node) => {
        var new_decoration = decorations.decoration_for (node.path, node.is_directory);
        if (decoration_equal (node.decoration, new_decoration)) {
          return;
        }
        node.decoration = new_decoration;
        tree.rebind (node);
      });
    }

    private static bool decoration_equal (FileDecoration.State? a, FileDecoration.State? b) {
      if (a == b) {
        return true; // same reference, or both null
      }
      if (a == null || b == null) {
        return false;
      }
      return a.tone == b.tone && a.tooltip == b.tooltip;
    }

    /**
     * An external change to a watched directory's own immediate children
     * (something this pane didn't do itself — those already update the
     * tree directly, e.g. on_create_entry_requested()).
     */
    private void on_directory_changed (string path) {
      var node = model.find (path);
      if (node == null || !node.children_loaded) {
        return; // never shown, or gone (deleted/renamed away) before this event was handled
      }

      try {
        model.rescan_children (node);
      } catch (Error e) {
        return; // the directory itself was likely just deleted/renamed away
      }

      // An entry new to the tree binds its row inside refresh_children().
      stamp_children_decorations (node);
      tree.refresh_children (path, node.children);
      inline_edit.on_children_refreshed (path);
    }

    private void on_create_entry_requested (string parent_path, string name, bool is_directory) {
      var parent = model.find (parent_path);
      if (parent == null) {
        inline_edit.discard_pending_entry ();
        return;
      }

      FileNode node;
      try {
        node = model.create_child (parent, name, is_directory);
      } catch (Error e) {
        inline_edit.discard_pending_entry ();
        show_error (_("Couldn’t create “%s”: %s").printf (name, e.message));
        return;
      }

      tree.refresh_children (parent_path, parent.children);
      inline_edit.on_children_refreshed (parent_path);
      if (!is_directory) {
        file_created (node.path);
      }
    }

    private void on_rename_entry_requested (string path, string new_name) {
      var node = model.find (path);
      var parent = node == null ? null : model.find (Path.get_dirname (path));
      if (node == null || parent == null) {
        inline_edit.cancel_rename ();
        return;
      }

      FileNode renamed;
      try {
        renamed = model.rename_child (parent, node, new_name);
      } catch (Error e) {
        inline_edit.cancel_rename ();
        show_error (_("Couldn’t rename “%s”: %s").printf (node.name, e.message));
        return;
      }

      tree.refresh_children (parent.path, parent.children);
      inline_edit.on_children_refreshed (parent.path);
      // refresh_children() just replaced `node` with `renamed` in the
      // tree's own model, invalidating the selection — see
      // ExplorerPaneTree.focus_path()'s own comment for why this matters.
      tree.focus_path (renamed.path);
      file_moved (path, renamed.path);
    }

    /** Actually deletes `path` — called by the app once it's decided it's safe to (a folder, or a file with no dirty open tab, or one whose unsaved changes the user explicitly confirmed losing). */
    public void delete_entry (string path) {
      var node = model.find (path);
      var parent = node == null ? null : model.find (Path.get_dirname (path));
      if (node == null || parent == null) {
        return;
      }

      try {
        model.delete_child (parent, node);
      } catch (Error e) {
        show_error (_("Couldn’t delete “%s”: %s").printf (node.name, e.message));
        return;
      }

      tree.refresh_children (parent.path, parent.children);
      inline_edit.on_children_refreshed (parent.path);
    }

    /** The system's own confirmation for deleting `filename` while it has unsaved changes open — Cancel, or lose them and delete anyway. */
    public async bool confirm_delete_with_unsaved_changes (string filename) {
      return yield Dialogs.confirm_destructive (
        widget,
        _("You are deleting a file with unsaved changes"),
        _("Your changes to “%s” will be lost if you don't save them.").printf (filename),
        _("Move to Trash")
      );
    }

    private void do_paste (string source_path, bool is_cut, string target_path) {
      var source = model.find (source_path);
      var source_parent = source == null ? null : model.find (Path.get_dirname (source_path));
      var target = model.find (target_path);
      if (source == null || source_parent == null || target == null) {
        return;
      }

      FileNode result;
      try {
        if (is_cut) {
          result = model.move_child (source_parent, source, target);
        } else {
          result = model.copy_child (source, target);
        }
      } catch (Error e) {
        show_error (_("Couldn’t paste “%s”: %s").printf (source.name, e.message));
        return;
      }

      tree.refresh_children (target.path, target.children);
      inline_edit.on_children_refreshed (target.path);
      if (is_cut) {
        tree.refresh_children (source_parent.path, source_parent.children);
        inline_edit.on_children_refreshed (source_parent.path);
        // A Copy leaves the original right where it was — nothing moved
        // for any tab open on it to care about; only a Cut actually needs
        // this.
        file_moved (source_path, result.path);
      }

      if (is_cut) {
        clipboard_node = null;
      }
    }

    private void open_in_files (string path) {
      try {
        AppInfo.launch_default_for_uri (File.new_for_path (path).get_uri (), null);
      } catch (Error e) {
        show_error (_("Couldn’t open “%s” in the file manager: %s").printf (path, e.message));
      }
    }

    private void open_in_terminal (string path) {
      foreach (var command in TERMINAL_COMMANDS) {
        if (Environment.find_program_in_path (command) == null) {
          continue;
        }

        var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
        launcher.set_cwd (path);
        string[] argv = { command };
        try {
          launcher.spawnv (argv);
        } catch (Error e) {
          show_error (_("Couldn’t launch %s: %s").printf (command, e.message));
        }
        return;
      }

      show_error (_("No terminal emulator was found on this system."));
    }

    // Tried in this order for "Open in Terminal"; the first one actually
    // installed wins. Spawned with its working directory set directly
    // (see open_in_terminal()) rather than passed a
    // `--working-directory`-style flag, since those differ per terminal and
    // a process's own cwd doesn't.
    private const string[] TERMINAL_COMMANDS = { "gnome-terminal", "kgx", "konsole", "xfce4-terminal", "xterm" };

    private void copy_to_clipboard (string text) {
      widget.get_clipboard ().set_text (text);
    }

    /** `path`, relative to the workspace root — `path` itself if it's somehow outside it. */
    private string relative_path (string path) {
      var prefix = root_path + "/";
      return path.has_prefix (prefix) ? path.substring (prefix.length) : path;
    }

    /**
     * `target` null means the workspace root (background click). A
     * directory (the root included) can hold a New File/Folder, be opened
     * in a file manager/terminal, and — the root aside — Cut/Copy an
     * existing folder; either kind of directory is also a valid Paste
     * destination, shown only when the clipboard actually holds something.
     * A file only has Cut/Copy. Rename/Delete/Copy Path/Copy Relative Path
     * apply to any *existing* entry, just not the workspace root itself.
     */
    private void show_context_menu (FileNode? target, double x, double y) {
      var context_path = target == null ? model.root.path : target.path;
      var has_clipboard = clipboard_node != null;

      ContextMenu.popup_at (tree.widget, x, y, (popover, box) => {
        if (target == null || target.is_directory) {
          box.append (ContextMenu.item (_("New File…"), () => inline_edit.request_new_entry (target, false), popover));
          box.append (ContextMenu.item (_("New Folder…"), () => inline_edit.request_new_entry (target, true), popover));
          box.append (ContextMenu.separator ());
          box.append (ContextMenu.item (_("Open in Files"), () => open_in_files (context_path), popover));
          box.append (ContextMenu.item (_("Open in Terminal"), () => open_in_terminal (context_path), popover));

          if (target != null || has_clipboard) {
            box.append (ContextMenu.separator ());
          }
          if (target != null) {
            box.append (ContextMenu.item (_("Cut"), () => request_cut (target), popover));
            box.append (ContextMenu.item (_("Copy"), () => request_copy (target), popover));
          }
          if (has_clipboard) {
            box.append (ContextMenu.item (_("Paste"), () => request_paste (target), popover));
          }
        } else {
          box.append (ContextMenu.item (_("Cut"), () => request_cut (target), popover));
          box.append (ContextMenu.item (_("Copy"), () => request_copy (target), popover));
        }

        // Renaming/deleting the workspace root itself isn't offered — only an actual file/folder target has this group.
        if (target != null) {
          box.append (ContextMenu.separator ());
          box.append (ContextMenu.item (_("Rename…"), () => inline_edit.request_rename (target), popover));
          box.append (ContextMenu.item (_("Delete"), () => delete_entry_requested (target.path), popover));
        }

        box.append (ContextMenu.separator ());
        box.append (ContextMenu.item (_("Copy Path"), () => copy_to_clipboard (context_path), popover));
        box.append (ContextMenu.item (_("Copy Relative Path"), () => copy_to_clipboard (relative_path (context_path)), popover));
      });
    }

    /**
     * Cut/Copy/Paste here are the tree's own internal concept, deliberately
     * not the system clipboard (that's what copy_to_clipboard() above,
     * used only by Copy Path/Copy Relative Path, is for) — there's no
     * interoperability need with an external file manager, so no reason to
     * take on a real clipboard format for it.
     */
    private void request_cut (FileNode target) {
      set_clipboard (target, true);
    }

    private void request_copy (FileNode target) {
      set_clipboard (target, false);
    }

    private void set_clipboard (FileNode node, bool is_cut) {
      clear_cut_dim ();
      clipboard_node = node;
      if (is_cut) {
        node.is_cut = true;
        tree.rebind (node);
      }
    }

    private void request_paste (FileNode? target) {
      if (clipboard_node == null) {
        return;
      }
      do_paste (clipboard_node.path, clipboard_node.is_cut, target == null ? model.root.path : target.path);
    }

    /** Undims whatever's currently on the Cut clipboard, if anything — called before replacing it with a new Cut/Copy. */
    private void clear_cut_dim () {
      if (clipboard_node == null || !clipboard_node.is_cut) {
        return;
      }
      clipboard_node.is_cut = false;
      tree.rebind (clipboard_node);
    }

    public void show_error (string message) {
      Dialogs.show_error (widget, message);
    }
  }
}
