/**
 * The functions in the Command Bar's `>` list, end to end through the
 * real window, over the fixture packages in
 * tests/system/command-bar/functions/ (OPUS_FUNCTIONS_DIR): which
 * functions a file's language gets, and a script's output landing in
 * the text — the selection, or all of it.
 */

private const uint DISPLAY = 102;

private string write_file (string name, string text) throws Error {
    var folder = DirUtils.make_tmp ("opus-functions-test-XXXXXX");
    var path = Path.build_filename (folder, name);
    FileUtils.set_contents (path, text);
    return path;
}

/** The text once the function's edits have landed — they come back from a thread, one main-loop turn or more later. */
private string wait_for_text (SystemTestSession opus, string expected) throws Error {
    string text = "";
    for (int i = 0; i < 100; i++) {
        text = opus.active_text ();
        if (text == expected) {
            return text;
        }
        Thread.usleep (50000);
    }
    return text;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/functions/a_lua_file_lists_its_groups_functions_and_the_general_ones", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (write_file ("a.lua", "x = 1\n"));

            opus.open_commands ();

            assert_cmpstrv (opus.wait_for_command_bar_items (), { "set-language", "toggle-word-wrap", "reload-functions", "user-settings", "function:document:only-lua", "function:document:reindent", "function:document:shout", "function:document:trim-trailing-whitespace" });
            opus.close ();
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/system/functions/another_language_does_not_see_the_groups_functions", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (write_file ("a.rb", "x = 1\n"));

            opus.open_commands ();

            assert_cmpstrv (opus.wait_for_command_bar_items (), { "set-language", "toggle-word-wrap", "reload-functions", "user-settings", "function:document:reindent", "function:document:shout", "function:document:trim-trailing-whitespace" });
            opus.close ();
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/system/functions/a_function_rewrites_the_selection", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (write_file ("a.txt", "ação boa\n"));
            opus.set_cursor_offsets ({ 0 }, { 4 });

            opus.open_commands ();
            opus.command_bar_type (">selection shout");
            assert_cmpstrv (opus.wait_for_command_bar_items (), { "function:selection:shout" });
            opus.command_bar_accept ();

            assert_cmpstr (wait_for_text (opus, "AÇÃO! boa\n"), CompareOperator.EQ, "AÇÃO! boa\n");
            opus.close ();
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/system/functions/with_nothing_selected_a_function_rewrites_the_whole_text", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (write_file ("a.txt", "ação boa\n"));

            opus.open_commands ();
            opus.command_bar_type (">shout");
            assert_cmpstrv (opus.wait_for_command_bar_items (), { "function:document:shout" });
            opus.command_bar_accept ();

            assert_cmpstr (wait_for_text (opus, "AÇÃO BOA\n!"), CompareOperator.EQ, "AÇÃO BOA\n!");
            opus.close ();
        } catch (Error e) {
            error (e.message);
        }
    });

    return Test.run ();
}
