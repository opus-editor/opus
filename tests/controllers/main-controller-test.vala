// Builds a small fixture under a fresh temp directory and tears it down
// after the test runs. Layout:
//
//   <root>/
//     a-file.txt

private string make_fixture () throws Error {
    var root_path = DirUtils.make_tmp ("codi-gtk-main-controller-test-XXXXXX");
    FileUtils.set_contents (Path.build_filename (root_path, "a-file.txt"), "file content");
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

    Test.add_func ("/controllers/main/file_activation_opens_preview_in_editor", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var file_tree_view = new FakeFileTreeView ();
            var tab_bar_view = new FakeTabBarView ();
            var editor_view = new FakeEditorView ();

            var file_tree_controller = new FileTreeController (file_tree_view, root_path);
            var editor_controller = new EditorController (tab_bar_view, editor_view);
            new MainController (file_tree_controller, editor_controller);

            var file_path = Path.build_filename (root_path, "a-file.txt");
            file_tree_view.activate_file (file_path, false);

            assert_cmpstr (editor_view.text, CompareOperator.EQ, "file content");
            assert_true (tab_bar_view.preview_flags[file_path]);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/controllers/main/double_activation_opens_permanent_tab", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var file_tree_view = new FakeFileTreeView ();
            var tab_bar_view = new FakeTabBarView ();
            var editor_view = new FakeEditorView ();

            var file_tree_controller = new FileTreeController (file_tree_view, root_path);
            var editor_controller = new EditorController (tab_bar_view, editor_view);
            new MainController (file_tree_controller, editor_controller);

            var file_path = Path.build_filename (root_path, "a-file.txt");
            file_tree_view.activate_file (file_path, true);

            assert_false (tab_bar_view.preview_flags[file_path]);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
