/**
 * Word wrap per language, end to end: a `language.markdown` block in
 * settings.json wraps Markdown tabs and leaves the others alone, and
 * Alt+W's own override wins over both.
 */

private const uint DISPLAY = 118;
private const string SETTINGS = """{ "editor.word_wrap": false, "language.markdown": { "editor.word_wrap": true } }""";

private string write_fixture (string name) throws Error {
    var root_path = DirUtils.make_tmp ("opus-word-wrap-test-XXXXXX");
    var path = Path.build_filename (root_path, name);
    FileUtils.set_contents (path, "one line\n");
    return path;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/word_wrap/a_language_block_wraps_its_own_files", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, null, SETTINGS);

            opus.open_tab (write_fixture ("a.md"));

            assert_true (opus.word_wrap ());
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/word_wrap/other_languages_keep_the_plain_key", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, null, SETTINGS);

            opus.open_tab (write_fixture ("a.rb"));

            assert_false (opus.word_wrap ());
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/word_wrap/the_toggle_wins_over_the_language_block", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, null, SETTINGS);
            opus.open_tab (write_fixture ("a.md"));
            opus.open_commands ();
            opus.command_bar_type (">toggle word wrap");

            opus.command_bar_accept ();

            assert_false (opus.word_wrap ());
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
