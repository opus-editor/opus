/**
 * Facade for the sidebar's file tree. A Controller only ever sees this
 * interface — never the Gtk widgets backing it.
 */
public interface IFileTreeView : Object {
    /**
     * A file row was clicked. `open_permanent` is true for a double-click
     * (open/promote to a permanent tab), false for a single-click (preview).
     */
    public signal void file_activated (string path, bool open_permanent);

    /** Replaces the displayed tree with the entries under `root`. */
    public abstract void populate (FileNode root);

    /** Highlights the row for `path` as selected. */
    public abstract void select_path (string path);
}
