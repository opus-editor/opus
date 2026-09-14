/** Test double for {@link ITabBarView}: records calls, never touches Gtk. */
public class FakeTabBarView : Object, ITabBarView {
    /** Open tab paths, in display order. */
    public GenericArray<string> open_paths = new GenericArray<string> ();
    public HashTable<string, string> labels = new HashTable<string, string> (str_hash, str_equal);
    public HashTable<string, bool> preview_flags = new HashTable<string, bool> (str_hash, str_equal);
    public HashTable<string, bool> modified_flags = new HashTable<string, bool> (str_hash, str_equal);
    public string? active_path = null;

    /** Set by a test before triggering a close, to script the dialog's answer. */
    public DiscardChoice next_discard_choice = DiscardChoice.CANCEL;

    public void add_tab (string path, string label, bool preview) {
        open_paths.add (path);
        labels[path] = label;
        preview_flags[path] = preview;
        modified_flags[path] = false;
    }

    public void remove_tab (string path) {
        for (uint i = 0; i < open_paths.length; i++) {
            if (open_paths[i] == path) {
                open_paths.remove_index (i);
                break;
            }
        }
        labels.remove (path);
        preview_flags.remove (path);
        modified_flags.remove (path);
        if (active_path == path) {
            active_path = null;
        }
    }

    public void set_active (string path) {
        active_path = path;
    }

    public void mark_preview (string path, bool preview) {
        preview_flags[path] = preview;
    }

    public void mark_modified (string path, bool modified) {
        modified_flags[path] = modified;
    }

    public async DiscardChoice confirm_unsaved_close (string filename) {
        return next_discard_choice;
    }

    /** Test helpers: simulate user interaction with the tab bar. */
    public void select_tab (string path) {
        tab_selected (path);
    }

    public void request_close (string path) {
        tab_close_requested (path);
    }

    public void double_click_tab (string path) {
        tab_double_clicked (path);
    }
}
