// Opus.Plugins.EditorConfig.Hierarchy: the .editorconfig files from a file's directory up, over real folders.

private string make_tree () throws Error {
    return DirUtils.make_tmp ("opus-editorconfig-hierarchy-test-XXXXXX");
}

private void write_file (string root, string relative, string contents) throws Error {
    var path = Path.build_filename (root, relative);
    DirUtils.create_with_parents (Path.get_dirname (path), 0700);
    FileUtils.set_contents (path, contents);
}

private void remove_recursive (string path) {
    if (FileUtils.test (path, FileTest.IS_DIR) && !FileUtils.test (path, FileTest.IS_SYMLINK)) {
        try {
            var dir = Dir.open (path);
            string? entry;
            while ((entry = dir.read_name ()) != null) {
                remove_recursive (Path.build_filename (path, entry));
            }
        } catch (Error e) {
            return;
        }
        DirUtils.remove (path);
    } else {
        FileUtils.remove (path);
    }
}

private Opus.Plugins.EditorConfig.Resolved resolve (string root, string relative) {
    var path = Path.build_filename (root, relative);
    return Opus.Plugins.EditorConfig.Hierarchy.for_file (path).resolve (path);
}

private void test_the_closest_file_has_the_last_word () {
    try {
        var root = make_tree ();
        write_file (root, ".editorconfig", "root = true\n[*]\nindent_size = 2\nindent_style = space\n");
        write_file (root, "sub/.editorconfig", "[*]\nindent_size = 4\n");

        var resolved = resolve (root, "sub/a.rb");

        assert_cmpint (resolved.indent_size (), CompareOperator.EQ, 4);
        assert_true (resolved.insert_spaces () == true); // inherited from the root's file
        assert_cmpint ((int) resolve (root, "a.rb").indent_size (), CompareOperator.EQ, 2);
        remove_recursive (root);
    } catch (Error e) {
        error (e.message);
    }
}

private void test_root_true_stops_the_climb () {
    try {
        var root = make_tree ();
        write_file (root, ".editorconfig", "[*]\nindent_size = 2\n");
        write_file (root, "sub/.editorconfig", "root = true\n[*]\nindent_style = tab\n");

        var resolved = resolve (root, "sub/a.rb");

        assert_true (resolved.indent_size () == null);
        assert_true (resolved.insert_spaces () == false);
        remove_recursive (root);
    } catch (Error e) {
        error (e.message);
    }
}

private void test_unset_drops_what_an_outer_file_set () {
    try {
        var root = make_tree ();
        write_file (root, ".editorconfig", "root = true\n[*]\nindent_size = 2\nend_of_line = crlf\n");
        write_file (root, "sub/.editorconfig", "[*]\nindent_size = unset\n");

        var resolved = resolve (root, "sub/a.rb");

        assert_true (resolved.indent_size () == null);
        assert_true (resolved.end_of_line () == Document.LineEnding.CRLF);
        remove_recursive (root);
    } catch (Error e) {
        error (e.message);
    }
}

private void test_a_glob_with_a_slash_is_relative_to_its_own_files_directory () {
    try {
        var root = make_tree ();
        write_file (root, ".editorconfig", "root = true\n");
        write_file (root, "pkg/.editorconfig", "[src/*.js]\nindent_size = 3\n");

        assert_cmpint ((int) resolve (root, "pkg/src/a.js").indent_size (), CompareOperator.EQ, 3);
        assert_true (resolve (root, "pkg/a.js").indent_size () == null);
        assert_true (resolve (root, "src/a.js").indent_size () == null);
        remove_recursive (root);
    } catch (Error e) {
        error (e.message);
    }
}

private void test_without_any_file_everything_is_null () {
    try {
        var root = make_tree ();
        write_file (root, ".editorconfig", "root = true\n");

        var resolved = resolve (root, "deep/er/a.rb");

        assert_true (resolved.indent_size () == null && resolved.insert_spaces () == null && resolved.end_of_line () == null);
        remove_recursive (root);
    } catch (Error e) {
        error (e.message);
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/plugins/editorconfig/hierarchy/the_closest_file_has_the_last_word", test_the_closest_file_has_the_last_word);
    Test.add_func ("/plugins/editorconfig/hierarchy/root_true_stops_the_climb", test_root_true_stops_the_climb);
    Test.add_func ("/plugins/editorconfig/hierarchy/unset_drops_what_an_outer_file_set", test_unset_drops_what_an_outer_file_set);
    Test.add_func ("/plugins/editorconfig/hierarchy/a_glob_with_a_slash_is_relative_to_its_own_files_directory", test_a_glob_with_a_slash_is_relative_to_its_own_files_directory);
    Test.add_func ("/plugins/editorconfig/hierarchy/without_any_file_everything_is_null", test_without_any_file_everything_is_null);
    Test.run ();
}
