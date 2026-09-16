/**
 * A single row in the file tree list: an icon, a name label, and (via the
 * {@link Gtk.TreeExpander} wrapping them) the chevron used to expand or
 * collapse a directory. Recycled by the list view's factory.
 *
 * Purely a display widget — click handling lives in {@link FileTreeView}'s
 * `Gtk.ListView.activate` handler, not a gesture of this row's own; see the
 * comment on `single-click-activate` there for why.
 *
 * Loads its widget tree via {@link Gtk.Builder} rather than a
 * composite-template subclass — same pattern as EditorView/MainWindowView.
 */
public class FileTreeRow : Object {
    private Gtk.Box box;
    private Gtk.TreeExpander expander;
    private Gtk.Image icon;
    private Gtk.Label label;

    public Gtk.Widget widget { get { return box; } }

    public FileTreeRow () {
        var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/file-tree/_row.ui");
        box = (Gtk.Box) builder.get_object ("row");
        expander = (Gtk.TreeExpander) builder.get_object ("expander");
        icon = (Gtk.Image) builder.get_object ("icon");
        label = (Gtk.Label) builder.get_object ("label");
    }

    /** Binds this row to `list_row`/`bound_node`, recycled from a previous use. */
    public void bind (Gtk.TreeListRow list_row, FileNode bound_node) {
        expander.list_row = list_row;
        label.label = bound_node.name;
        icon.visible = !bound_node.is_directory;
        icon.icon_name = "text-x-generic-symbolic";
    }

    /** Releases the row's data ahead of being recycled for another node. */
    public void unbind () {
        expander.list_row = null;
    }
}
