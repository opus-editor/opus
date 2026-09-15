/**
 * Wires {@link FileTreeController}'s file activations into
 * {@link EditorController}'s open calls — the only glue between the
 * sidebar and the tab/editor pane.
 */
public class MainController : Object {
    public MainController (FileTreeController file_tree_controller, EditorController editor_controller) {
        file_tree_controller.file_activated.connect ((path, open_permanent) => {
            try {
                editor_controller.open (path, open_permanent);
            } catch (Error e) {
                warning ("failed to open %s: %s", path, e.message);
            }
        });
    }
}
