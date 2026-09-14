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

    public FileNode (string path, string name, bool is_directory) {
        this.path = path;
        this.name = name;
        this.is_directory = is_directory;
        this.children = new GenericArray<FileNode> ();
    }
}
