/**
 * A single node in a file tree: plain data, no filesystem access.
 *
 * A directory node's {@link children} lists its immediate entries; a file
 * node always has an empty {@link children} list.
 */
public class FileNode : Object {
  public string path { get; private set; }
  public string name { get; private set; }
  public bool is_directory { get; private set; }
  public GenericArray<FileNode> children;

  /** Whether this directory's own immediate children have actually been scanned from disk yet — see FileTree.ensure_children_loaded(). Always true for a plain file (nothing to scan); false for a directory until something asks for it, typically the sidebar row actually expanding. */
  public bool children_loaded { get; set; }

  /** This node's name is being edited inline in the tree — a New File/Folder still being named (blank `name`), or an existing entry being renamed (its current `name`). Which one is for whoever set it (EditorView.FileTree) to track; EditorView.FileTreeRow just needs to know an edit is in progress. */
  public bool is_editing_name { get; set; default = false; }

  /** This node is on the tree's own internal Cut clipboard, awaiting a Paste — shown dimmed until then. */
  public bool is_cut { get; set; default = false; }

  public FileNode (string path, string name, bool is_directory) {
    this.path = path;
    this.name = name;
    this.is_directory = is_directory;
    this.children = new GenericArray<FileNode> ();
    this.children_loaded = !is_directory;
  }
}
