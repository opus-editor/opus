// The gtk4 vapi types Gtk.TreeListModel's constructor create_func as taking
// a GLib.Object item, but the real C typedef takes an untyped gpointer —
// generating a GCC incompatible-pointer-types warning on every build. This
// raw binding matches the actual C signature exactly, sidestepping the vapi
// entirely instead of living with the warning.
[CCode (cname = "GtkTreeListModelCreateModelFunc", has_target = false)]
private delegate GLib.ListModel? RawCreateModelFunc (void* item, void* user_data);

[CCode (cname = "gtk_tree_list_model_new")]
private extern static Gtk.TreeListModel tree_list_model_new_raw (
  owned GLib.ListModel root, bool passthrough, bool autoexpand,
  RawCreateModelFunc create_func, void* user_data, GLib.DestroyNotify? user_destroy
);

namespace EditorView {
  /**
   * Gtk-backed facade for the sidebar's file tree: a Gtk.ListView over a
   * Gtk.TreeListModel, with ExplorerPaneTreeRow as its row widget — rendering,
   * selection, and keyboard navigation only. Split out of the real
   * EditorView.FileTree (which also carried the CRUD-to-Model translation,
   * context menu, and inline-edit — those live in ExplorerPane/
   * ExplorerPaneInlineEdit now, composed alongside this).
   *
   * The tree is built eagerly from the FileNode handed to populate(): every
   * directory's children are already known, so the model's create-func
   * never touches the filesystem, it just wraps the already-loaded
   * children of the directory being expanded.
   */
  public class ExplorerPaneTree : Object {
    private Gtk.ListView list_view;
    private Gtk.TreeListModel? tree_model;
    private Gtk.SingleSelection? selection;

    // Set for the one selection_changed this arrow key's own native move
    // binding is about to cause, then cleared — see on_selection_changed()'s
    // own comment for why this exists at all.
    private bool navigated_by_keyboard = false;

    // "Symbols" hardcoded for now — a future "pick a different icon
    // theme" feature would swap this constructor call (or make it
    // settable), not anything downstream: every row already resolves its
    // own icon through this one instance, theme-agnostically.
    private IconTheme icon_theme = new IconTheme.symbols ();

    // One entry per directory whose children have been turned into a
    // ListStore — the root's from populate(), every other one lazily as
    // on_create_model_raw materializes it on first expand. Kept around (not
    // just handed to Gtk.TreeListModel and forgotten) so a New File/Folder
    // can be spliced straight into the right one and have it show up
    // immediately.
    private HashTable<string, ListStore> stores_by_path = new HashTable<string, ListStore> (str_hash, str_equal);

    // Bluish translucent highlight for the folder row currently under a
    // dragged file/folder — toggled by ExplorerPaneDragDrop, which doesn't
    // track it itself: it's pointer-position state, unrelated to which
    // FileNode a recycled row happens to be bound to right now.
    private const string DRAG_HOVER_CSS_CLASS = "drag-hover";

    // "Reveal in Sidebar" flash — a warm highlight added to the target
    // row then removed shortly after, so the CSS transition on the row's
    // own background-color (see the CSS below) fades it back out on its
    // own.
    private const string REVEAL_FLASH_CSS_CLASS = "reveal-flash";
    private const string REVEAL_FLASH_TRANSITION_CSS_CLASS = "reveal-flash-fading";
    private const uint REVEAL_FLASH_HOLD_MS = 150;
    private const uint REVEAL_FLASH_TRANSITION_MS = 700; // matches the CSS transition's own duration

    public Gtk.Widget widget { get { return list_view; } }

    /** The linked workspace's own root node — set once populate() actually knows it. */
    public FileNode? root_node { get; private set; }

    /** True while a New File/Folder or Rename is being typed inline — set by ExplorerPaneInlineEdit, read here so Left/Right lets the text cursor move instead of navigating the tree. */
    public bool editing_active = false;

    /**
     * A file row was clicked. `open_permanent` is true for a double-click
     * (open/promote to a permanent tab), false for a single-click (preview).
     */
    public signal void file_activated (string path, bool open_permanent);

    /** A directory's expanded state actually changed (not fired for a no-op re-assignment) — `expanded` true means its children are now visible. */
    public signal void directory_expanded_changed (string path, bool expanded);

    /**
     * `node`'s row is about to show its children for the first time and
     * has no data for them yet — fired synchronously from
     * on_create_model_raw(), right before it builds that row's own
     * ListStore. The handler is expected to mutate `node` in place
     * (FileTree.ensure_children_loaded()) before returning, since GTK's
     * own create-func is itself synchronous.
     */
    public signal void children_load_requested (FileNode node);

    /** A row's own inline edit (New File/Folder or Rename) was confirmed with a non-empty name — re-emitted from whichever ExplorerPaneTreeRow is currently editing. */
    public signal void row_edit_committed (string name);

    /** A row's own inline edit was cancelled — re-emitted the same way. */
    public signal void row_edit_cancelled ();

    /** Right click landed at `(x, y)` — on `target`, or on the tree's own empty background (`target == null`, meaning the workspace root). */
    public signal void context_menu_requested (FileNode? target, double x, double y);

    /** F2 pressed with `node` selected — same entry point the "Rename…" context menu item already uses. */
    public signal void rename_requested (FileNode node);

    /** Delete pressed with `node` selected — same entry point the "Delete" context menu item already uses. */
    public signal void delete_requested (FileNode node);

    public ExplorerPaneTree () {
      var factory = new Gtk.SignalListItemFactory ();
      factory.setup.connect (on_setup);
      factory.bind.connect (on_bind);
      factory.unbind.connect (on_unbind);

      list_view = new Gtk.ListView (null, factory);
      // Matches the sidebar header's background instead of the default
      // "view" (card-like) background — same class Nautilus uses for its
      // own sidebar list.
      list_view.add_css_class ("navigation-sidebar");
      // Built-in dense/treeview-like row style (less vertical padding per
      // row than the list's default).
      list_view.add_css_class ("data-table");

      // selection-changed drives preview (fires reliably on every single
      // click); `activate`, GTK's own native, battle-tested double-click
      // recognizer, drives promotion. Neither reimplements or races the
      // other — see on_selection_changed()'s own doc comment.
      list_view.activate.connect (on_activate);

      // GtkListBase's own native move-binding is what Up/Down actually run
      // on this list — it just moves Gtk.SingleSelection's own `selected`
      // position, the exact same property a mouse click changes too.
      // navigated_by_keyboard tells on_selection_changed() apart the two.
      // Left/Right ride the same controller but are handled ourselves —
      // ported from VS Code's own real Explorer keybindings (onLeftArrow/
      // onRightArrow, abstractTree.ts).
      var key_nav_controller = new Gtk.EventControllerKey () {
        propagation_phase = Gtk.PropagationPhase.CAPTURE,
      };
      key_nav_controller.key_pressed.connect ((keyval, keycode, state) => {
        switch (keyval) {
          case Gdk.Key.Up:
          case Gdk.Key.Down:
          case Gdk.Key.Home:
          case Gdk.Key.End:
          case Gdk.Key.Page_Up:
          case Gdk.Key.Page_Down:
            navigated_by_keyboard = true;
            return false; // still let GtkListBase move the selection itself

          case Gdk.Key.Left:
          case Gdk.Key.KP_Left:
            // A New File/Folder or Rename is being typed inline — let Left
            // move the text cursor instead, same as it would in any other
            // Gtk.Text.
            if (editing_active) {
              return false;
            }
            navigate_left ();
            return true;

          case Gdk.Key.Right:
          case Gdk.Key.KP_Right:
            if (editing_active) {
              return false;
            }
            navigate_right ();
            return true;

          case Gdk.Key.F2:
            if (editing_active) {
              return false;
            }
            var rename_node = selected_node ();
            if (rename_node != null) {
              rename_requested (rename_node);
            }
            return true;

          case Gdk.Key.Delete:
          case Gdk.Key.KP_Delete:
            // Same reasoning as Left/Right above: a new-entry/rename text
            // field being typed into needs its own native "delete the
            // character ahead of the cursor" binding, not this one.
            if (editing_active) {
              return false;
            }
            var delete_node = selected_node ();
            if (delete_node != null) {
              delete_requested (delete_node);
            }
            return true;

          default:
            return false;
        }
      });
      list_view.add_controller (key_nav_controller);

      install_css ();

      setup_context_menu ();
      setup_background_click ();
      setup_repeat_click_toggle ();
    }

    // .data-table alone still isn't tight enough; trims it further. Must
    // be a descendant selector ("row", no ">") — row isn't a direct child
    // of listview (some internal wrapper sits between them).
    private void install_css () {
      GlobalCss.install_from_resource ("/io/github/nowaos/Opus/styles/explorer-pane.css");
    }

    public void populate (FileNode root) {
      root_node = root;
      var root_store = children_store (root);
      stores_by_path[root.path] = root_store;

      tree_model = tree_list_model_new_raw (root_store, false, false, on_create_model_raw, (void*) this, null);
      selection = new Gtk.SingleSelection (tree_model);
      selection.selection_changed.connect (on_selection_changed);
      list_view.model = selection;
    }

    /**
     * The width (in px) that would show every *currently visible* row's
     * full label with nothing clipped — ported from VS Code's own real
     * ExplorerView.getOptimalWidth().
     */
    public double get_optimal_width () {
      double widest = 0;
      collect_optimal_width (list_view, ref widest);
      return widest;
    }

    // libadwaita's own real ".navigation-sidebar > row" rule wraps every
    // row in padding/margin (28px total, horizontally) that ExplorerPaneTreeRow's
    // own box knows nothing about, since that lives on its *parent*.
    private const double NATIVE_ROW_HORIZONTAL_MARGIN = 12; // 6px each side

    private static void collect_optimal_width (Gtk.Widget root, ref double widest) {
      var row = root.get_data<ExplorerPaneTreeRow?> ("row");
      if (row != null && row.bound_node != null) {
        var native_row = root.get_parent () ?? root;
        int minimum, natural, minimum_baseline, natural_baseline;
        native_row.measure (Gtk.Orientation.HORIZONTAL, -1, out minimum, out natural, out minimum_baseline, out natural_baseline);
        widest = double.max (widest, natural + NATIVE_ROW_HORIZONTAL_MARGIN);
      }

      for (var child = root.get_first_child (); child != null; child = child.get_next_sibling ()) {
        collect_optimal_width (child, ref widest);
      }
    }

    public void select_path (string path) {
      if (tree_model == null) {
        return;
      }

      uint position;
      if (find_position (path, out position)) {
        selection.selected = position;
      }
    }

    /**
     * select_path() plus real keyboard focus (see reveal_path()'s own
     * comment on why those two aren't the same thing) — needed after
     * rebind()'s own remove+insert dance (rename entering/leaving edit
     * mode, in either direction) invalidates Gtk.SingleSelection's own
     * `selected` the same way any other structural change would, which
     * otherwise silently starves the key_nav_controller above: with
     * nothing selected *and* focused, F2/Delete's own selected_node()
     * finds nothing to act on the next time either is pressed.
     */
    public void focus_path (string path) {
      uint position;
      if (find_position (path, out position)) {
        move_focus_and_select (position);
      }
    }

    /**
     * "Reveal in Sidebar" from a tab's context menu: same as select_path()
     * (expands every collapsed ancestor, selects it), plus scrolls it into
     * view and briefly flashes its row a warm highlight. Also moves real
     * keyboard focus onto the row (see flash_path()'s own comment for
     * why that has to happen there, not here) — matching VS Code's own
     * real revealAndSelect, which setFocus()es the revealed item too.
     * select_path() alone left the row `:selected` but never `:focus`,
     * and row:selected:not(:focus)'s own transparent background-color
     * override (see the CSS below) beats both the flash's own
     * background-color rule and native :hover by specificity, so the
     * row never visibly flashed and silently stopped hovering too, both
     * for as long as it stayed selected.
     */
    public void reveal_path (string path) {
      if (tree_model == null) {
        return;
      }

      uint position;
      if (!find_position (path, out position)) {
        return;
      }

      selection.selected = position;
      list_view.scroll_to (position, Gtk.ListScrollFlags.NONE, null);

      Idle.add (() => {
        flash_path (path);
        return Source.REMOVE;
      });
    }

    /**
     * `path`'s row isn't a real widget yet at reveal_path()'s own point
     * in the call stack — find_position() only just expanded its
     * ancestors in the *model*, and GtkListView only materializes the
     * actual row widgets for that on its own next layout pass. Deferred
     * one Idle turn (same as this method's own caller already was)
     * gives that pass time to run first — confirmed live: a grab_focus()
     * attempted synchronously in reveal_path() silently no-ops (nothing
     * to focus yet), while this same call succeeds once run from here.
     */
    private void flash_path (string path) {
      var widget = find_realized_row_widget (list_view, path);
      var row_widget = widget == null ? null : native_row_widget (widget);
      if (row_widget == null) {
        return;
      }

      row_widget.grab_focus ();
      row_widget.add_css_class (REVEAL_FLASH_TRANSITION_CSS_CLASS);
      row_widget.add_css_class (REVEAL_FLASH_CSS_CLASS);
      Timeout.add (REVEAL_FLASH_HOLD_MS, () => {
        row_widget.remove_css_class (REVEAL_FLASH_CSS_CLASS);
        Timeout.add (REVEAL_FLASH_TRANSITION_MS, () => {
          row_widget.remove_css_class (REVEAL_FLASH_TRANSITION_CSS_CLASS);
          return Source.REMOVE;
        });
        return Source.REMOVE;
      });
    }

    /** Finds `path`'s currently-realized row widget, if any — list virtualization means most paths don't have one at all. */
    private static Gtk.Widget? find_realized_row_widget (Gtk.Widget root, string path) {
      var row = root.get_data<ExplorerPaneTreeRow?> ("row");
      if (row != null && row.bound_node != null && row.bound_node.path == path) {
        return root;
      }

      for (var child = root.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = find_realized_row_widget (child, path);
        if (found != null) {
          return found;
        }
      }
      return null;
    }

    // Expands every collapsed ancestor of `path` while scanning the
    // flattened list, so a nested row can be found without knowing its
    // depth up front.
    private bool find_position (string path, out uint position) {
      position = 0;
      uint i = 0;
      while (i < tree_model.get_n_items ()) {
        var row = tree_model.get_row (i);
        var node = (FileNode) row.item;

        if (node.path == path) {
          position = i;
          return true;
        }

        if (node.is_directory && !row.expanded && is_ancestor (node.path, path)) {
          set_expanded (row, node, true);
          continue;
        }

        i++;
      }

      return false;
    }

    private static bool is_ancestor (string dir_path, string target_path) {
      return target_path.has_prefix (dir_path + "/");
    }

    /** Left — ported from VS Code's own real Explorer (onLeftArrow, abstractTree.ts): collapses the selected row if it's an expanded directory; otherwise moves to its parent. A no-op at a top-level entry. */
    private void navigate_left () {
      if (selection.selected == Gtk.INVALID_LIST_POSITION) {
        return;
      }

      var list_row = (Gtk.TreeListRow) selection.get_item (selection.selected);
      var node = (FileNode) list_row.item;

      if (node.is_directory && list_row.expanded) {
        set_expanded (list_row, node, false);
        return;
      }

      var parent_row = list_row.get_parent ();
      if (parent_row == null) {
        return;
      }

      move_focus_and_select (parent_row.get_position ());
    }

    /** Right — ported from VS Code's own real Explorer (onRightArrow, abstractTree.ts): expands the selected row if collapsed; otherwise moves into its own first child. */
    private void navigate_right () {
      if (selection.selected == Gtk.INVALID_LIST_POSITION) {
        return;
      }

      var list_row = (Gtk.TreeListRow) selection.get_item (selection.selected);
      var node = (FileNode) list_row.item;

      if (node.is_directory && !list_row.expanded) {
        set_expanded (list_row, node, true);
        return;
      }

      var first_child = list_row.get_child_row (0);
      if (first_child == null) {
        return;
      }

      move_focus_and_select (first_child.get_position ());
    }

    /** Moves both Gtk.SingleSelection's own `selected` *and* actual GTK keyboard focus to `position` — SELECT alone leaves real focus wherever it already was, on a row that can end up destroyed by the very navigation that just happened. */
    private void move_focus_and_select (uint position) {
      navigated_by_keyboard = true;
      list_view.scroll_to (position, Gtk.ListScrollFlags.FOCUS | Gtk.ListScrollFlags.SELECT, null);
    }

    /** The single place `.expanded` is ever assigned — directory_expanded_changed needs to fire for exactly a real change, not a same-value re-assignment. */
    public void set_expanded (Gtk.TreeListRow row, FileNode node, bool expanded) {
      if (row.expanded == expanded) {
        return;
      }
      row.expanded = expanded;
      directory_expanded_changed (node.path, expanded);
    }

    private static ListStore children_store (FileNode node) {
      var store = new ListStore (typeof (FileNode));
      for (uint i = 0; i < node.children.length; i++) {
        store.append (node.children[i]);
      }
      return store;
    }

    // Always returns a (possibly empty) store for a directory, even one
    // with no children yet — Gtk.TreeListModel decides a row is
    // expandable purely from create_func returning non-null here.
    private static ListModel? on_create_model_raw (void* item, void* user_data) {
      var node = (FileNode) item;
      if (!node.is_directory) {
        return null;
      }

      var self = (ExplorerPaneTree) user_data;
      self.children_load_requested (node);
      var store = children_store (node);
      self.stores_by_path[node.path] = store;
      return store;
    }

    /** A single click (or the first click of a double-click) changed the selected row. Arrow-key navigation lands here too but should only move the highlight, not also toggle a directory or open a preview. */
    private void on_selection_changed (uint position, uint n_items) {
      if (selection.selected == Gtk.INVALID_LIST_POSITION) {
        return;
      }

      if (navigated_by_keyboard) {
        navigated_by_keyboard = false;
        return;
      }

      var list_row = (Gtk.TreeListRow) selection.get_item (selection.selected);
      var node = (FileNode) list_row.item;

      if (node.is_directory) {
        set_expanded (list_row, node, !list_row.expanded);
        return;
      }

      file_activated (node.path, false);
    }

    /** A row was double-clicked, or Enter was pressed on it. Promotes a file to a permanent tab; toggles a directory's expansion. */
    private void on_activate (uint position) {
      var list_row = (Gtk.TreeListRow) selection.get_item (position);
      var node = (FileNode) list_row.item;

      if (node.is_directory) {
        set_expanded (list_row, node, !list_row.expanded);
        return;
      }

      file_activated (node.path, true);
    }

    private void on_setup (Object item) {
      var list_item = (Gtk.ListItem) item;
      var row = new ExplorerPaneTreeRow (icon_theme);
      row.widget.set_data ("row", row);
      row.edit_committed.connect ((name) => row_edit_committed (name));
      row.edit_cancelled.connect (() => row_edit_cancelled ());
      list_item.child = row.widget;
    }

    private void on_bind (Object item) {
      var list_item = (Gtk.ListItem) item;
      var list_row = (Gtk.TreeListRow) list_item.item;
      var node = (FileNode) list_row.item;
      list_item.child.get_data<ExplorerPaneTreeRow> ("row").bind (list_row, node);
    }

    private void on_unbind (Object item) {
      var list_item = (Gtk.ListItem) item;
      list_item.child.get_data<ExplorerPaneTreeRow> ("row").unbind ();
    }

    /** Right-click anywhere in the tree — the tree's empty background (`target == null`), a folder row, or a file row. list_view.pick() finds whichever ExplorerPaneTreeRow, if any, is under the point. */
    private void setup_context_menu () {
      var click = new Gtk.GestureClick ();
      click.set_button (Gdk.BUTTON_SECONDARY);
      click.pressed.connect ((n_press, x, y) => {
        context_menu_requested (node_at (x, y), x, y);
      });
      list_view.add_controller (click);
    }

    public FileNode? node_at (double x, double y) {
      var row = row_at (x, y);
      return row == null ? null : row.bound_node;
    }

    /** Whatever Gtk.SingleSelection's own `selected` currently points at — the keyboard-driven counterpart to node_at(), which needs a mouse position instead. Null with nothing selected (an empty tree). */
    private FileNode? selected_node () {
      if (selection.selected == Gtk.INVALID_LIST_POSITION) {
        return null;
      }
      var list_row = (Gtk.TreeListRow) selection.get_item (selection.selected);
      return (FileNode) list_row.item;
    }

    /** The ExplorerPaneTreeRow (the one on_setup() stashed onto its widget) under `(x, y)`, or null over the tree's empty background. */
    public ExplorerPaneTreeRow? row_at (double x, double y) {
      var widget = row_widget_at (x, y);
      return widget == null ? null : widget.get_data<ExplorerPaneTreeRow?> ("row");
    }

    /** The row widget (the one on_setup() stashed a ExplorerPaneTreeRow onto) under `(x, y)`, or null over the tree's empty background. */
    public Gtk.Widget? row_widget_at (double x, double y) {
      Gtk.Widget? widget = list_view.pick (x, y, Gtk.PickFlags.DEFAULT);
      while (widget != null) {
        if (widget.get_data<ExplorerPaneTreeRow?> ("row") != null) {
          return widget;
        }
        widget = widget.get_parent ();
      }
      return null;
    }

    /**
     * The actual GTK-internal "row"-named wrapper `row_widget` sits inside
     * — the same element native hover/selection styling itself targets.
     * `row_widget` (ExplorerPaneTreeRow's own Gtk.Box) is only its *child*:
     * toggling `.drag-hover` there instead doesn't match native hover
     * pixel-for-pixel.
     */
    public Gtk.Widget? native_row_widget (Gtk.Widget? row_widget) {
      return row_widget == null ? null : row_widget.get_parent ();
    }

    public void set_drag_hover (Gtk.Widget? row_widget, bool hover) {
      if (row_widget == null) {
        return;
      }
      if (hover) {
        row_widget.add_css_class (DRAG_HOVER_CSS_CLASS);
      } else {
        row_widget.remove_css_class (DRAG_HOVER_CSS_CLASS);
      }
    }

    /**
     * A plain (primary-button) click that lands on the tree's empty
     * background moves focus to the list itself. Its real purpose: if a
     * New File/Folder/Rename is mid-edit, that takes focus away from its
     * entry, which resolves it exactly the way clicking a different row
     * already does.
     */
    private void setup_background_click () {
      var click = new Gtk.GestureClick ();
      click.set_button (Gdk.BUTTON_PRIMARY);
      click.pressed.connect ((n_press, x, y) => {
        if (node_at (x, y) == null) {
          list_view.grab_focus ();
        }
      });
      list_view.add_controller (click);
    }

    /**
     * on_selection_changed()'s expand/collapse toggle (for a folder) or
     * file_activated (for a file) only run because Gtk.SingleSelection's
     * own selection-changed signal fired — which it only does when the
     * selected row actually *changes*. Clicking an already-selected row
     * again leaves the selection untouched, so that signal never re-fires.
     * This catches exactly that missed case, for both.
     */
    private void setup_repeat_click_toggle () {
      var click = new Gtk.GestureClick ();
      click.set_button (Gdk.BUTTON_PRIMARY);
      click.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
      click.pressed.connect ((n_press, x, y) => {
        var node = node_at (x, y);
        if (node == null) {
          return;
        }

        uint position;
        if (!find_position (node.path, out position) || selection.selected != position) {
          return;
        }

        if (node.is_directory) {
          var list_row = (Gtk.TreeListRow) tree_model.get_row (position);
          set_expanded (list_row, node, !list_row.expanded);
        } else {
          file_activated (node.path, false);
        }
      });
      list_view.add_controller (click);
    }

    /**
     * Resolves the parent store `target` (or the workspace root, if null)
     * should get a new entry spliced into — expanding `target` first if
     * it's a collapsed folder, synchronously materializing its ListStore
     * via on_create_model_raw so a placeholder always has somewhere to go.
     */
    public FileNode resolve_parent (FileNode? target) {
      var parent = target ?? root_node;

      uint row_position = 0;
      if (target != null && find_position (target.path, out row_position)) {
        var list_row = (Gtk.TreeListRow) tree_model.get_row (row_position);
        set_expanded (list_row, target, true);
      }

      return parent;
    }

    public ListStore? store_for (string path) {
      return stores_by_path[path];
    }

    /** Forces whatever row is currently showing `node` to re-bind — a plain remove+reinsert is how a GListModel is told "re-bind whatever's showing for this item" (used for a Rename's own pre-fill, and for the Cut clipboard's dim toggling). */
    public void rebind (FileNode node) {
      var store = stores_by_path[Path.get_dirname (node.path)];
      uint position = 0;
      if (store != null && store.find (node, out position)) {
        store.remove (position);
        store.insert (position, node);
      }
    }

    /**
     * Syncs `parent_path`'s row's own children to `children` — called
     * once a New File/Folder/Rename/Paste is actually applied on disk.
     * Diffs against the store's current contents (sync_store()) rather
     * than clearing and rebuilding it outright: a plain remove_all() tears
     * down every row in this directory in one shot, collapsing any
     * expanded subfolder among *unrelated* siblings.
     */
    public void refresh_children (string parent_path, GenericArray<FileNode> children) {
      var store = stores_by_path[parent_path];
      if (store != null) {
        sync_store (store, children);
      }
    }

    /**
     * Brings `store` to hold exactly `target`'s items, in `target`'s
     * order — but only ever removing items no longer present and
     * inserting new ones, never touching one that's staying put.
     */
    private static void sync_store (ListStore store, GenericArray<FileNode> target) {
      for (int i = (int) store.get_n_items () - 1; i >= 0; i--) {
        if (!contains (target, (FileNode) store.get_item (i))) {
          store.remove (i);
        }
      }

      for (uint i = 0; i < target.length; i++) {
        uint position;
        if (!store.find (target[i], out position)) {
          store.insert (i, target[i]);
        }
      }
    }

    private static bool contains (GenericArray<FileNode> array, FileNode node) {
      for (uint i = 0; i < array.length; i++) {
        if (array[i] == node) {
          return true;
        }
      }
      return false;
    }
  }
}
