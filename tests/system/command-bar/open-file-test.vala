/**
 * Ctrl+P end to end through the real window: the bar opens over the
 * linked folder, typing narrows the walked file list, Return opens the
 * best match as a tab — and before anything is typed, the files opened
 * so far are what it lists.
 */

//   <root>/
//     src/
//       App.vala
//       models/
//         file-tree.vala
//     README.md
private string make_fixture () throws Error {
    var root_path = DirUtils.make_tmp ("opus-command-bar-test-XXXXXX");
    DirUtils.create (Path.build_filename (root_path, "src"), 0755);
    FileUtils.set_contents (Path.build_filename (root_path, "src", "App.vala"), "app\n");
    DirUtils.create (Path.build_filename (root_path, "src", "models"), 0755);
    FileUtils.set_contents (Path.build_filename (root_path, "src", "models", "file-tree.vala"), "tree\n");
    FileUtils.set_contents (Path.build_filename (root_path, "README.md"), "readme\n");
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

    Test.add_func ("/system/command_bar/return_opens_the_best_match_as_a_tab", () => {
        string folder = "";
        try {
            folder = make_fixture ();
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 108, folder);

            opus.open_command_bar ();
            opus.command_bar_type ("filetree");
            var items = opus.wait_for_command_bar_items ();
            opus.command_bar_accept ();

            assert_cmpint (items.length, CompareOperator.EQ, 1);
            assert_cmpstr (items[0], CompareOperator.EQ, Path.build_filename (folder, "src", "models", "file-tree.vala"));
            opus.assert_active_tab (Path.build_filename (folder, "src", "models", "file-tree.vala"));

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        } finally {
            remove_recursive (folder);
        }
    });

    Test.add_func ("/system/command_bar/empty_query_lists_the_files_opened_so_far", () => {
        string folder = "";
        try {
            folder = make_fixture ();
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 108, folder);
            var readme = Path.build_filename (folder, "README.md");
            opus.open_tab (readme);

            opus.open_command_bar ();
            var items = opus.wait_for_command_bar_items ();

            assert_cmpint (items.length, CompareOperator.EQ, 1);
            assert_cmpstr (items[0], CompareOperator.EQ, readme);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        } finally {
            remove_recursive (folder);
        }
    });

    return Test.run ();
}
