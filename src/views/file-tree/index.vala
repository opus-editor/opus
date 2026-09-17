/**
 * Gtk-backed facade for the sidebar's file tree: a {@link Gtk.ListView} over
 * a {@link Gtk.TreeListModel}, with {@link FileTreeRow} as its row widget.
 *
 * The tree is built eagerly from the {@link FileNode} handed to
 * {@link populate}: every directory's children are already known, so the
 * model's create-func never touches the filesystem, it just wraps the
 * already-loaded children of the directory being expanded.
 */
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

public class FileTreeView : Object {
    private Gtk.ScrolledWindow scrolled_window;
    private Gtk.ListView list_view;
    private Gtk.TreeListModel? tree_model;
    private Gtk.SingleSelection? selection;
    private FileNode? root_node;

    // One entry per directory whose children have been turned into a
    // ListStore — the root's from populate(), every other one lazily as
    // on_create_model_raw materializes it on first expand. Kept around (not
    // just handed to Gtk.TreeListModel and forgotten) so a New File/Folder
    // can be spliced straight into the right one and have it show up
    // immediately — ListStore is itself a GListModel, so TreeListModel/
    // ListView already pick up the change reactively, no manual refresh.
    private HashTable<string, ListStore> stores_by_path = new HashTable<string, ListStore> (str_hash, str_equal);

    // The node currently being edited inline, if any — a New File/Folder
    // still being named, or an existing entry being renamed. Which one it
    // is comes down to pending_parent_path: set only for the former, since
    // a not-yet-created placeholder has no real path of its own to derive
    // a parent from (an existing node being renamed does, via its own
    // path). A placeholder isn't yet part of any FileNode.children array
    // (that only happens once the name is committed and created on disk) —
    // just spliced directly into its directory's ListStore for
    // FileTreeRow to render as an editable entry; an existing rename
    // target already is a real entry there.
    private FileNode? editing_node = null;
    private string? pending_parent_path = null;

    // The tree's own internal Cut/Copy clipboard — never the system
    // clipboard (copy_to_clipboard()/Copy Path are the only things that
    // touch that; this is purely this app's own concept, the same way VS
    // Code's explorer has one). Cutting dims the node (clipboard_node.is_cut,
    // undone on the next Cut/Copy or once pasted); copying doesn't dim
    // anything and survives multiple pastes, only a cut is consumed by its
    // one paste.
    private FileNode? clipboard_node = null;

    public Gtk.Widget widget { get { return scrolled_window; } }

    /**
     * A file row was clicked. `open_permanent` is true for a double-click
     * (open/promote to a permanent tab), false for a single-click (preview).
     */
    public signal void file_activated (string path, bool open_permanent);

    /** A New File/Folder's inline name was confirmed — `is_directory` says which. */
    public signal void create_entry_requested (string parent_path, string name, bool is_directory);

    /** An inline Rename was confirmed with a non-empty, different name. */
    public signal void rename_entry_requested (string path, string new_name);

    public signal void delete_entry_requested (string path);

    /** A Paste was requested: `source_path` is what's on the tree's internal clipboard, `is_cut` says whether that was a Cut (move) or Copy (duplicate), `target_path` is the directory it should land in. */
    public signal void paste_requested (string source_path, bool is_cut, string target_path);

    public signal void open_in_files_requested (string path);
    public signal void open_in_terminal_requested (string path);
    public signal void copy_path_requested (string path);
    public signal void copy_relative_path_requested (string path);

    public FileTreeView () {
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

        // Two separate native GtkListView signals, deliberately not one:
        // a Gtk.GestureClick of our own on each row (the original
        // approach, in FileTreeRow) raced GtkListView's own built-in
        // click gesture for row selection — that one sits above ours in
        // the tree, so it *always* gets first (and sometimes exclusive)
        // claim to the press, and our own row's gesture intermittently
        // never fired at all. `single-click-activate` looked like a fix
        // (one native signal instead of a competing gesture), but it does
        // its own internal multi-click grouping before ever emitting
        // `activate`, which swallows the second click of a real
        // double-click — no reliable way to tell double- from
        // single-click from `activate` alone in that mode.
        //
        // selection-changed is what actually fires reliably on every
        // single click (it's what always moved the row highlight, even
        // during the original bug), so it drives preview; `activate`,
        // WITHOUT single-click-activate, is GTK's own native,
        // battle-tested double-click recognizer, so it drives promotion.
        // Neither one reimplements or races the other.
        list_view.activate.connect (on_activate);

        // .data-table alone still isn't tight enough; trims it further.
        // Must be a descendant selector ("row", no ">") — row isn't a direct
        // child of listview (some internal wrapper sits between them, found
        // by testing with a visible color first rather than guessing twice).
        // Gtk.StyleContext.add_provider_for_display is deprecated since GTK
        // 4.10 (removed in GTK 5) with no replacement: GTK's own tracking
        // issue lists it as still unresolved, proposed fix an open "move to
        // GtkSettings?" question — https://gitlab.gnome.org/GNOME/gtk/-/issues/2603
        // This warning is expected to stay until upstream picks one.
        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_string ("""
            /* 22px, matching VS Code's file explorer row height
             * (ExplorerDelegate.ITEM_HEIGHT in its own source). */
            listview.data-table row {
                padding-top: 0;
                padding-bottom: 0;
                min-height: 22px;
                border-radius: 4px;
            }
            treeexpander > expander {
                -gtk-icon-source: -gtk-icontheme("chevron-right-symbolic");
            }
            treeexpander > expander:checked {
                -gtk-icon-source: -gtk-icontheme("chevron-down-symbolic");
            }
        """);
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        scrolled_window = new Gtk.ScrolledWindow ();
        scrolled_window.child = list_view;

        setup_context_menu ();
        setup_background_click ();
        setup_repeat_click_toggle ();
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

    public void select_path (string path) {
        if (tree_model == null) {
            return;
        }

        uint position;
        if (find_position (path, out position)) {
            selection.selected = position;
        }
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
                row.expanded = true;
                continue;
            }

            i++;
        }

        return false;
    }

    private static bool is_ancestor (string dir_path, string target_path) {
        return target_path.has_prefix (dir_path + "/");
    }

    private static ListStore children_store (FileNode node) {
        var store = new ListStore (typeof (FileNode));
        for (uint i = 0; i < node.children.length; i++) {
            store.append (node.children[i]);
        }
        return store;
    }

    // Always returns a (possibly empty) store for a directory, even one
    // with no children yet: a New File/Folder inside a directory that was
    // empty at scan time still needs a real ListStore to be spliced into,
    // and Gtk.TreeListModel decides a row is expandable purely from
    // create_func returning non-null here, not from whether that model
    // currently holds anything — so an empty directory now shows a
    // (currently pointless) expander too, the same trade-off VS Code's own
    // explorer makes for the same reason.
    private static ListModel? on_create_model_raw (void* item, void* user_data) {
        var node = (FileNode) item;
        if (!node.is_directory) {
            return null;
        }

        var self = (FileTreeView) user_data;
        var store = children_store (node);
        self.stores_by_path[node.path] = store;
        return store;
    }

    /** A single click (or the first click of a double-click) changed the selected row — see the comment above. */
    private void on_selection_changed (uint position, uint n_items) {
        if (selection.selected == Gtk.INVALID_LIST_POSITION) {
            return;
        }

        var list_row = (Gtk.TreeListRow) selection.get_item (selection.selected);
        var node = (FileNode) list_row.item;

        if (node.is_directory) {
            list_row.expanded = !list_row.expanded;
            return;
        }

        file_activated (node.path, false);
    }

    /** A row was double-clicked — see the comment above. Promotes a file to a permanent tab. */
    private void on_activate (uint position) {
        var list_row = (Gtk.TreeListRow) selection.get_item (position);
        var node = (FileNode) list_row.item;

        if (node.is_directory) {
            return;
        }

        file_activated (node.path, true);
    }

    private void on_setup (Object item) {
        var list_item = (Gtk.ListItem) item;
        var row = new FileTreeRow ();
        // list_item.child only holds the Gtk.Widget; stash the FileTreeRow
        // facade that owns it so on_bind/on_unbind can get back to it.
        row.widget.set_data ("row", row);
        // Connected once here, not per bind(): this FileTreeRow instance is
        // reused for many different nodes over its lifetime (list recycling).
        row.edit_committed.connect (on_edit_committed);
        row.edit_cancelled.connect (on_edit_cancelled);
        list_item.child = row.widget;
    }

    private void on_bind (Object item) {
        var list_item = (Gtk.ListItem) item;
        var list_row = (Gtk.TreeListRow) list_item.item;
        var node = (FileNode) list_row.item;
        list_item.child.get_data<FileTreeRow> ("row").bind (list_row, node);
    }

    private void on_unbind (Object item) {
        var list_item = (Gtk.ListItem) item;
        list_item.child.get_data<FileTreeRow> ("row").unbind ();
    }

    /**
     * Right-click anywhere in the tree opens a menu — the tree's empty
     * background (`target == null`, meaning the workspace root), a folder
     * row, or a file row, each with its own item set; see
     * show_context_menu(). `list_view.pick()` finds whichever
     * FileTreeRow, if any, is under the point — the same `"row"` stash
     * on_setup() already uses — rather than a per-row gesture: there's no
     * competing native GTK behavior to out-race for a *secondary* click on
     * a list (unlike the primary-click case multi-cursor-editor.vala had
     * to work around for Alt+Click on the editor), so one gesture here is
     * enough.
     */
    private void setup_context_menu () {
        var click = new Gtk.GestureClick ();
        click.set_button (Gdk.BUTTON_SECONDARY);
        click.pressed.connect ((n_press, x, y) => {
            show_context_menu (node_at (x, y), x, y);
        });
        list_view.add_controller (click);
    }

    private FileNode? node_at (double x, double y) {
        Gtk.Widget? widget = list_view.pick (x, y, Gtk.PickFlags.DEFAULT);
        while (widget != null) {
            var row = widget.get_data<FileTreeRow?> ("row");
            if (row != null) {
                return row.bound_node;
            }
            widget = widget.get_parent ();
        }
        return null;
    }

    /**
     * A plain (primary-button) click that lands on the tree's empty
     * background — not on any row, same node_at() == null check the
     * context menu uses to mean the same thing — moves focus to the list
     * itself. GtkListView's own click-to-select handling has no row to act
     * on there anyway, so this doesn't compete with it for anything.
     * Its real purpose: if a New File/Folder/Rename is mid-edit, that
     * takes focus away from its entry, which resolves it (commits if
     * named, cancels if left blank) exactly the way clicking a different
     * row already does — see FileTreeRow's own focus-leave handling.
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
     * again leaves the selection untouched, so that signal never re-fires:
     * a folder appeared to only toggle "the first time" (a pre-existing
     * bug, not introduced by anything recent); a file stayed unopenable by
     * a plain click after its tab was closed some other way (e.g. its
     * close button) without ever touching the tree's own selection, found
     * live the same way. This catches exactly that missed case, for both.
     *
     * Runs in the CAPTURE phase — same technique multi-cursor-editor.vala's
     * Alt+Click uses, for the same reason: it needs to read whether this
     * row was *already* selected before GtkListView's own (BUBBLE-phase)
     * click handling updates the selection for this very click, not after.
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
            // Not yet the selected row: on_selection_changed is about to
            // fire for this same click and will handle it instead.
            if (!find_position (node.path, out position) || selection.selected != position) {
                return;
            }

            if (node.is_directory) {
                var list_row = (Gtk.TreeListRow) tree_model.get_row (position);
                list_row.expanded = !list_row.expanded;
            } else {
                file_activated (node.path, false);
            }
        });
        list_view.add_controller (click);
    }

    /**
     * `target` null means the workspace root (background click). A
     * directory (the root included) can hold a New File/Folder, be opened
     * in a file manager/terminal, and — the root aside, nothing to Cut or
     * Copy about the workspace root itself — Cut/Copy an existing folder;
     * either kind of directory is also a valid Paste destination, shown
     * only when the clipboard actually holds something. A file only has
     * Cut/Copy. Rename/Delete/Copy Path/Copy Relative Path apply to any
     * *existing* entry, just not the workspace root itself.
     */
    private void show_context_menu (FileNode? target, double x, double y) {
        var context_path = target == null ? root_node.path : target.path;
        var has_clipboard = clipboard_node != null;

        var popover = ContextMenu.create (list_view, x, y);
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        if (target == null || target.is_directory) {
            box.append (ContextMenu.item (_("New File…"), () => request_new_entry (target, false), popover));
            box.append (ContextMenu.item (_("New Folder…"), () => request_new_entry (target, true), popover));
            box.append (ContextMenu.separator ());
            box.append (ContextMenu.item (_("Open in Files"), () => open_in_files_requested (context_path), popover));
            box.append (ContextMenu.item (_("Open in Terminal"), () => open_in_terminal_requested (context_path), popover));

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
            box.append (ContextMenu.item (_("Rename…"), () => request_rename (target), popover));
            box.append (ContextMenu.item (_("Delete"), () => delete_entry_requested (target.path), popover));
        }

        box.append (ContextMenu.separator ());
        box.append (ContextMenu.item (_("Copy Path"), () => copy_path_requested (context_path), popover));
        box.append (ContextMenu.item (_("Copy Relative Path"), () => copy_relative_path_requested (context_path), popover));

        popover.child = box;
        popover.popup ();
    }

    /**
     * Starts naming a New File/Folder inline: expands `target` first if
     * it's a collapsed folder (synchronously materializing its ListStore
     * via on_create_model_raw, so the placeholder below always has
     * somewhere to go), then splices a placeholder FileNode — rendered as
     * an editable row by FileTreeRow.bind() — into that directory's store.
     */
    private void request_new_entry (FileNode? target, bool is_directory) {
        var parent = target ?? root_node;

        uint row_position = 0;
        if (target != null && find_position (target.path, out row_position)) {
            var list_row = (Gtk.TreeListRow) tree_model.get_row (row_position);
            if (!list_row.expanded) {
                list_row.expanded = true;
            }
        }

        var store = stores_by_path[parent.path];
        if (store == null) {
            return;
        }

        var placeholder = new FileNode ("", "", is_directory);
        placeholder.is_editing_name = true;
        editing_node = placeholder;
        pending_parent_path = parent.path;
        // Directories first, then files (FileTree.precedes' own order): a
        // new folder goes at the very top, a new file after the last
        // existing directory — never position 0 regardless of kind, which
        // put a New File at the top as if it were a folder.
        uint insert_index = 0;
        if (!is_directory) {
            while (insert_index < parent.children.length && parent.children[insert_index].is_directory) {
                insert_index++;
            }
        }
        store.insert (insert_index, placeholder);
    }

    /**
     * FileTreeRow doesn't distinguish a New File/Folder commit from a
     * Rename one — pending_parent_path being set says which this is (only
     * a not-yet-created placeholder needs it; see its own comment).
     * Deferred to the next main-loop iteration, not run directly: this
     * fires from the edit entry's own focus-leave (e.g. clicking a
     * different row while a New File/Folder is still blank cancels it),
     * which is itself still inside GTK's own dispatch of *that* click —
     * removing the placeholder's row from its ListStore synchronously
     * from in there tears down a widget GTK is still mid-way through
     * processing the same click against, and GTK doesn't take that
     * gracefully (found the hard way: a real crash — repeated
     * `gtk_widget_get_parent: assertion 'GTK_IS_WIDGET (widget)' failed`
     * — not assumed up front).
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
                // Committed but unchanged — same as cancelling.
                cancel_rename ();
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

    /** Removes the still-pending New File/Folder placeholder — after a cancelled edit, or called by the controller when creating it on disk failed. */
    public void discard_pending_entry () {
        if (editing_node == null || pending_parent_path == null) {
            return;
        }

        var store = stores_by_path[pending_parent_path];
        uint position = 0;
        if (store != null && store.find (editing_node, out position)) {
            store.remove (position);
        }

        editing_node = null;
        pending_parent_path = null;
    }

    /**
     * Starts renaming `target` inline: FileTreeRow.bind() pre-fills and
     * fully selects its current name once is_editing_name is set. Unlike a New
     * File/Folder placeholder, `target` is already a real entry in its
     * parent's ListStore — removing and immediately reinserting it (a
     * no-op on ordering, since neither its identity nor its sort key
     * changed) is just how a GListModel is told "re-bind whatever's
     * showing for this item", the same trick request_new_entry doesn't
     * need since inserting a *new* item already does that itself.
     * pending_parent_path stays null here — that's what tells
     * on_edit_committed/on_edit_cancelled this is a rename, not a create.
     */
    private void request_rename (FileNode target) {
        var parent_path = Path.get_dirname (target.path);
        var store = stores_by_path[parent_path];
        uint position = 0;
        if (store == null || !store.find (target, out position)) {
            return;
        }

        target.is_editing_name = true;
        editing_node = target;
        store.remove (position);
        store.insert (position, target);
    }

    /** Reverts the still-pending Rename back to a normal display row — after a cancelled/no-op edit, or called by the controller when renaming on disk failed. */
    public void cancel_rename () {
        if (editing_node == null) {
            return;
        }

        var node = editing_node;
        editing_node = null;
        node.is_editing_name = false;
        rebind (node);
    }

    /** Forces whatever row is currently showing `node` to re-bind — see request_rename()'s doc for why remove+reinsert is what that takes. */
    private void rebind (FileNode node) {
        var store = stores_by_path[Path.get_dirname (node.path)];
        uint position = 0;
        if (store != null && store.find (node, out position)) {
            store.remove (position);
            store.insert (position, node);
        }
    }

    /**
     * Syncs `parent_path`'s row's own children to `children` — called by
     * the controller once a New File/Folder/Rename/Paste is actually
     * applied on disk (this also clears whichever of the now-fulfilled
     * pending placeholder or renaming node belongs to this directory,
     * since `children` reflects the real, saved state and never includes
     * a placeholder, and already has the renamed node's fresh replacement
     * instead of the old one).
     *
     * Diffs against the store's current contents (sync_store()) rather
     * than clearing and rebuilding it outright: a plain remove_all()
     * tears down every row in this directory in one shot, GtkTreeListRow
     * included — collapsing any expanded subfolder among *unrelated*
     * siblings, not just whatever this refresh is actually about (found
     * live: pasting into a folder was closing every other already-expanded
     * folder in the whole tree).
     */
    public void refresh_children (string parent_path, GenericArray<FileNode> children) {
        var store = stores_by_path[parent_path];
        if (store != null) {
            sync_store (store, children);
        }

        if (pending_parent_path == parent_path) {
            editing_node = null;
            pending_parent_path = null;
        } else if (editing_node != null && Path.get_dirname (editing_node.path) == parent_path) {
            editing_node = null;
        }
    }

    /**
     * Brings `store` to hold exactly `target`'s items, in `target`'s
     * order — but only ever removing items no longer present and
     * inserting new ones, never touching one that's staying put. That's
     * enough for every caller here: every operation that could otherwise
     * reorder an existing entry (rename, move) always hands back a fresh
     * FileNode instance for it (see FileTree.rename_child/move_child's own
     * comments on why), so an item that's genuinely the *same* object
     * between calls is, by construction, already in the right relative
     * order — only ever needing a plain insert to land at its final
     * index, never a remove-and-reinsert that would cost it (or an
     * expanded directory nested under it) its GtkTreeListRow state.
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

    public void copy_to_clipboard (string text) {
        widget.get_clipboard ().set_text (text);
    }

    /**
     * Cut/Copy/Paste here are the tree's own internal concept, deliberately
     * not the system clipboard (that's what copy_to_clipboard() above, used
     * only by Copy Path/Copy Relative Path, is for) — there's no
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
            rebind (node);
        }
    }

    private void request_paste (FileNode? target) {
        if (clipboard_node == null) {
            return;
        }
        paste_requested (clipboard_node.path, clipboard_node.is_cut, target == null ? root_node.path : target.path);
    }

    /**
     * Called by the controller once a Paste actually completed on disk —
     * a Copy's clipboard survives it (it can be pasted again elsewhere);
     * a Cut's is consumed by its one Paste, which also already made the
     * cut node vanish from its old directory's row (refresh_children()
     * rebuilds that from the real, now-shorter children array), so there's
     * no separate row left to un-dim.
     */
    public void clipboard_pasted (bool was_cut) {
        if (was_cut) {
            clipboard_node = null;
        }
    }

    /** Undims whatever's currently on the Cut clipboard, if anything — called before replacing it with a new Cut/Copy. */
    private void clear_cut_dim () {
        if (clipboard_node == null || !clipboard_node.is_cut) {
            return;
        }
        clipboard_node.is_cut = false;
        rebind (clipboard_node);
    }

    public void show_error (string message) {
        var dialog = new Adw.AlertDialog (_("Error"), message);
        dialog.add_response ("ok", _("OK"));
        dialog.present (widget);
    }

    /**
     * Deleting `filename` while it has unsaved changes open in a tab —
     * same shape VS Code's own uses: just Cancel or go ahead and lose
     * them, no third "save first" option (there's nowhere left to save
     * to once the file's gone). Returns whether the user chose to
     * proceed.
     */
    public async bool confirm_delete_with_unsaved_changes (string filename) {
        var dialog = new Adw.AlertDialog (
            _("You are deleting “%s” with unsaved changes. Do you want to continue?").printf (filename),
            _("Your changes will be lost if you don't save them.")
        );
        dialog.add_response ("cancel", _("Cancel"));
        dialog.add_response ("delete", _("Move to Trash"));
        dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_default_response ("cancel");
        dialog.set_close_response ("cancel");
        // See TabBarView.confirm_unsaved_close's own comment: Adw.AlertDialog
        // stacks buttons vertically by default at medium sizes.
        dialog.prefer_wide_layout = true;

        var response = yield dialog.choose (widget, null);
        return response == "delete";
    }
}
