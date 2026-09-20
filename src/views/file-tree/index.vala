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

    // Bluish translucent highlight (see the CSS below) for the folder row
    // currently under a dragged file/folder — toggled directly on its row
    // widget in on_drag_motion()/on_drag_leave(), not tracked by
    // FileTreeRow itself: it's pointer-position state, unrelated to which
    // FileNode a recycled row happens to be bound to right now.
    private const string DRAG_HOVER_CSS_CLASS = "drag-hover";

    // How long a drag has to sit over a collapsed folder before it
    // auto-expands — the "spring-loaded folder" convention Nautilus/
    // Finder/Explorer all already use, so reaching a deep destination
    // doesn't need a separate expand-then-drag-again pass.
    private const uint HOVER_EXPAND_MS = 1500;

    private Gtk.Widget? drag_hover_widget = null;
    private uint hover_expand_timeout_id = 0;

    // "Reveal in Sidebar" flash — a warm highlight added to the target
    // row then removed shortly after, so the CSS transition on the row's
    // own background-color (see the CSS below) fades it back out on its
    // own; FLASH_HOLD_MS just needs to be long enough for GTK to actually
    // paint one frame at full brightness before the removal (and thus the
    // fade) kicks in.
    //
    // The transition itself lives on a *second*, separately-toggled class
    // (REVEAL_FLASH_TRANSITION_CSS_CLASS) rather than on every row
    // unconditionally: a transition on the row's own base rule would also
    // animate native hover/selection's own background-color changes,
    // which normally snap instantly — sharing the property turned every
    // hover into a slow, laggy fade too. Toggling a second class on for
    // only as long as this one row's own flash-then-fade actually takes
    // (HOLD_MS to show it solid, TRANSITION_MS more to fade it back out)
    // keeps the transition scoped to just that row, just that window.
    private const string REVEAL_FLASH_CSS_CLASS = "reveal-flash";
    private const string REVEAL_FLASH_TRANSITION_CSS_CLASS = "reveal-flash-fading";
    private const uint REVEAL_FLASH_HOLD_MS = 150;
    private const uint REVEAL_FLASH_TRANSITION_MS = 700; // matches the CSS transition's own duration

    public Gtk.Widget widget { get { return scrolled_window; } }

    /**
     * A file row was clicked. `open_permanent` is true for a double-click
     * (open/promote to a permanent tab), false for a single-click (preview).
     */
    public signal void file_activated (string path, bool open_permanent);

    /** A directory's expanded state actually changed (not fired for a no-op re-assignment) — `expanded` true means its children are now visible. */
    public signal void directory_expanded_changed (string path, bool expanded);

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
            /* The transition lives on this separate, briefly-toggled class
             * (see REVEAL_FLASH_TRANSITION_CSS_CLASS's own comment) rather
             * than on every row unconditionally — that made native hover/
             * selection's own background-color changes fade slowly too,
             * leaving a laggy "trail" on every hover. Defined here, on
             * *this* class rather than .reveal-flash itself, so it's
             * active while .reveal-flash is being *removed* too (a
             * transition defined only inside .reveal-flash would apply
             * going into the flash, not coming back out of it once that
             * class is gone). */
            listview.data-table row.reveal-flash-fading {
                transition: background-color 700ms ease-out;
            }
            treeexpander > expander {
                -gtk-icon-source: -gtk-icontheme("chevron-right-symbolic");
            }
            treeexpander > expander:checked {
                -gtk-icon-source: -gtk-icontheme("chevron-down-symbolic");
            }
            /* The folder row directly under a dragged file/folder — accent
             * color (the system's own, not a hardcoded blue) at partial
             * opacity, so it tracks the user's own accent choice and still
             * reads correctly in light/dark. Set on the real "row" node
             * itself (see native_row_widget()'s own comment) — the 22px
             * height/border-radius rule right above already covers it too,
             * same as it does for native hover/selection. */
            listview.data-table row.drag-hover {
                background-color: color-mix(in srgb, var(--accent-bg-color) 30%, transparent);
            }
            /* libadwaita's own default for any widget currently holding an
             * "active" drop target (base.css: `:drop(active)`) is a 1px
             * accent-colored inset border — already suppressed for other
             * sidebar list types (placessidebar, stackswitcher, …), but
             * only via a *descendant* selector, which doesn't catch our
             * own Gtk.DropTarget: it's attached straight to this listview,
             * which already carries .navigation-sidebar itself rather than
             * being a child of something that does. .drag-hover above is
             * this tree's own feedback for a drop target; this outer
             * border is redundant on top of it either way. */
            listview.data-table:drop(active) {
                box-shadow: none;
            }
            /* "Reveal in Sidebar" — briefly highlights the revealed row,
             * the same warm/warning color the "File Has Changed on Disk"
             * banner uses (see EditorView's own install_css()), not a
             * hardcoded yellow, so it also tracks light/dark. Added then
             * removed shortly after in code, with .reveal-flash-fading's
             * own transition (above) fading it back out instead of
             * snapping off. */
            listview.data-table row.reveal-flash {
                background-color: var(--warning-bg-color);
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
        setup_drag_drop ();
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

    /**
     * "Reveal in Sidebar" from a tab's context menu: same as select_path()
     * (expands every collapsed ancestor, selects it), plus scrolls it into
     * view and briefly flashes its row a warm highlight so it's easy to
     * spot even in a long list.
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

        // The row for `position` isn't necessarily realized as an actual
        // widget yet right after scroll_to() — GTK only binds one on its
        // own next layout pass. Deferred one main-loop iteration for that
        // to happen, same reasoning as FileTreeRow's own start_editing().
        Idle.add (() => {
            flash_path (path);
            return Source.REMOVE;
        });
    }

    private void flash_path (string path) {
        var widget = find_realized_row_widget (list_view, path);
        var row_widget = widget == null ? null : native_row_widget (widget);
        if (row_widget == null) {
            return;
        }

        row_widget.add_css_class (REVEAL_FLASH_TRANSITION_CSS_CLASS);
        row_widget.add_css_class (REVEAL_FLASH_CSS_CLASS);
        Timeout.add (REVEAL_FLASH_HOLD_MS, () => {
            row_widget.remove_css_class (REVEAL_FLASH_CSS_CLASS); // transition is still on — this is what fades it back out
            Timeout.add (REVEAL_FLASH_TRANSITION_MS, () => {
                row_widget.remove_css_class (REVEAL_FLASH_TRANSITION_CSS_CLASS); // fade's done — stop carrying the transition on this row
                return Source.REMOVE;
            });
            return Source.REMOVE;
        });
    }

    /** Finds `path`'s currently-realized row widget, if any — list virtualization means most paths don't have one at all (recycled away, off-screen); only ever meaningful right after a scroll_to() targeting that exact path. */
    private static Gtk.Widget? find_realized_row_widget (Gtk.Widget root, string path) {
        var row = root.get_data<FileTreeRow?> ("row");
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

    /** The single place `.expanded` is ever assigned — a plain `row.expanded = x` wouldn't tell anything an expand/collapse actually happened, and directory_expanded_changed needs to fire for exactly that, exactly once per real change (not a same-value re-assignment). */
    private void set_expanded (Gtk.TreeListRow row, FileNode node, bool expanded) {
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
            set_expanded (list_row, node, !list_row.expanded);
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
        var row = row_at (x, y);
        return row == null ? null : row.bound_node;
    }

    /** The FileTreeRow (the one on_setup() stashed onto its widget) under `(x, y)`, or null over the tree's empty background. */
    private FileTreeRow? row_at (double x, double y) {
        var widget = row_widget_at (x, y);
        return widget == null ? null : widget.get_data<FileTreeRow?> ("row");
    }

    /** The row widget (the one on_setup() stashed a FileTreeRow onto) under `(x, y)`, or null over the tree's empty background. */
    private Gtk.Widget? row_widget_at (double x, double y) {
        Gtk.Widget? widget = list_view.pick (x, y, Gtk.PickFlags.DEFAULT);
        while (widget != null) {
            if (widget.get_data<FileTreeRow?> ("row") != null) {
                return widget;
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
                set_expanded (list_row, node, !list_row.expanded);
            } else {
                file_activated (node.path, false);
            }
        });
        list_view.add_controller (click);
    }

    /**
     * Dragging a row here is a Cut+Paste in one gesture: it reuses
     * paste_requested with `is_cut = true` on drop, the exact signal the
     * Cut/Paste context-menu items already fire — no new Controller/Model
     * code needed for the move itself. One Gtk.DragSource/Gtk.DropTarget
     * pair on `list_view` itself, not per-row — matching every other
     * primary-button controller in this class (see setup_background_click/
     * setup_repeat_click_toggle's own comments on why a per-row gesture
     * raced GtkListView's built-in click handling here before).
     */
    private void setup_drag_drop () {
        FileDrag.make_source (list_view, (x, y) => {
            var widget = row_widget_at (x, y);
            var row = row_at (x, y);
            if (widget == null || row == null || row.bound_node == null) {
                return null;
            }
            return new FileDragCandidate (row.bound_node.path, widget);
        });

        var drop_target = new Gtk.DropTarget (typeof (FileDragPayload), Gdk.DragAction.MOVE);
        drop_target.motion.connect (on_drag_motion);
        drop_target.leave.connect (on_drag_leave);
        drop_target.drop.connect (on_drag_drop);
        list_view.add_controller (drop_target);
    }

    /**
     * Highlights the folder row directly under the pointer and starts (or
     * restarts, on moving to a different row) the auto-expand timer for
     * it. Only a directory — or the tree's own background, meaning the
     * workspace root — is a valid drop target; hovering a file row shows
     * the "no drop" cursor and never highlights, same as dropping there
     * would just be rejected by on_drag_drop() below.
     */
    private Gdk.DragAction on_drag_motion (double x, double y) {
        var widget = row_widget_at (x, y);
        var row = row_at (x, y);
        FileNode? node = row == null ? null : row.bound_node;

        var target_widget = (node != null && node.is_directory) ? native_row_widget (widget) : null;
        if (target_widget != drag_hover_widget) {
            set_drag_hover (drag_hover_widget, false);
            drag_hover_widget = target_widget;
            set_drag_hover (drag_hover_widget, true);
        }
        reset_hover_expand_timer (row, node);

        if (widget == null) {
            return Gdk.DragAction.MOVE; // background — drop lands in the workspace root
        }
        return node != null && node.is_directory ? Gdk.DragAction.MOVE : 0;
    }

    /**
     * The actual GTK-internal "row"-named wrapper `row_widget` sits inside
     * — the same element native hover/selection styling itself targets
     * (`listview.data-table row` already relies on this for the 22px row
     * height/border-radius above). `row_widget` (FileTreeRow's own
     * Gtk.Box) is only its *child*: toggling `.drag-hover` there instead
     * doesn't match native hover pixel-for-pixel (confirmed live, not
     * assumed) — this is the same "some internal wrapper sits between
     * them" the constructor's own CSS-provider comment already found.
     */
    private Gtk.Widget? native_row_widget (Gtk.Widget? row_widget) {
        return row_widget == null ? null : row_widget.get_parent ();
    }

    private void on_drag_leave () {
        set_drag_hover (drag_hover_widget, false);
        drag_hover_widget = null;
        cancel_hover_expand_timer ();
    }

    private void set_drag_hover (Gtk.Widget? row_widget, bool hover) {
        if (row_widget == null) {
            return;
        }
        if (hover) {
            row_widget.add_css_class (DRAG_HOVER_CSS_CLASS);
        } else {
            row_widget.remove_css_class (DRAG_HOVER_CSS_CLASS);
        }
    }

    /** Schedules HOVER_EXPAND_MS from now to expand `row`, unless it's already expanded (or isn't a directory) — cancels whatever was already pending for the previous row first, so only ever the *current* hover can fire. */
    private void reset_hover_expand_timer (FileTreeRow? row, FileNode? node) {
        cancel_hover_expand_timer ();
        if (row == null || row.bound_row == null || node == null || !node.is_directory || row.bound_row.expanded) {
            return;
        }

        var list_row = row.bound_row;
        hover_expand_timeout_id = Timeout.add (HOVER_EXPAND_MS, () => {
            hover_expand_timeout_id = 0;
            set_expanded (list_row, node, true);
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
        set_drag_hover (drag_hover_widget, false);
        drag_hover_widget = null;
        cancel_hover_expand_timer ();

        var payload = value.get_object () as FileDragPayload;
        if (payload == null) {
            return false;
        }

        var target = node_at (x, y);
        if (target != null && !target.is_directory) {
            return false;
        }

        // Dropped a folder directly onto itself — almost always the user
        // starting a drag, changing their mind, and letting go right back
        // where they picked it up, not a real move attempt. move_child()
        // would just throw its own self/descendant guard for this exact
        // case anyway; quietly doing nothing instead of surfacing that as
        // an error dialog for what wasn't really an attempted move.
        if (target != null && target.path == payload.path) {
            return true;
        }

        var target_path = target == null ? root_node.path : target.path;

        // Dropped back into the folder it's already in — also a no-op,
        // not a mistake worth an error dialog either.
        if (Path.get_dirname (payload.path) == target_path) {
            return true;
        }

        paste_requested (payload.path, true, target_path);
        return true;
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

        ContextMenu.show (list_view, x, y, (popover, box) => {
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
        });
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
            set_expanded (list_row, target, true);
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
