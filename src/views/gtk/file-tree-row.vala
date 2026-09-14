/**
 * A single row in the file tree list: an icon, a name label, and (via the
 * {@link Gtk.TreeExpander} wrapping them) the chevron used to expand or
 * collapse a directory. Recycled by the list view's factory, so the bound
 * {@link FileNode} is tracked on the instance rather than re-derived.
 */
[GtkTemplate (ui = "/io/github/alxmagro/Codi/ui/file-tree-row.ui")]
public class FileTreeRow : Gtk.Box {
    [GtkChild]
    private unowned Gtk.TreeExpander expander;
    [GtkChild]
    private unowned Gtk.Image icon;
    [GtkChild]
    private unowned Gtk.Label label;

    private FileNode? node;

    /** A bound file (never a directory) was clicked `n_press` times in a row. */
    public signal void file_clicked (string path, bool open_permanent);

    construct {
        var click = new Gtk.GestureClick ();
        click.pressed.connect (on_pressed);
        add_controller (click);
    }

    /** Binds this row to `list_row`/`bound_node`, recycled from a previous use. */
    public void bind (Gtk.TreeListRow list_row, FileNode bound_node) {
        node = bound_node;
        expander.list_row = list_row;
        label.label = bound_node.name;
        icon.icon_name = bound_node.is_directory ? "folder-symbolic" : "text-x-generic-symbolic";
    }

    /** Releases the row's data ahead of being recycled for another node. */
    public void unbind () {
        node = null;
        expander.list_row = null;
    }

    private void on_pressed (int n_press, double x, double y) {
        if (node == null || node.is_directory || n_press > 2) {
            return;
        }

        file_clicked (node.path, n_press == 2);
    }
}
