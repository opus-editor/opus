/**
 * Wires {@link FileTreeController}'s file activations, creations and
 * deletions into {@link EditorController} — the only glue between the
 * sidebar and the tab/editor pane.
 */
public class MainController : Object {
    private FileTreeController file_tree_controller;
    private EditorController editor_controller;

    public MainController (FileTreeController file_tree_controller, EditorController editor_controller) {
        this.file_tree_controller = file_tree_controller;
        this.editor_controller = editor_controller;

        file_tree_controller.file_activated.connect ((path, open_permanent) => {
            open (path, open_permanent);
        });
        // A New File is opened as a permanent tab right away, same as a
        // double-click — there's no reason to make the user go find and
        // click the file they just named.
        file_tree_controller.file_created.connect ((path) => {
            open (path, true);
        });
        file_tree_controller.delete_entry_requested.connect ((path) => on_delete_requested.begin (path));
    }

    private void open (string path, bool open_permanent) {
        try {
            editor_controller.open (path, open_permanent);
        } catch (Error e) {
            warning ("failed to open %s: %s", path, e.message);
        }
    }

    /**
     * A folder, or a file with no dirty open tab, deletes immediately —
     * same as before. A file with unsaved changes open asks first (same
     * shape VS Code uses); declining leaves it untouched, on disk and in
     * its tab. Either way, once actually deleted, whatever tab was open
     * for it closes outright — nothing left on disk to save it back to.
     */
    private async void on_delete_requested (string path) {
        if (editor_controller.is_dirty (path)) {
            var confirmed = yield file_tree_controller.confirm_delete_with_unsaved_changes (Path.get_basename (path));
            if (!confirmed) {
                return;
            }
        }

        file_tree_controller.delete_entry (path);
        editor_controller.discard_tab (path);
    }
}
