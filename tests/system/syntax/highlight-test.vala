/**
 * Syntax highlighting end to end through the real window: a file whose
 * language has a package is painted when it opens and repainted as it
 * is edited, a language embedded in it is painted as itself, and a file
 * nothing claims is left plain.
 */

private string write_fixture (string name, string contents) throws Error {
    var root_path = DirUtils.make_tmp ("opus-syntax-highlight-test-XXXXXX");
    var path = Path.build_filename (root_path, name);
    FileUtils.set_contents (path, contents);
    return path;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/syntax_highlight/a_file_is_painted_in_its_own_language_when_opened", () => {
        try {
            //                                            0123456789
            var path = write_fixture ("settings.json", "{\"a\": 12}");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 97);

            opus.open_tab (path);

            opus.wait_for_syntax_style (6, "constant.numeric");
            assert_cmpstr (opus.syntax_style_at (0), CompareOperator.EQ, "");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/syntax_highlight/typing_repaints_what_changed", () => {
        try {
            var path = write_fixture ("settings.json", "[true]");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 97);
            opus.open_tab (path);
            opus.wait_for_syntax_style (1, "constant.builtin");
            opus.set_cursor_offsets ({ 1 }, { 1 });

            opus.type ("1,");

            // `[1,true]`: the number is painted, and `true` kept its style three characters on.
            opus.wait_for_syntax_style (1, "constant.numeric");
            assert_cmpstr (opus.syntax_style_at (2), CompareOperator.EQ, "");
            assert_cmpstr (opus.syntax_style_at (3), CompareOperator.EQ, "constant.builtin");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/syntax_highlight/an_embedded_language_is_painted_as_itself", () => {
        try {
            //                                        0         1         2
            //                                        0123456789012345678901234567
            var path = write_fixture ("page.html", "<script>const n = 1;</script>");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 97);

            opus.open_tab (path);

            opus.wait_for_syntax_style (1, "tag");
            assert_cmpstr (opus.syntax_style_at (8), CompareOperator.EQ, "keyword.storage.modifier");
            assert_cmpstr (opus.syntax_style_at (18), CompareOperator.EQ, "constant.numeric");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/syntax_highlight/a_file_no_language_claims_stays_plain", () => {
        try {
            var path = write_fixture ("notes.txt", "{\"a\": 12}");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 97);

            opus.open_tab (path);

            opus.wait_for_active_tab (path);
            assert_cmpstr (opus.syntax_style_at (6), CompareOperator.EQ, "");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
