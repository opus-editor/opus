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

    Test.add_func ("/models/workspace/resolve/no_argument_is_blank", () => {
        string? folder_path;
        string? file_path;
        Workspace.resolve ({ "opus" }, out folder_path, out file_path);

        assert_null (folder_path);
        assert_null (file_path);
    });

    return Test.run ();
}
