// Opus.Plugins.EditorConfig.Provider: FileSettings.Values from a real folder, and a cache the workspace's own changes empty.

private string make_tree () throws Error {
    var root = DirUtils.make_tmp ("opus-editorconfig-provider-test-XXXXXX");
    FileUtils.set_contents (Path.build_filename (root, ".editorconfig"), "root = true\n[*]\nindent_size = 2\nindent_style = space\nend_of_line = crlf\ntrim_trailing_whitespace = true\ninsert_final_newline = false\n");
    return root;
}

private void test_the_values_say_what_the_files_do () {
    try {
        var root = make_tree ();
        var provider = new Opus.Plugins.EditorConfig.Provider (new WorkspaceContext (root));
        provider.activate ();

        var values = provider.settings_for (Path.build_filename (root, "a.rb"));

        assert_true (values.indent_size == 2);
        assert_true (values.insert_spaces == true);
        assert_true (values.line_ending == Document.LineEnding.CRLF);
        assert_true (values.trim_trailing_whitespace == true);
        assert_true (values.insert_final_newline == false);
        provider.deactivate ();
        FileUtils.remove (Path.build_filename (root, ".editorconfig"));
        DirUtils.remove (root);
    } catch (Error e) {
        error (e.message);
    }
}

private void test_a_rewritten_editorconfig_counts_once_the_workspace_says_so () {
    try {
        var root = make_tree ();
        var context = new WorkspaceContext (root);
        var provider = new Opus.Plugins.EditorConfig.Provider (context);
        provider.activate ();
        var path = Path.build_filename (root, "a.rb");
        assert_true (provider.settings_for (path).indent_size == 2);
        FileUtils.set_contents (Path.build_filename (root, ".editorconfig"), "root = true\n[*]\nindent_size = 8\n");
        assert_true (provider.settings_for (path).indent_size == 2); // cached until told

        context.file_content_changed (Path.build_filename (root, ".editorconfig"));

        assert_true (provider.settings_for (path).indent_size == 8);
        provider.deactivate ();
        FileUtils.remove (Path.build_filename (root, ".editorconfig"));
        DirUtils.remove (root);
    } catch (Error e) {
        error (e.message);
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/plugins/editorconfig/provider/the_values_say_what_the_files_do", test_the_values_say_what_the_files_do);
    Test.add_func ("/plugins/editorconfig/provider/a_rewritten_editorconfig_counts_once_the_workspace_says_so", test_a_rewritten_editorconfig_counts_once_the_workspace_says_so);
    Test.run ();
}
