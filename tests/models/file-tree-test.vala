// Builds a small fixture under a fresh temp directory and tears it down
// after the test runs. Layout:
//
//   <root>/
//     .hidden-dir/
//     .hidden-file
//     b-dir/
//       nested.txt
//     a-file.txt
//     Z-file.txt
private string make_fixture () throws Error {
    var root_path = DirUtils.make_tmp ("opus-file-tree-test-XXXXXX");

    DirUtils.create (Path.build_filename (root_path, ".hidden-dir"), 0755);
    FileUtils.set_contents (Path.build_filename (root_path, ".hidden-file"), "");

    DirUtils.create (Path.build_filename (root_path, "b-dir"), 0755);
    FileUtils.set_contents (Path.build_filename (root_path, "b-dir", "nested.txt"), "");

    FileUtils.set_contents (Path.build_filename (root_path, "a-file.txt"), "");
    FileUtils.set_contents (Path.build_filename (root_path, "Z-file.txt"), "");

    return root_path;
}

private void remove_recursive (string path) {
    if (FileUtils.test (path, FileTest.IS_DIR)) {
        Dir dir;
        try {
            dir = Dir.open (path);
        } catch (Error e) {
            return;
        }
        string? entry;
        while ((entry = dir.read_name ()) != null) {
            remove_recursive (Path.build_filename (path, entry));
        }
        DirUtils.remove (path);
    } else {
        FileUtils.remove (path);
    }
}

private FileNode? find_child (FileNode node, string name) {
    for (uint i = 0; i < node.children.length; i++) {
        if (node.children[i].name == name) {
            return node.children[i];
        }
    }
    return null;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/file-tree/orders-directories-before-files-alphabetically", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var children = tree.root.children;
            assert (children.length == 5);
            assert (children[0].name == ".hidden-dir");
            assert (children[1].name == "b-dir");
            assert (children[2].name == ".hidden-file");
            assert (children[3].name == "a-file.txt");
            assert (children[4].name == "Z-file.txt");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/includes-hidden-entries", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            assert (find_child (tree.root, ".hidden-dir") != null);
            assert (find_child (tree.root, ".hidden-file") != null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/excludes-git-directory", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            DirUtils.create (Path.build_filename (root_path, ".git"), 0755);
            FileUtils.set_contents (Path.build_filename (root_path, ".git", "config"), "");

            var tree = new FileTree (root_path);
            assert (find_child (tree.root, ".git") == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/walks-nested-directories", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var b_dir = find_child (tree.root, "b-dir");
            assert (b_dir != null);
            tree.ensure_children_loaded (b_dir);
            assert (b_dir.children.length == 1);
            assert (b_dir.children[0].name == "nested.txt");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/directory-node-is-directory-with-children", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var b_dir = find_child (tree.root, "b-dir");
            assert (b_dir != null);
            assert (b_dir.is_directory);
            tree.ensure_children_loaded (b_dir);
            assert (b_dir.children.length == 1);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    // The scanning laziness this whole class exists for (see its own doc
    // comment) — a directory one level below root starts unscanned right
    // after construction, only ever loaded on demand.
    Test.add_func ("/file-tree/children-loaded/directory-starts-unloaded", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var b_dir = find_child (tree.root, "b-dir");

            assert (!b_dir.children_loaded);
            assert (b_dir.children.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/children-loaded/root-starts-loaded", () => {
        // Root is the one exception: FileTree's own constructor builds it
        // via build_node(), which always scans its *own* immediate
        // children — the top level has to be there right away for the
        // sidebar to show anything at all before any row is expanded.
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);

            assert (tree.root.children_loaded);
            assert (tree.root.children.length == 5);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/ensure-children-loaded/scans-an-unloaded-directory", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var b_dir = find_child (tree.root, "b-dir");

            tree.ensure_children_loaded (b_dir);

            assert (b_dir.children_loaded);
            assert (b_dir.children.length == 1);
            assert (b_dir.children[0].name == "nested.txt");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/ensure-children-loaded/is-a-no-op-once-already-loaded", () => {
        // Same identity-preservation reasoning as
        // rescan-children/keeps-the-same-node-for-an-unaffected-entry
        // below: a redundant rescan would hand back a *different*
        // FileNode for "nested.txt", silently collapsing anything
        // expanded under it in the sidebar.
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var b_dir = find_child (tree.root, "b-dir");
            tree.ensure_children_loaded (b_dir);
            var nested_before = b_dir.children[0];

            tree.ensure_children_loaded (b_dir);

            assert (b_dir.children[0] == nested_before);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/file-node-is-not-directory-and-has-no-children", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var a_file = find_child (tree.root, "a-file.txt");
            assert (a_file != null);
            assert (!a_file.is_directory);
            assert (a_file.children.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/create-child/creates-a-file-on-disk", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);

            var node = tree.create_child (tree.root, "new-file.txt", false);

            assert (!node.is_directory);
            assert (FileUtils.test (node.path, FileTest.EXISTS));
            assert (!FileUtils.test (node.path, FileTest.IS_DIR));
            assert (find_child (tree.root, "new-file.txt") == node);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/create-child/creates-a-directory-on-disk", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);

            var node = tree.create_child (tree.root, "new-dir", true);

            assert (node.is_directory);
            assert (FileUtils.test (node.path, FileTest.IS_DIR));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/create-child/inserts-in-sorted-order", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);

            // Fixture's children are already: .hidden-dir, b-dir,
            // .hidden-file, a-file.txt, Z-file.txt — a new directory goes
            // after the existing directories but before any file.
            tree.create_child (tree.root, "c-dir", true);

            var children = tree.root.children;
            assert (children.length == 6);
            assert (children[0].name == ".hidden-dir");
            assert (children[1].name == "b-dir");
            assert (children[2].name == "c-dir");
            assert (children[3].name == ".hidden-file");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/create-child/throws-if-the-name-already-exists", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);

            var threw = false;
            try {
                tree.create_child (tree.root, "a-file.txt", false);
            } catch (Error e) {
                threw = true;
            }
            assert (threw);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/rename-child/renames-on-disk-and-in-the-tree", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var old_node = find_child (tree.root, "a-file.txt");
            var old_path = old_node.path;

            var renamed = tree.rename_child (tree.root, old_node, "renamed.txt");

            assert (renamed.name == "renamed.txt");
            assert (!FileUtils.test (old_path, FileTest.EXISTS));
            assert (FileUtils.test (renamed.path, FileTest.EXISTS));
            assert (find_child (tree.root, "a-file.txt") == null);
            assert (find_child (tree.root, "renamed.txt") == renamed);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/rename-child/renaming-a-directory-updates-its-children-paths", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var b_dir = find_child (tree.root, "b-dir");

            var renamed = tree.rename_child (tree.root, b_dir, "renamed-dir");

            assert (renamed.children.length == 1);
            assert (renamed.children[0].name == "nested.txt");
            assert (renamed.children[0].path == Path.build_filename (renamed.path, "nested.txt"));
            assert (FileUtils.test (renamed.children[0].path, FileTest.EXISTS));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/delete-child/trashes-and-removes-from-the-tree", () => {
        // Whether trashing a file actually succeeds depends on the
        // filesystem it lives on having a trash implementation at all —
        // e.g. it fails on this very test's own tmpfs fixture directory.
        // Covers both outcomes rather than assuming one: on success, gone
        // from disk and from the tree; on failure, untouched in both — not
        // silently dropped from the tree while still sitting on disk.
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var node = find_child (tree.root, "a-file.txt");
            var path = node.path;

            try {
                tree.delete_child (tree.root, node);
                assert (!FileUtils.test (path, FileTest.EXISTS));
                assert (find_child (tree.root, "a-file.txt") == null);
            } catch (Error e) {
                assert (FileUtils.test (path, FileTest.EXISTS));
                assert (find_child (tree.root, "a-file.txt") == node);
            }
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/rescan-children/picks-up-a-file-added-externally", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            FileUtils.set_contents (Path.build_filename (root_path, "added-externally.txt"), "");

            tree.rescan_children (tree.root);

            assert (find_child (tree.root, "added-externally.txt") != null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/rescan-children/drops-a-node-for-a-file-removed-externally", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            FileUtils.remove (Path.build_filename (root_path, "a-file.txt"));

            tree.rescan_children (tree.root);

            assert (find_child (tree.root, "a-file.txt") == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/rescan-children/keeps-the-same-node-for-an-unaffected-entry", () => {
        // Matters beyond just "no needless work": FileTreeView's own
        // diffing (sync_store()) is identity-based, so a rescan that
        // rebuilt every child fresh — even ones nothing happened to —
        // would collapse any of their own already-expanded subfolders on
        // every single external change, not just the one that actually
        // happened.
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var b_dir_before = find_child (tree.root, "b-dir");
            FileUtils.set_contents (Path.build_filename (root_path, "added-externally.txt"), "");

            tree.rescan_children (tree.root);

            assert (find_child (tree.root, "b-dir") == b_dir_before);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/rescan-children/replaces-a-node-whose-kind-changed", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var old_file = find_child (tree.root, "a-file.txt");
            FileUtils.remove (old_file.path);
            DirUtils.create (old_file.path, 0755);

            tree.rescan_children (tree.root);

            var replaced = find_child (tree.root, "a-file.txt");
            assert (replaced != null);
            assert (replaced != old_file);
            assert (replaced.is_directory);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/move-child/moves-a-file-on-disk-and-into-the-new-parent", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var a_file = find_child (tree.root, "a-file.txt");
            var b_dir = find_child (tree.root, "b-dir");
            var old_path = a_file.path;

            var moved = tree.move_child (tree.root, a_file, b_dir);

            assert (!FileUtils.test (old_path, FileTest.EXISTS));
            assert (FileUtils.test (moved.path, FileTest.EXISTS));
            assert (find_child (tree.root, "a-file.txt") == null);
            assert (find_child (b_dir, "a-file.txt") == moved);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/move-child/throws-when-moving-a-directory-into-itself", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var b_dir = find_child (tree.root, "b-dir");

            var threw = false;
            try {
                tree.move_child (tree.root, b_dir, b_dir);
            } catch (Error e) {
                threw = true;
            }
            assert (threw);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/move-child/throws-when-moving-a-directory-into-its-own-descendant", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var b_dir = find_child (tree.root, "b-dir");
            var nested_dir = tree.create_child (b_dir, "nested-dir", true);

            var threw = false;
            try {
                tree.move_child (tree.root, b_dir, nested_dir);
            } catch (Error e) {
                threw = true;
            }
            assert (threw);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/copy-child/copies-a-file-on-disk-and-into-the-tree-without-touching-the-original", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var a_file = find_child (tree.root, "a-file.txt");
            var b_dir = find_child (tree.root, "b-dir");

            var copied = tree.copy_child (a_file, b_dir);

            assert (FileUtils.test (a_file.path, FileTest.EXISTS));
            assert (FileUtils.test (copied.path, FileTest.EXISTS));
            assert (find_child (tree.root, "a-file.txt") == a_file);
            assert (find_child (b_dir, "a-file.txt") == copied);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/copy-child/copies-a-directory-recursively", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var b_dir = find_child (tree.root, "b-dir");
            tree.ensure_children_loaded (b_dir);
            var c_dir = tree.create_child (tree.root, "c-dir", true);

            var copied = tree.copy_child (b_dir, c_dir);

            assert (copied.is_directory);
            assert (copied.children.length == 1);
            assert (copied.children[0].name == "nested.txt");
            assert (FileUtils.test (copied.children[0].path, FileTest.EXISTS));
            assert (FileUtils.test (find_child (b_dir, "nested.txt").path, FileTest.EXISTS));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/copy-child/throws-when-copying-a-directory-into-itself", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var b_dir = find_child (tree.root, "b-dir");

            var threw = false;
            try {
                tree.copy_child (b_dir, b_dir);
            } catch (Error e) {
                threw = true;
            }
            assert (threw);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/copy-child/throws-when-copying-a-directory-into-its-own-descendant", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var b_dir = find_child (tree.root, "b-dir");
            var nested_dir = tree.create_child (b_dir, "nested-dir", true);

            var threw = false;
            try {
                tree.copy_child (b_dir, nested_dir);
            } catch (Error e) {
                threw = true;
            }
            assert (threw);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/find/finds-a-nested-node-by-path", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);
            var b_dir = find_child (tree.root, "b-dir");
            tree.ensure_children_loaded (b_dir);
            var expected = b_dir.children[0];

            var found = tree.find (expected.path);

            assert (found == expected);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/file-tree/find/returns-null-for-an-unknown-path", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var tree = new FileTree (root_path);

            assert (tree.find (Path.build_filename (root_path, "nope")) == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
