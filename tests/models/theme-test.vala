private Theme parse (string json) {
    try {
        return Theme.parse ("example", json);
    } catch (ThemeError e) {
        error ("the theme should have parsed: %s", e.message);
    }
}

private void test_a_theme_may_ask_for_its_own_editor_text_color () {
    var theme = parse ("""{ "palette": { "ink": "#504e55" }, "editor": { "foreground": "ink" }, "syntax": {} }""");

    assert_cmpstr (theme.editor_foreground, CompareOperator.EQ, "#504e55");
}

private void test_without_an_editor_block_the_text_color_is_the_windows () {
    var theme = parse ("""{ "syntax": {} }""");

    assert_null (theme.editor_foreground);
}

private void test_an_editor_foreground_that_is_not_a_color_is_invalid () {
    assert_invalid ("""{ "editor": { "foreground": "nope" }, "syntax": {} }""", "palette has no color");
    assert_invalid ("""{ "editor": { "foreground": "editor.foreground" }, "syntax": {} }""", "editor.foreground");
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

/** A theme folder `id` with one file serving both variants. */
private void write_theme (string directory, string id, string json) {
    try {
        var folder = Path.build_filename (directory, id);
        DirUtils.create_with_parents (folder, 0700);
        FileUtils.set_contents (Path.build_filename (folder, "theme.json"), """{ "name": "T", "light": "colors.json", "dark": "colors.json" }""");
        FileUtils.set_contents (Path.build_filename (folder, "colors.json"), json);
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

private void test_an_id_without_an_owner_is_not_a_theme () {
    string directory = new_themes_directory ();
    write_theme (directory, "o/paper", """{ "syntax": {} }""");

    try {
        Theme.load ({ directory }, "paper", false);
        assert_not_reached ();
    } catch (ThemeError e) {
        assert_true (e is ThemeError.NOT_FOUND);
        assert_true (e.message.contains ("owner/theme"));
    }
}

private void test_a_theme_without_the_variant_asked_for_is_not_found () {
    string directory = new_themes_directory ();
    var folder = Path.build_filename (directory, "o", "paper");
    DirUtils.create_with_parents (folder, 0700);
    try {
        FileUtils.set_contents (Path.build_filename (folder, "theme.json"), """{ "name": "Paper", "light": "light.json" }""");
        FileUtils.set_contents (Path.build_filename (folder, "light.json"), """{ "syntax": {} }""");
    } catch (FileError e) {
        error ("%s", e.message);
    }

    try {
        Theme.load ({ directory }, "o/paper", true);
        assert_not_reached ();
    } catch (ThemeError e) {
        assert_true (e is ThemeError.NOT_FOUND);
        assert_true (e.message.contains ("dark"));
    }
}

private void test_a_theme_is_loaded_by_name_from_a_directory () {
    string directory = new_themes_directory ();
    write_theme (directory, "o/github-light", """{ "syntax": { "keyword": { "foreground": "#d73a49" } } }""");

    Theme? theme = null;
    try {
        theme = Theme.load ({ directory }, "o/github-light", false);
    } catch (ThemeError e) {
        error ("%s", e.message);
    }

    assert_cmpstr (theme.name, CompareOperator.EQ, "o/github-light");
    assert_cmpstr (theme.style ("keyword").foreground, CompareOperator.EQ, "#d73a49");
}

private void test_a_later_directory_overrides_an_earlier_one () {
    string bundled = new_themes_directory ();
    string user = new_themes_directory ();
    write_theme (bundled, "o/github-light", """{ "syntax": { "keyword": { "foreground": "#d73a49" } } }""");
    write_theme (user, "o/github-light", """{ "syntax": { "keyword": { "foreground": "#cf222e" } } }""");

    Theme? theme = null;
    try {
        theme = Theme.load ({ bundled, user }, "o/github-light", false);
    } catch (ThemeError e) {
        error ("%s", e.message);
    }

    assert_cmpstr (theme.style ("keyword").foreground, CompareOperator.EQ, "#cf222e");
}

private void test_a_theme_no_directory_has_is_not_found () {
    string directory = new_themes_directory ();

    try {
        Theme.load ({ directory }, "o/github-light", false);
        assert_not_reached ();
    } catch (ThemeError e) {
        assert_true (e is ThemeError.NOT_FOUND);
    }
}

private void test_a_style_of_one_language_is_kept_under_that_languages_key () {
    var theme = parse ("""{ "languages": { "css": { "constant": { "foreground": "#d73a49", "bold": true } } } }""");

    var style = theme.style (Syntax.CaptureStyles.language_key ("css", "constant"));

    assert_cmpstr (style.foreground, CompareOperator.EQ, "#d73a49");
    assert_true (style.bold);
}

private void test_a_style_of_one_language_leaves_the_general_one_alone () {
    var theme = parse ("""{ "syntax": { "constant": { "foreground": "#005cc5" } }, "languages": { "css": { "constant": { "foreground": "#d73a49" } } } }""");

    var style = theme.style ("constant");

    assert_cmpstr (style.foreground, CompareOperator.EQ, "#005cc5");
}

private void test_a_style_of_one_language_is_not_a_general_style () {
    var theme = parse ("""{ "languages": { "css": { "constant": { "foreground": "#d73a49" } } } }""");

    assert_null (theme.style ("constant"));
}

private void test_the_styles_of_a_language_are_among_the_keys_the_theme_defines () {
    var theme = parse ("""{ "syntax": { "keyword": {} }, "languages": { "css": { "constant": {} }, "json": { "string": {} } } }""");

    var keys = theme.style_keys ();

    assert_cmpint (keys.length, CompareOperator.EQ, 3);
    assert_true (Syntax.CaptureStyles.language_key ("css", "constant") in keys);
    assert_true (Syntax.CaptureStyles.language_key ("json", "string") in keys);
}

private void test_a_theme_may_style_a_language_nothing_else_knows_of () {
    var theme = parse ("""{ "languages": { "klingon": { "keyword": { "foreground": "#d73a49" } } } }""");

    assert_nonnull (theme.style (Syntax.CaptureStyles.language_key ("klingon", "keyword")));
}

private void test_a_language_with_dots_in_its_name_can_be_styled () {
    var theme = parse ("""{ "languages": { "markdown.inline": { "markup.bold": { "bold": true } } } }""");

    assert_true (theme.style (Syntax.CaptureStyles.language_key ("markdown.inline", "markup.bold")).bold);
}

private void test_languages_that_is_not_an_object_is_invalid () {
    assert_invalid ("""{ "languages": [] }""", "\"languages\" must be an object");
}

private void test_a_language_that_is_not_an_object_is_invalid () {
    assert_invalid ("""{ "languages": { "css": "red" } }""", "languages.css must be an object");
}

private void test_a_language_style_that_is_not_an_object_is_invalid () {
    assert_invalid ("""{ "languages": { "css": { "constant": "red" } } }""", "languages.css.constant must be an object");
}

private void test_a_bad_color_in_a_language_style_says_where_it_is () {
    assert_invalid ("""{ "languages": { "css": { "constant": { "foreground": "red" } } } }""", "languages.css.constant.foreground");
}

private void test_a_language_name_that_would_read_two_ways_is_invalid () {
    assert_invalid ("""{ "languages": { "a:b": { "constant": {} } } }""", "can't be a language's name");
}

private void test_a_style_may_name_a_color_of_the_palette () {
    var theme = parse ("""{ "palette": { "blue": "#005cc5" }, "syntax": { "constant": { "foreground": "blue" } } }""");

    assert_cmpstr (theme.style ("constant").foreground, CompareOperator.EQ, "#005cc5");
}

private void test_a_background_may_name_a_color_of_the_palette () {
    var theme = parse ("""{ "palette": { "wash": "#f0fff4" }, "syntax": { "diff.plus": { "background": "wash" } } }""");

    assert_cmpstr (theme.style ("diff.plus").background, CompareOperator.EQ, "#f0fff4");
}

private void test_a_style_of_one_language_may_name_a_color_of_the_palette () {
    var theme = parse ("""{ "palette": { "red": "#d73a49" }, "languages": { "css": { "constant": { "foreground": "red" } } } }""");

    var style = theme.style (Syntax.CaptureStyles.language_key ("css", "constant"));

    assert_cmpstr (style.foreground, CompareOperator.EQ, "#d73a49");
}

private void test_a_color_spelled_out_still_works_next_to_a_palette () {
    var theme = parse ("""{ "palette": { "blue": "#005cc5" }, "syntax": { "constant": { "foreground": "#22863a" } } }""");

    assert_cmpstr (theme.style ("constant").foreground, CompareOperator.EQ, "#22863a");
}

private void test_the_palette_may_come_after_the_styles_that_use_it () {
    var theme = parse ("""{ "syntax": { "constant": { "foreground": "blue" } }, "palette": { "blue": "#005cc5" } }""");

    assert_cmpstr (theme.style ("constant").foreground, CompareOperator.EQ, "#005cc5");
}

private void test_a_palette_name_may_have_dots_and_dashes () {
    var theme = parse ("""{ "palette": { "scale.red-5": "#d73a49" }, "syntax": { "keyword": { "foreground": "scale.red-5" } } }""");

    assert_cmpstr (theme.style ("keyword").foreground, CompareOperator.EQ, "#d73a49");
}

private void test_the_names_of_the_palette_are_not_styles () {
    var theme = parse ("""{ "palette": { "blue": "#005cc5" } }""");

    assert_cmpint (theme.style_keys ().length, CompareOperator.EQ, 0);
    assert_null (theme.style ("blue"));
}

private void test_a_color_name_the_palette_lacks_is_invalid_and_says_where () {
    assert_invalid ("""{ "palette": { "blue": "#005cc5" }, "syntax": { "constant": { "foreground": "blu" } } }""", "syntax.constant.foreground: the palette has no color named \"blu\"");
}

private void test_a_color_name_with_no_palette_at_all_is_invalid () {
    assert_invalid ("""{ "syntax": { "constant": { "foreground": "blue" } } }""", "the palette has no color named \"blue\"");
}

private void test_there_are_no_colors_named_by_default () {
    assert_invalid ("""{ "syntax": { "constant": { "foreground": "red" } } }""", "the palette has no color named \"red\"");
    assert_invalid ("""{ "syntax": { "constant": { "foreground": "white" } } }""", "the palette has no color named \"white\"");
}

private void test_a_palette_color_must_be_spelled_out () {
    assert_invalid ("""{ "palette": { "blue": "navy", "navy": "#032f62" } }""", "palette.blue must be a color");
}

private void test_a_malformed_palette_color_is_invalid () {
    assert_invalid ("""{ "palette": { "blue": "#05c" } }""", "palette.blue must be a color");
}

private void test_a_palette_that_is_not_an_object_is_invalid () {
    assert_invalid ("""{ "palette": ["#005cc5"] }""", "\"palette\" must be an object");
}

private void test_a_palette_name_that_reads_as_a_color_is_invalid () {
    assert_invalid ("""{ "palette": { "#fff": "#ffffff" } }""", "can't be a color's name");
}

private void test_a_malformed_color_spelled_out_is_still_invalid () {
    assert_invalid ("""{ "palette": { "blue": "#005cc5" }, "syntax": { "constant": { "foreground": "#05c" } } }""", "syntax.constant.foreground must be a color");
}

private void test_a_style_may_take_the_editors_own_text_color () {
    var theme = parse ("""{ "syntax": { "variable": { "foreground": "editor.foreground" } } }""");

    var style = theme.style ("variable");

    assert_nonnull (style);
    assert_null (style.foreground);
}

private void test_a_style_taking_the_editors_own_text_color_is_a_key_the_theme_defines () {
    var theme = parse ("""{ "syntax": { "variable": { "foreground": "editor.foreground" } } }""");

    assert_true ("variable" in theme.style_keys ());
}

private void test_a_style_may_take_the_editors_own_background () {
    var theme = parse ("""{ "syntax": { "diff.plus": { "foreground": "#22863a", "background": "editor.background" } } }""");

    var style = theme.style ("diff.plus");

    assert_cmpstr (style.foreground, CompareOperator.EQ, "#22863a");
    assert_null (style.background);
}

private void test_the_editors_own_colors_need_no_palette () {
    var theme = parse ("""{ "syntax": { "variable": { "foreground": "editor.foreground" } } }""");

    assert_nonnull (theme.style ("variable"));
}

private void test_a_palette_color_named_like_the_editors_own_wins () {
    var theme = parse ("""{ "palette": { "editor.foreground": "#24292e" }, "syntax": { "variable": { "foreground": "editor.foreground" } } }""");

    assert_cmpstr (theme.style ("variable").foreground, CompareOperator.EQ, "#24292e");
}

private void test_the_editors_own_background_is_not_a_text_color () {
    assert_invalid ("""{ "syntax": { "variable": { "foreground": "editor.background" } } }""", "syntax.variable.foreground: \"editor.background\" is the editor's own background");
}

private void test_the_editors_own_text_color_is_not_a_background () {
    assert_invalid ("""{ "syntax": { "variable": { "background": "editor.foreground" } } }""", "syntax.variable.background: \"editor.foreground\" is the editor's own text color");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/theme/a_theme_may_ask_for_its_own_editor_text_color", test_a_theme_may_ask_for_its_own_editor_text_color);
    Test.add_func ("/models/theme/without_an_editor_block_the_text_color_is_the_windows", test_without_an_editor_block_the_text_color_is_the_windows);
    Test.add_func ("/models/theme/an_editor_foreground_that_is_not_a_color_is_invalid", test_an_editor_foreground_that_is_not_a_color_is_invalid);
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
    Test.add_func ("/models/theme/an_id_without_an_owner_is_not_a_theme", test_an_id_without_an_owner_is_not_a_theme);
    Test.add_func ("/models/theme/a_theme_without_the_variant_asked_for_is_not_found", test_a_theme_without_the_variant_asked_for_is_not_found);
    Test.add_func ("/models/theme/a_theme_is_loaded_by_name_from_a_directory", test_a_theme_is_loaded_by_name_from_a_directory);
    Test.add_func ("/models/theme/a_later_directory_overrides_an_earlier_one", test_a_later_directory_overrides_an_earlier_one);
    Test.add_func ("/models/theme/a_theme_no_directory_has_is_not_found", test_a_theme_no_directory_has_is_not_found);
    Test.add_func ("/models/theme/a_style_of_one_language_is_kept_under_that_languages_key", test_a_style_of_one_language_is_kept_under_that_languages_key);
    Test.add_func ("/models/theme/a_style_of_one_language_leaves_the_general_one_alone", test_a_style_of_one_language_leaves_the_general_one_alone);
    Test.add_func ("/models/theme/a_style_of_one_language_is_not_a_general_style", test_a_style_of_one_language_is_not_a_general_style);
    Test.add_func ("/models/theme/the_styles_of_a_language_are_among_the_keys_the_theme_defines", test_the_styles_of_a_language_are_among_the_keys_the_theme_defines);
    Test.add_func ("/models/theme/a_theme_may_style_a_language_nothing_else_knows_of", test_a_theme_may_style_a_language_nothing_else_knows_of);
    Test.add_func ("/models/theme/a_language_with_dots_in_its_name_can_be_styled", test_a_language_with_dots_in_its_name_can_be_styled);
    Test.add_func ("/models/theme/languages_that_is_not_an_object_is_invalid", test_languages_that_is_not_an_object_is_invalid);
    Test.add_func ("/models/theme/a_language_that_is_not_an_object_is_invalid", test_a_language_that_is_not_an_object_is_invalid);
    Test.add_func ("/models/theme/a_language_style_that_is_not_an_object_is_invalid", test_a_language_style_that_is_not_an_object_is_invalid);
    Test.add_func ("/models/theme/a_bad_color_in_a_language_style_says_where_it_is", test_a_bad_color_in_a_language_style_says_where_it_is);
    Test.add_func ("/models/theme/a_language_name_that_would_read_two_ways_is_invalid", test_a_language_name_that_would_read_two_ways_is_invalid);
    Test.add_func ("/models/theme/a_style_may_name_a_color_of_the_palette", test_a_style_may_name_a_color_of_the_palette);
    Test.add_func ("/models/theme/a_background_may_name_a_color_of_the_palette", test_a_background_may_name_a_color_of_the_palette);
    Test.add_func ("/models/theme/a_style_of_one_language_may_name_a_color_of_the_palette", test_a_style_of_one_language_may_name_a_color_of_the_palette);
    Test.add_func ("/models/theme/a_color_spelled_out_still_works_next_to_a_palette", test_a_color_spelled_out_still_works_next_to_a_palette);
    Test.add_func ("/models/theme/the_palette_may_come_after_the_styles_that_use_it", test_the_palette_may_come_after_the_styles_that_use_it);
    Test.add_func ("/models/theme/a_palette_name_may_have_dots_and_dashes", test_a_palette_name_may_have_dots_and_dashes);
    Test.add_func ("/models/theme/the_names_of_the_palette_are_not_styles", test_the_names_of_the_palette_are_not_styles);
    Test.add_func ("/models/theme/a_color_name_the_palette_lacks_is_invalid_and_says_where", test_a_color_name_the_palette_lacks_is_invalid_and_says_where);
    Test.add_func ("/models/theme/a_color_name_with_no_palette_at_all_is_invalid", test_a_color_name_with_no_palette_at_all_is_invalid);
    Test.add_func ("/models/theme/there_are_no_colors_named_by_default", test_there_are_no_colors_named_by_default);
    Test.add_func ("/models/theme/a_palette_color_must_be_spelled_out", test_a_palette_color_must_be_spelled_out);
    Test.add_func ("/models/theme/a_malformed_palette_color_is_invalid", test_a_malformed_palette_color_is_invalid);
    Test.add_func ("/models/theme/a_palette_that_is_not_an_object_is_invalid", test_a_palette_that_is_not_an_object_is_invalid);
    Test.add_func ("/models/theme/a_palette_name_that_reads_as_a_color_is_invalid", test_a_palette_name_that_reads_as_a_color_is_invalid);
    Test.add_func ("/models/theme/a_malformed_color_spelled_out_is_still_invalid", test_a_malformed_color_spelled_out_is_still_invalid);
    Test.add_func ("/models/theme/a_style_may_take_the_editors_own_text_color", test_a_style_may_take_the_editors_own_text_color);
    Test.add_func ("/models/theme/a_style_taking_the_editors_own_text_color_is_a_key_the_theme_defines", test_a_style_taking_the_editors_own_text_color_is_a_key_the_theme_defines);
    Test.add_func ("/models/theme/a_style_may_take_the_editors_own_background", test_a_style_may_take_the_editors_own_background);
    Test.add_func ("/models/theme/the_editors_own_colors_need_no_palette", test_the_editors_own_colors_need_no_palette);
    Test.add_func ("/models/theme/a_palette_color_named_like_the_editors_own_wins", test_a_palette_color_named_like_the_editors_own_wins);
    Test.add_func ("/models/theme/the_editors_own_background_is_not_a_text_color", test_the_editors_own_background_is_not_a_text_color);
    Test.add_func ("/models/theme/the_editors_own_text_color_is_not_a_background", test_the_editors_own_text_color_is_not_a_background);
    Test.run ();
}
