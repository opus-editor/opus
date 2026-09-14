/** Test double for {@link IFileTreeView}: records calls, never touches Gtk. */
public class FakeFileTreeView : Object, IFileTreeView {
    public FileNode? populated_root = null;
    public string? selected_path = null;

    public void populate (FileNode root) {
        populated_root = root;
    }

    public void select_path (string path) {
        selected_path = path;
    }

    /** Test helper: simulate a sidebar click. */
    public void activate_file (string path, bool open_permanent) {
        file_activated (path, open_permanent);
    }
}
