// Opus.Plugins.EditorConfig.Commands: "Generate .editorconfig" writes the template at the root, once.

private void test_generate_writes_the_template_and_asks_to_open_it () {
    try {
        var root = DirUtils.make_tmp ("opus-editorconfig-commands-test-XXXXXX");
        var commands = new Opus.Plugins.EditorConfig.Commands (new WorkspaceContext (root));
        string? opened = null;
        commands.open_file_requested.connect ((path) => opened = path);

        commands.run (Opus.Plugins.EditorConfig.Commands.GENERATE);

        string written;
        FileUtils.get_contents (Path.build_filename (root, ".editorconfig"), out written);
        assert_cmpstr (written, CompareOperator.EQ, Opus.Plugins.EditorConfig.Commands.TEMPLATE);
        assert_cmpstr (opened, CompareOperator.EQ, Path.build_filename (root, ".editorconfig"));
        FileUtils.remove (Path.build_filename (root, ".editorconfig"));
        DirUtils.remove (root);
    } catch (Error e) {
        error (e.message);
    }
}

private void test_generate_refuses_to_replace_an_existing_file () {
    try {
        var root = DirUtils.make_tmp ("opus-editorconfig-commands-test-XXXXXX");
        FileUtils.set_contents (Path.build_filename (root, ".editorconfig"), "[*]\nindent_size = 8\n");
        var commands = new Opus.Plugins.EditorConfig.Commands (new WorkspaceContext (root));

        bool refused = false;
        try {
            commands.run (Opus.Plugins.EditorConfig.Commands.GENERATE);
        } catch (Error e) {
            refused = e is IOError.EXISTS;
        }

        assert_true (refused);
        string kept;
        FileUtils.get_contents (Path.build_filename (root, ".editorconfig"), out kept);
        assert_cmpstr (kept, CompareOperator.EQ, "[*]\nindent_size = 8\n");
        FileUtils.remove (Path.build_filename (root, ".editorconfig"));
        DirUtils.remove (root);
    } catch (Error e) {
        error (e.message);
    }
}

private void test_the_one_command_is_listed_under_the_plugins_name () {
    var commands = new Opus.Plugins.EditorConfig.Commands (new WorkspaceContext ("/r"));

    var listed = commands.commands ();

    assert_cmpstr (commands.name, CompareOperator.EQ, "EditorConfig");
    assert_cmpint (listed.length, CompareOperator.EQ, 1);
    assert_cmpstr (listed[0].id, CompareOperator.EQ, "generate");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/plugins/editorconfig/commands/generate_writes_the_template_and_asks_to_open_it", test_generate_writes_the_template_and_asks_to_open_it);
    Test.add_func ("/plugins/editorconfig/commands/generate_refuses_to_replace_an_existing_file", test_generate_refuses_to_replace_an_existing_file);
    Test.add_func ("/plugins/editorconfig/commands/the_one_command_is_listed_under_the_plugins_name", test_the_one_command_is_listed_under_the_plugins_name);
    Test.run ();
}
