int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/models/workspace/resolve/directory_argument_links_a_folder", () => {
        string dir_path = "";
        try {
            dir_path = DirUtils.make_tmp ("opus-workspace-test-XXXXXX");

            string? folder_path;
            string? file_path;
            Workspace.resolve ({ "opus", dir_path }, out folder_path, out file_path);

            assert_cmpstr (folder_path, CompareOperator.EQ, dir_path);
            assert_null (file_path);
        } catch (Error e) {
            error ("failed to create fixture directory: %s", e.message);
        } finally {
            DirUtils.remove (dir_path);
        }
    });

    Test.add_func ("/models/workspace/resolve/file_argument_opens_a_file_with_no_folder", () => {
        string file_path = Path.build_filename (Environment.get_tmp_dir (), "opus-workspace-test-%u".printf (Random.next_int ()));

        try {
            FileUtils.set_contents (file_path, "");

            string? folder_path;
            string? resolved_file_path;
            Workspace.resolve ({ "opus", file_path }, out folder_path, out resolved_file_path);

            assert_null (folder_path);
            assert_cmpstr (resolved_file_path, CompareOperator.EQ, file_path);
        } catch (Error e) {
            error ("failed to create fixture file: %s", e.message);
        } finally {
            FileUtils.remove (file_path);
        }
    });

    Test.add_func ("/models/workspace/resolve/relative_argument_is_resolved_to_an_absolute_path", () => {
        // `opus .` (or any relative argument) must not leave folder_path/
        // file_path relative — every FileNode built from it downstream
        // would inherit that (FileTree just concatenates paths, it
        // doesn't resolve them), surfacing as far as a tab's own tooltip
        // showing something relative instead of a real absolute path.
        var original_cwd = Environment.get_current_dir ();
        string dir_path = "";
        try {
            dir_path = DirUtils.make_tmp ("opus-workspace-test-XXXXXX");
            Environment.set_current_dir (dir_path);

            string? folder_path;
            string? file_path;
            Workspace.resolve ({ "opus", "." }, out folder_path, out file_path);

            assert_true (Path.is_absolute (folder_path));
            // Not a plain string-equals against dir_path itself: if the
            // system's own tmp dir happens to be a symlink, GFile's own
            // resolution could legitimately differ from the raw string —
            // normalizing both sides the same way keeps this robust
            // either way, rather than assuming this machine's specifics.
            assert_cmpstr (folder_path, CompareOperator.EQ, File.new_for_path (dir_path).get_path ());
        } catch (Error e) {
            error ("failed to create fixture directory: %s", e.message);
        } finally {
            Environment.set_current_dir (original_cwd);
            DirUtils.remove (dir_path);
        }
    });

    Test.add_func ("/models/workspace/resolve/no_argument_is_blank", () => {
        string? folder_path;
        string? file_path;
        Workspace.resolve ({ "opus" }, out folder_path, out file_path);

        assert_null (folder_path);
        assert_null (file_path);
    });

    return Test.run ();
}
