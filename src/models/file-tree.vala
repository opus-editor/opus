/**
 * Builds a {@link FileNode} tree by walking a directory on disk — one
 * level at a time, not the whole tree up front: build_node() scans a
 * node's own immediate children, but a child directory's own children
 * stay unscanned (FileNode.children_loaded false) until
 * {@link ensure_children_loaded} is actually asked for them, typically
 * when the sidebar row for it expands for the first time (see
 * FileTreeView.children_load_requested). Scanning eagerly and
 * recursively used to mean opening a folder with a large `node_modules`
 * walked every single file in it, synchronously, before the window even
 * showed anything — long enough for the desktop to flag Opus as "Not
 * Responding". VS Code's own real explorer has the same one-level-at-a-
 * time design for the same reason.
 *
 * Within each directory, children are ordered directories-first, then
 * alphabetically (case-insensitive). Hidden entries (dotfiles/dotdirs) are
 * included like any other entry, except `.git` — never useful to browse or
 * edit, so it's excluded outright rather than just hidden.
 */
public class FileTree : Object {
    private const string ENTRY_ATTRIBUTES = FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE;
    private const string EXCLUDED_ENTRY = ".git";

    public FileNode root { get; private set; }

    public FileTree (string root_path) throws Error {
        root = build_node (root_path);
    }

    /** Scans `node`'s own immediate children from disk if that hasn't happened yet — a no-op otherwise. The on-demand half of build_node()'s own one-level-at-a-time design. */
    public void ensure_children_loaded (FileNode node) throws Error {
        if (node.children_loaded) {
            return;
        }
        scan_children (node);
    }

    /** Finds the node at `path` within this tree, or null if there isn't one. */
    public FileNode? find (string path) {
        return find_in (root, path);
    }

    private static FileNode? find_in (FileNode node, string path) {
        if (node.path == path) {
            return node;
        }

        for (uint i = 0; i < node.children.length; i++) {
            var found = find_in (node.children[i], path);
            if (found != null) {
                return found;
            }
        }

        return null;
    }

    /** Creates `name` inside `parent` on disk — a plain empty file, or a directory — and inserts the resulting node into `parent.children` in the same sorted order the initial scan uses. Returns the new node. */
    public FileNode create_child (FileNode parent, string name, bool is_directory) throws Error {
        var path = Path.build_filename (parent.path, name);
        var file = File.new_for_path (path);

        if (is_directory) {
            file.make_directory ();
        } else {
            var stream = file.create (FileCreateFlags.NONE);
            stream.close ();
        }

        var node = new FileNode (path, name, is_directory);
        insert_sorted (parent.children, node);
        return node;
    }

    /**
     * Renames `node` (a child of `parent`) to `new_name` on disk, and
     * replaces it in `parent.children` with a freshly-scanned node built
     * from its new path. A fresh scan, not an in-place path/name update,
     * because renaming a directory changes the path of everything under
     * it too — `build_node` already knows how to walk that correctly, no
     * need for a second way to do it. Returns the new node.
     */
    public FileNode rename_child (FileNode parent, FileNode node, string new_name) throws Error {
        var renamed_file = File.new_for_path (node.path).set_display_name (new_name);

        parent.children.remove (node);
        var renamed_node = build_node (renamed_file.get_path ());
        insert_sorted (parent.children, renamed_node);
        return renamed_node;
    }

    /** Moves `node` (a child of `parent`) to the trash, and removes it from `parent.children`. */
    public void delete_child (FileNode parent, FileNode node) throws Error {
        File.new_for_path (node.path).trash ();
        parent.children.remove (node);
    }

    /**
     * Moves `node` (a child of `old_parent`) to become a child of
     * `new_parent`, on disk and in the tree — the model side of a
     * Cut+Paste. Throws if `new_parent` is `node` itself or one of its own
     * descendants (moving a directory into itself would recurse forever),
     * or if `new_parent` already has an entry with that name (the same
     * "already exists" failure `create_child` surfaces). Same fresh-scan
     * approach as `rename_child`, for the same reason: moving a directory
     * changes the path of everything under it.
     */
    public FileNode move_child (FileNode old_parent, FileNode node, FileNode new_parent) throws Error {
        if (is_self_or_descendant (node, new_parent)) {
            throw new IOError.INVALID_ARGUMENT ("Can’t move “%s” into itself.".printf (node.name));
        }

        var destination = File.new_for_path (Path.build_filename (new_parent.path, node.name));
        File.new_for_path (node.path).move (destination, FileCopyFlags.NONE);

        old_parent.children.remove (node);
        var moved_node = build_node (destination.get_path ());
        insert_sorted (new_parent.children, moved_node);
        return moved_node;
    }

    /**
     * Copies `node` (recursively, if it's a directory) into `new_parent`,
     * on disk and in the tree — the model side of a Copy+Paste. Same
     * self/descendant guard as `move_child`, for the same reason (a
     * directory copied into its own descendant would recurse forever);
     * unlike a move, copying into `node`'s own current parent is fine —
     * `create_child`'s "already exists" case would only trip if a distinct
     * destination happens to collide with something already there.
     */
    public FileNode copy_child (FileNode node, FileNode new_parent) throws Error {
        if (is_self_or_descendant (node, new_parent)) {
            throw new IOError.INVALID_ARGUMENT ("Can’t copy “%s” into itself.".printf (node.name));
        }

        var destination = File.new_for_path (Path.build_filename (new_parent.path, node.name));
        copy_recursive (File.new_for_path (node.path), destination);

        var copied_node = build_node (destination.get_path ());
        insert_sorted (new_parent.children, copied_node);
        return copied_node;
    }

    /**
     * Re-scans `node`'s own immediate children from disk — for an external
     * change (e.g. a file created via Nautilus) to a directory this tree
     * didn't make itself. An entry still present (same name, same
     * directory-or-file kind) keeps its existing FileNode — and, for a
     * directory, everything already loaded under it — rather than being
     * rebuilt from scratch; only genuinely new entries go through
     * build_node(), and ones no longer on disk are dropped. Preserving
     * identity for anything unaffected matters here the same way it does
     * for every other tree-mutating method — FileTreeView's own diffing
     * (sync_store()) needs it to avoid collapsing unrelated expanded
     * subfolders on every external change, not just the entry that
     * actually changed.
     */
    public void rescan_children (FileNode node) throws Error {
        var file = File.new_for_path (node.path);
        var enumerator = file.enumerate_children (ENTRY_ATTRIBUTES, FileQueryInfoFlags.NONE);

        var seen_names = new GenericArray<string> ();
        FileInfo? entry_info;
        while ((entry_info = enumerator.next_file ()) != null) {
            var name = entry_info.get_name ();
            if (name == EXCLUDED_ENTRY) {
                continue;
            }
            seen_names.add (name);

            var is_directory = entry_info.get_file_type () == FileType.DIRECTORY;
            var existing = find_child_by_name (node.children, name);
            if (existing != null) {
                if (existing.is_directory == is_directory) {
                    continue; // unchanged — keep the existing FileNode as-is
                }
                node.children.remove (existing); // same name, but a file replaced a directory or vice versa
            }

            insert_sorted (node.children, build_node (Path.build_filename (node.path, name)));
        }

        for (int i = node.children.length - 1; i >= 0; i--) {
            if (!contains_string (seen_names, node.children[i].name)) {
                node.children.remove_index (i);
            }
        }

        node.children_loaded = true;
    }

    private static FileNode? find_child_by_name (GenericArray<FileNode> children, string name) {
        for (uint i = 0; i < children.length; i++) {
            if (children[i].name == name) {
                return children[i];
            }
        }
        return null;
    }

    private static bool contains_string (GenericArray<string> array, string s) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == s) {
                return true;
            }
        }
        return false;
    }

    private static bool is_self_or_descendant (FileNode node, FileNode candidate) {
        return candidate == node || candidate.path.has_prefix (node.path + "/");
    }

    private static void copy_recursive (File source, File destination) throws Error {
        var info = source.query_info (FileAttribute.STANDARD_TYPE, FileQueryInfoFlags.NONE);
        if (info.get_file_type () != FileType.DIRECTORY) {
            source.copy (destination, FileCopyFlags.NONE);
            return;
        }

        destination.make_directory ();
        var enumerator = source.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
        FileInfo? entry_info;
        while ((entry_info = enumerator.next_file ()) != null) {
            copy_recursive (source.get_child (entry_info.get_name ()), destination.get_child (entry_info.get_name ()));
        }
    }

    /** Builds `path`'s own node — scanning its immediate children if it's a directory (see scan_children()), but no deeper: a child directory's own children stay unscanned. */
    private FileNode build_node (string path) throws Error {
        var file = File.new_for_path (path);
        var file_info = file.query_info (ENTRY_ATTRIBUTES, FileQueryInfoFlags.NONE);
        var is_directory = file_info.get_file_type () == FileType.DIRECTORY;
        var node = new FileNode (path, Path.get_basename (path), is_directory);

        if (is_directory) {
            scan_children (node);
        }

        return node;
    }

    /** Scans `node`'s own immediate children from disk — one level, see the class's own doc comment. Marks `node.children_loaded` true even if the directory turns out empty, so ensure_children_loaded() knows not to redo this. */
    private void scan_children (FileNode node) throws Error {
        var file = File.new_for_path (node.path);
        var enumerator = file.enumerate_children (ENTRY_ATTRIBUTES, FileQueryInfoFlags.NONE);
        FileInfo? entry_info;
        while ((entry_info = enumerator.next_file ()) != null) {
            if (entry_info.get_name () == EXCLUDED_ENTRY) {
                continue;
            }

            var child_path = Path.build_filename (node.path, entry_info.get_name ());
            var is_directory = entry_info.get_file_type () == FileType.DIRECTORY;
            insert_sorted (node.children, new FileNode (child_path, entry_info.get_name (), is_directory));
        }
        node.children_loaded = true;
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
