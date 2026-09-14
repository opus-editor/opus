/**
 * Builds the {@link FileTree} for a workspace root and drives an
 * {@link IFileTreeView} from it.
 *
 * Re-emits the view's `file_activated` signal as its own, so callers (e.g.
 * a future `MainController`) never need to depend on `IFileTreeView`
 * directly to react to file activations.
 */
public class FileTreeController : Object {
    private IFileTreeView view;

    public signal void file_activated (string path, bool open_permanent);

    public FileTreeController (IFileTreeView view, string root_path) throws Error {
        this.view = view;

        var tree = new FileTree (root_path);
        view.populate (tree.root);

        view.file_activated.connect ((path, open_permanent) => {
            file_activated (path, open_permanent);
        });
    }
}
