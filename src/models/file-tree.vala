/**
 * Builds a {@link FileNode} tree by walking a directory on disk.
 *
 * Within each directory, children are ordered directories-first, then
 * alphabetically (case-insensitive). Hidden entries (dotfiles/dotdirs) are
 * included like any other entry — no filtering is applied.
 */
public class FileTree : Object {
    private const string ENTRY_ATTRIBUTES = FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE;

    public FileNode root { get; private set; }

    public FileTree (string root_path) throws Error {
        root = build_node (root_path);
    }

    private FileNode build_node (string path) throws Error {
        var file = File.new_for_path (path);
        var file_info = file.query_info (ENTRY_ATTRIBUTES, FileQueryInfoFlags.NONE);
        var is_directory = file_info.get_file_type () == FileType.DIRECTORY;
        var node = new FileNode (path, Path.get_basename (path), is_directory);

        if (is_directory) {
            var enumerator = file.enumerate_children (ENTRY_ATTRIBUTES, FileQueryInfoFlags.NONE);
            FileInfo? entry_info;
            while ((entry_info = enumerator.next_file ()) != null) {
                var child_path = Path.build_filename (path, entry_info.get_name ());
                insert_sorted (node.children, build_node (child_path));
            }
        }

        return node;
    }

    // Inserts `child` keeping `children` ordered directories-first, then
    // alphabetically (case-insensitive) — a plain insertion sort, so we
    // don't rely on GenericArray.sort()'s generated comparator wrapper.
    private static void insert_sorted (GenericArray<FileNode> children, FileNode child) {
        uint index = 0;
        while (index < children.length && precedes (children[index], child)) {
            index++;
        }
        children.insert ((int) index, child);
    }

    private static bool precedes (FileNode a, FileNode b) {
        if (a.is_directory != b.is_directory) {
            return a.is_directory;
        }
        return strcmp (a.name.down (), b.name.down ()) <= 0;
    }
}
