private Theme parse (string json) {
    try {
        return Theme.parse ("example", json);
    } catch (ThemeError e) {
        error ("the theme should have parsed: %s", e.message);
    }
}

private void assert_invalid (string json, string message_part) {
    try {
        Theme.parse ("example", json);
        assert_not_reached ();
    } catch (ThemeError e) {
        assert_true (e is ThemeError.INVALID);
        assert_true (e.message.contains (message_part));
    }
}

private string new_themes_directory () {
    string directory = Path.build_filename (Environment.get_tmp_dir (), "opus-theme-test-%u".printf (Random.next_int ()));
    DirUtils.create_with_parents (directory, 0700);
    return directory;
}

private void write_theme (string directory, string name, string json) {
    try {
        FileUtils.set_contents (Path.build_filename (directory, name + ".json"), json);
    } catch (FileError e) {
        error ("%s", e.message);
    }
}

private void test_a_theme_is_named_after_its_file () {
    var theme = parse ("{}");

    assert_cmpstr (theme.name, CompareOperator.EQ, "example");
}

private void test_a_syntax_style_carries_its_colors () {
    var theme = parse ("""{ "syntax": { "diff.plus": { "foreground": "#22863a", "background": "#f0fff4" } } }""");

    var style = theme.style ("diff.plus");

    assert_cmpstr (style.foreground, CompareOperator.EQ, "#22863a");
    assert_cmpstr (style.background, CompareOperator.EQ, "#f0fff4");
}

private void test_a_syntax_style_carries_its_font_flags () {
    var theme = parse ("""{ "syntax": { "markup.heading": { "bold": true, "italic": true, "underline": true, "strikethrough": true } } }""");

    var style = theme.style ("markup.heading");

    assert_true (style.bold);
    assert_true (style.italic);
    assert_true (style.underline);
    assert_true (style.strikethrough);
}

private void test_what_a_syntax_style_leaves_out_is_unset () {
    var theme = parse ("""{ "syntax": { "keyword": { "foreground": "#d73a49" } } }""");

    var style = theme.style ("keyword");

    assert_null (style.background);
    assert_false (style.bold);
    assert_false (style.italic);
}

private void test_a_syntax_key_the_theme_leaves_out_has_no_style () {
    var theme = parse ("""{ "syntax": { "keyword": { "foreground": "#d73a49" } } }""");

    assert_null (theme.style ("string"));
}

private void test_style_keys_lists_every_syntax_key () {
    var theme = parse ("""{ "syntax": { "keyword": { "bold": true }, "string": { "italic": true } } }""");

    var keys = theme.style_keys ();

    assert_cmpuint (keys.length, CompareOperator.EQ, 2);
    assert_true ("keyword" in keys);
    assert_true ("string" in keys);
}

private void test_an_empty_theme_styles_nothing () {
    var theme = new Theme.empty ();

    assert_cmpuint (theme.style_keys ().length, CompareOperator.EQ, 0);
}

private void test_malformed_json_is_invalid () {
    assert_invalid ("""{ "syntax": """, "JSON");
}

private void test_a_theme_that_is_not_an_object_is_invalid () {
    assert_invalid ("""["github"]""", "object");
}

private void test_a_color_in_another_notation_is_invalid () {
    assert_invalid ("""{ "syntax": { "keyword": { "background": "white" } } }""", "syntax.keyword.background");
}

private void test_a_shorthand_color_is_invalid () {
    assert_invalid ("""{ "syntax": { "keyword": { "foreground": "#fff" } } }""", "syntax.keyword.foreground");
}

private void test_a_font_flag_that_is_not_a_boolean_is_invalid () {
    assert_invalid ("""{ "syntax": { "keyword": { "bold": "yes" } } }""", "syntax.keyword.bold");
}

private void test_a_syntax_entry_that_is_not_an_object_is_invalid () {
    assert_invalid ("""{ "syntax": { "keyword": "#d73a49" } }""", "syntax.keyword");
}

private void test_a_theme_is_loaded_by_name_from_a_directory () {
    string directory = new_themes_directory ();
    write_theme (directory, "github-light", """{ "syntax": { "keyword": { "foreground": "#d73a49" } } }""");

    Theme? theme = null;
    try {
        theme = Theme.load ({ directory }, "github-light");
    } catch (ThemeError e) {
        error ("%s", e.message);
    }

    assert_cmpstr (theme.name, CompareOperator.EQ, "github-light");
    assert_cmpstr (theme.style ("keyword").foreground, CompareOperator.EQ, "#d73a49");
}

private void test_a_later_directory_overrides_an_earlier_one () {
    string bundled = new_themes_directory ();
    string user = new_themes_directory ();
    write_theme (bundled, "github-light", """{ "syntax": { "keyword": { "foreground": "#d73a49" } } }""");
    write_theme (user, "github-light", """{ "syntax": { "keyword": { "foreground": "#cf222e" } } }""");

    Theme? theme = null;
    try {
        theme = Theme.load ({ bundled, user }, "github-light");
    } catch (ThemeError e) {
        error ("%s", e.message);
    }

    assert_cmpstr (theme.style ("keyword").foreground, CompareOperator.EQ, "#cf222e");
}

private void test_a_theme_no_directory_has_is_not_found () {
    string directory = new_themes_directory ();

    try {
        Theme.load ({ directory }, "github-light");
        assert_not_reached ();
    } catch (ThemeError e) {
        assert_true (e is ThemeError.NOT_FOUND);
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/theme/a_theme_is_named_after_its_file", test_a_theme_is_named_after_its_file);
    Test.add_func ("/models/theme/a_syntax_style_carries_its_colors", test_a_syntax_style_carries_its_colors);
    Test.add_func ("/models/theme/a_syntax_style_carries_its_font_flags", test_a_syntax_style_carries_its_font_flags);
    Test.add_func ("/models/theme/what_a_syntax_style_leaves_out_is_unset", test_what_a_syntax_style_leaves_out_is_unset);
    Test.add_func ("/models/theme/a_syntax_key_the_theme_leaves_out_has_no_style", test_a_syntax_key_the_theme_leaves_out_has_no_style);
    Test.add_func ("/models/theme/style_keys_lists_every_syntax_key", test_style_keys_lists_every_syntax_key);
    Test.add_func ("/models/theme/an_empty_theme_styles_nothing", test_an_empty_theme_styles_nothing);
    Test.add_func ("/models/theme/malformed_json_is_invalid", test_malformed_json_is_invalid);
    Test.add_func ("/models/theme/a_theme_that_is_not_an_object_is_invalid", test_a_theme_that_is_not_an_object_is_invalid);
    Test.add_func ("/models/theme/a_color_in_another_notation_is_invalid", test_a_color_in_another_notation_is_invalid);
    Test.add_func ("/models/theme/a_shorthand_color_is_invalid", test_a_shorthand_color_is_invalid);
    Test.add_func ("/models/theme/a_font_flag_that_is_not_a_boolean_is_invalid", test_a_font_flag_that_is_not_a_boolean_is_invalid);
    Test.add_func ("/models/theme/a_syntax_entry_that_is_not_an_object_is_invalid", test_a_syntax_entry_that_is_not_an_object_is_invalid);
    Test.add_func ("/models/theme/a_theme_is_loaded_by_name_from_a_directory", test_a_theme_is_loaded_by_name_from_a_directory);
    Test.add_func ("/models/theme/a_later_directory_overrides_an_earlier_one", test_a_later_directory_overrides_an_earlier_one);
    Test.add_func ("/models/theme/a_theme_no_directory_has_is_not_found", test_a_theme_no_directory_has_is_not_found);
    Test.run ();
}
