/**
 * A single row in the file tree list: an icon, a name label, and (via the
 * {@link Gtk.TreeExpander} wrapping them) the chevron used to expand or
 * collapse a directory. Recycled by the list view's factory, so the bound
 * {@link FileNode} is tracked on the instance rather than re-derived.
 *
 * Loads its widget tree via {@link Gtk.Builder} rather than a
 * composite-template subclass — same pattern as EditorView/MainWindowView.
 */
public class FileTreeRow : Object {
    private Gtk.Box box;
    private Gtk.TreeExpander expander;
    private Gtk.Image icon;
    private Gtk.Label label;

    private FileNode? node;

    public Gtk.Widget widget { get { return box; } }

    /** A bound file (never a directory) was clicked `n_press` times in a row. */
    public signal void file_clicked (string path, bool open_permanent);

    public FileTreeRow () {
        var builder = new Gtk.Builder.from_resource ("/io/github/alxmagro/Codi/file-tree/_row.ui");
        box = (Gtk.Box) builder.get_object ("row");
        expander = (Gtk.TreeExpander) builder.get_object ("expander");
        icon = (Gtk.Image) builder.get_object ("icon");
        label = (Gtk.Label) builder.get_object ("label");

        var click = new Gtk.GestureClick ();
        click.pressed.connect (on_pressed);
        box.add_controller (click);
    }

    /** Binds this row to `list_row`/`bound_node`, recycled from a previous use. */
    public void bind (Gtk.TreeListRow list_row, FileNode bound_node) {
        node = bound_node;
        expander.list_row = list_row;
        label.label = bound_node.name;
        icon.visible = !bound_node.is_directory;
        icon.icon_name = "text-x-generic-symbolic";
    }

    /** Releases the row's data ahead of being recycled for another node. */
    public void unbind () {
        node = null;
        expander.list_row = null;
    }

    private void on_pressed (int n_press, double x, double y) {
        if (node == null || n_press > 2) {
            return;
        }

        if (node.is_directory) {
            expander.list_row.expanded = !expander.list_row.expanded;
            return;
        }

        file_clicked (node.path, n_press == 2);
    }
}
