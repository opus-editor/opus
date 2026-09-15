/**
 * Gtk-backed {@link IFileTreeView}: a {@link Gtk.ListView} over a
 * {@link Gtk.TreeListModel}, with {@link FileTreeRow} as its row widget.
 *
 * The tree is built eagerly from the {@link FileNode} handed to
 * {@link populate}: every directory's children are already known, so the
 * model's create-func never touches the filesystem, it just wraps the
 * already-loaded children of the directory being expanded.
 */
public class FileTreeView : Object, IFileTreeView {
    private Gtk.ScrolledWindow scrolled_window;
    private Gtk.ListView list_view;
    private Gtk.TreeListModel? tree_model;
    private Gtk.SingleSelection? selection;

    public Gtk.Widget widget { get { return scrolled_window; } }

    public FileTreeView () {
        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect (on_setup);
        factory.bind.connect (on_bind);
        factory.unbind.connect (on_unbind);

        list_view = new Gtk.ListView (null, factory);

        scrolled_window = new Gtk.ScrolledWindow ();
        scrolled_window.child = list_view;
    }

    public void populate (FileNode root) {
        // The gtk4 vapi types this constructor's create_func parameter as
        // GLib.Object, but GTK's real C typedef (GtkTreeListModelCreateModelFunc)
        // takes an untyped gpointer — a vapi imprecision, not a real ABI
        // mismatch. GCC flags it as an incompatible-pointer-types warning that
        // no combination of -Wno-incompatible-pointer-types, #pragma GCC
        // diagnostic, or -std= reliably suppresses on this toolchain (verified);
        // harmless and unavoidable short of hand-writing a raw extern binding.
        tree_model = new Gtk.TreeListModel (children_store (root), false, false, on_create_model);
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

    private ListModel? on_create_model (Object item) {
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
        list_item.child = row;
    }

    private void on_bind (Object item) {
        var list_item = (Gtk.ListItem) item;
        var list_row = (Gtk.TreeListRow) list_item.item;
        var node = (FileNode) list_row.item;
        ((FileTreeRow) list_item.child).bind (list_row, node);
    }

    private void on_unbind (Object item) {
        var list_item = (Gtk.ListItem) item;
        ((FileTreeRow) list_item.child).unbind ();
    }
}
