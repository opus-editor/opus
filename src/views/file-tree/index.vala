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

    public Gtk.Widget widget { get { return scrolled_window; } }

    /**
     * A file row was clicked. `open_permanent` is true for a double-click
     * (open/promote to a permanent tab), false for a single-click (preview).
     */
    public signal void file_activated (string path, bool open_permanent);

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

        // .data-table alone still isn't tight enough; trims it further.
        // Must be a descendant selector ("row", no ">") — row isn't a direct
        // child of listview (some internal wrapper sits between them, found
        // by testing with a visible color first rather than guessing twice).
        // Gtk.StyleContext.add_provider_for_display is deprecated since GTK
        // 4.10 (removed in GTK 5); no replacement exists yet for registering
        // a provider scoped to part of the app (checked the Vala bindings —
        // Gtk.Widget exposes nothing equivalent).
        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_string ("""
            listview.data-table row {
                padding-top: 2px;
                padding-bottom: 2px;
                min-height: 0px;
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
    }

    public void populate (FileNode root) {
        tree_model = tree_list_model_new_raw (children_store (root), false, false, on_create_model_raw, null, null);
        selection = new Gtk.SingleSelection (tree_model);
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

    private static ListModel? on_create_model_raw (void* item, void* user_data) {
        var node = (FileNode) item;
        if (!node.is_directory || node.children.length == 0) {
            return null;
        }
        return children_store (node);
    }

    private void on_setup (Object item) {
        var list_item = (Gtk.ListItem) item;
        var row = new FileTreeRow ();
        row.file_clicked.connect ((path, open_permanent) => file_activated (path, open_permanent));
        // list_item.child only holds the Gtk.Widget; stash the FileTreeRow
        // facade that owns it so on_bind/on_unbind can get back to it.
        row.widget.set_data ("row", row);
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
}
