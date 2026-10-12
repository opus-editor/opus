/**
 * .editorconfig files up the tree, end to end: a subfolder's own file
 * has the last word over the root's, and `unset` hands a setting back
 * to the editor's default.
 */

private const uint DISPLAY = 121;

private string make_folder (string sub_editorconfig) throws Error {
    var folder = DirUtils.make_tmp ("opus-editorconfig-hierarchy-test-XXXXXX");
    FileUtils.set_contents (Path.build_filename (folder, ".editorconfig"), "root = true\n[*]\nindent_style = space\nindent_size = 2\n");
    DirUtils.create (Path.build_filename (folder, "sub"), 0700);
    FileUtils.set_contents (Path.build_filename (folder, "sub", ".editorconfig"), sub_editorconfig);
    FileUtils.set_contents (Path.build_filename (folder, "sub", "a.rb"), "def foo\n  bar\n");
    return folder;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/editorconfig_hierarchy/the_subfolders_file_has_the_last_word", () => {
        try {
            var folder = make_folder ("[*]\nindent_size = 4\n");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_tab (Path.build_filename (folder, "sub", "a.rb"));
            opus.set_cursors ({ {0, 7} }); // end of "def foo"

            opus.type_cmd ("enter");

            opus.assert_editor_text ("def foo\n    \n  bar\n");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/editorconfig_hierarchy/unset_hands_the_setting_back_to_the_editors_default", () => {
        try {
            var folder = make_folder ("[*]\nindent_size = unset\nindent_style = unset\n");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_tab (Path.build_filename (folder, "sub", "a.rb"));
            opus.set_cursors ({ {0, 7} });

            opus.type_cmd ("enter");

            opus.assert_editor_text ("def foo\n\t\n  bar\n");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/editorconfig_hierarchy/an_open_tab_follows_a_rewritten_editorconfig", () => {
        try {
            var folder = make_folder ("");
            var path = Path.build_filename (folder, "a.rb");
            FileUtils.set_contents (path, "def foo\n  bar\n");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_tab (path);
            opus.set_cursors ({ {0, 7} });
            opus.type_cmd ("enter");
            opus.assert_editor_text ("def foo\n  \n  bar\n");

            FileUtils.set_contents (Path.build_filename (folder, ".editorconfig"), "root = true\n[*]\nindent_style = space\nindent_size = 4\n");

            // The watcher reports in batches, a little after the write.
            string text = "";
            int64 deadline = get_monotonic_time () + 5 * 1000 * 1000;
            while (get_monotonic_time () < deadline) {
                opus.editor_write ("def foo\n  bar\n");
                opus.set_cursors ({ {0, 7} });
                opus.type_cmd ("enter");
                text = opus.active_text ();
                if (text == "def foo\n    \n  bar\n") {
                    break;
                }
                Thread.usleep (100 * 1000);
            }
            assert_cmpstr (text, CompareOperator.EQ, "def foo\n    \n  bar\n");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
