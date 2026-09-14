// Builds a small fixture under a fresh temp directory and tears it down
// after the test runs. Layout:
//
//   <root>/
//     a-dir/
//     a-file.txt
private string make_fixture () throws Error {
    var root_path = DirUtils.make_tmp ("codi-gtk-file-tree-controller-test-XXXXXX");

    DirUtils.create (Path.build_filename (root_path, "a-dir"), 0755);
    FileUtils.set_contents (Path.build_filename (root_path, "a-file.txt"), "");

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

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/controllers/file-tree/populates-view-with-root", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var view = new FakeFileTreeView ();

            new FileTreeController (view, root_path);

            assert (view.populated_root != null);
            assert (view.populated_root.path == root_path);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/controllers/file-tree/forwards-file-activated-from-view", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var view = new FakeFileTreeView ();
            var controller = new FileTreeController (view, root_path);

            string? received_path = null;
            bool? received_open_permanent = null;
            controller.file_activated.connect ((path, open_permanent) => {
                received_path = path;
                received_open_permanent = open_permanent;
            });

            var activated_path = Path.build_filename (root_path, "a-file.txt");
            view.activate_file (activated_path, true);

            assert (received_path == activated_path);
            assert (received_open_permanent == true);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/controllers/file-tree/forwards-preview-activation", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var view = new FakeFileTreeView ();
            var controller = new FileTreeController (view, root_path);

            bool? received_open_permanent = null;
            controller.file_activated.connect ((path, open_permanent) => {
                received_open_permanent = open_permanent;
            });

            view.activate_file (Path.build_filename (root_path, "a-file.txt"), false);

            assert (received_open_permanent == false);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
