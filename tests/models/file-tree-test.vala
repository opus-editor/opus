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
            assert (b_dir.children.length == 1);
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

    return Test.run ();
}
