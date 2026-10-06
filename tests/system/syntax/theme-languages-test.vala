/**
 * A theme's styles for one language, end to end through the real
 * window: with tests/fixtures/themes/by-language.json on, the same
 * capture is painted one way in the languages the theme singles out
 * and the general way everywhere else.
 */

private const uint DISPLAY = 110;
private const string SETTINGS = """{ "editor.theme_light": "by-language", "editor.theme_dark": "by-language" }""";

private string write_fixture (string name, string contents) throws Error {
    var root_path = DirUtils.make_tmp ("opus-theme-languages-test-XXXXXX");
    var path = Path.build_filename (root_path, name);
    FileUtils.set_contents (path, contents);
    return path;
}

private SystemTestSession opus_showing (string name, string contents) throws Error {
    var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, null, SETTINGS);
    opus.open_tab (write_fixture (name, contents));
    return opus;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/theme_languages/a_language_the_theme_singles_out_is_painted_its_own_way", () => {
        try {
            //                                      0123456
            var opus = opus_showing ("a.json", "{\"a\": 12}");

            opus.wait_for_syntax_style (6, "json:constant");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/theme_languages/another_language_is_painted_the_general_way", () => {
        try {
            //                                 01234
            var opus = opus_showing ("a.toml", "a = 12\n");

            opus.wait_for_syntax_style (4, "constant.numeric");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/theme_languages/embedded_code_is_painted_as_its_own_language", () => {
        try {
            //                                 0123456789012345678901
            var opus = opus_showing ("a.html", "<style>a { color: red; }</style>");

            opus.wait_for_syntax_style (18, "css:constant");
            assert_cmpstr (opus.syntax_style_at (1), CompareOperator.EQ, "tag");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
