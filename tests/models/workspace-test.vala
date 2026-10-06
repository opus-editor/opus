int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/models/workspace/resolve/directory_argument_links_a_folder", () => {
        string dir_path = "";
        try {
            dir_path = DirUtils.make_tmp ("opus-workspace-test-XXXXXX");

            string? folder_path;
            string? file_path;
            Workspace.resolve ({ "opus", dir_path }, Environment.get_current_dir (), out folder_path, out file_path);

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
            Workspace.resolve ({ "opus", file_path }, Environment.get_current_dir (), out folder_path, out resolved_file_path);

            assert_null (folder_path);
            assert_cmpstr (resolved_file_path, CompareOperator.EQ, file_path);
        } catch (Error e) {
            error ("failed to create fixture file: %s", e.message);
        } finally {
            FileUtils.remove (file_path);
        }
    });

    Test.add_func ("/models/workspace/resolve/a_relative_argument_is_taken_from_the_directory_the_command_was_typed_in", () => {
        string dir_path = "";
        try {
            dir_path = DirUtils.make_tmp ("opus-workspace-test-XXXXXX");

            string? folder_path;
            string? file_path;
            Workspace.resolve ({ "opus", "." }, dir_path, out folder_path, out file_path);

            // Normalized the same way on both sides: the system's tmp dir may be a symlink.
            assert_cmpstr (folder_path, CompareOperator.EQ, File.new_for_path (dir_path).get_path ());
            assert_true (Path.is_absolute (folder_path));
        } catch (Error e) {
            error ("failed to create fixture directory: %s", e.message);
        } finally {
            DirUtils.remove (dir_path);
        }
    });

    Test.add_func ("/models/workspace/resolve/a_relative_file_is_taken_from_the_same_directory", () => {
        string dir_path = "";
        string file_path = "";
        try {
            dir_path = DirUtils.make_tmp ("opus-workspace-test-XXXXXX");
            file_path = Path.build_filename (dir_path, "notes.md");
            FileUtils.set_contents (file_path, "");

            string? folder_path;
            string? resolved_file_path;
            Workspace.resolve ({ "opus", "notes.md" }, dir_path, out folder_path, out resolved_file_path);

            assert_null (folder_path);
            assert_cmpstr (resolved_file_path, CompareOperator.EQ, File.new_for_path (file_path).get_path ());
        } catch (Error e) {
            error ("failed to create fixture: %s", e.message);
        } finally {
            FileUtils.remove (file_path);
            DirUtils.remove (dir_path);
        }
    });

    Test.add_func ("/models/workspace/resolve/the_processs_own_directory_plays_no_part", () => {
        // With an Opus already open, the command runs in that process,
        // started wherever: only the directory it was typed in counts.
        string typed_in = "";
        try {
            typed_in = DirUtils.make_tmp ("opus-workspace-test-XXXXXX");

            string? folder_path;
            string? file_path;
            Workspace.resolve ({ "opus", "." }, typed_in, out folder_path, out file_path);

            assert_cmpstr (folder_path, CompareOperator.NE, File.new_for_path (Environment.get_current_dir ()).get_path ());
            assert_cmpstr (folder_path, CompareOperator.EQ, File.new_for_path (typed_in).get_path ());
        } catch (Error e) {
            error ("failed to create fixture directory: %s", e.message);
        } finally {
            DirUtils.remove (typed_in);
        }
    });

    Test.add_func ("/models/workspace/resolve/no_argument_is_blank", () => {
        string? folder_path;
        string? file_path;
        Workspace.resolve ({ "opus" }, Environment.get_current_dir (), out folder_path, out file_path);

        assert_null (folder_path);
        assert_null (file_path);
    });

    return Test.run ();
}
