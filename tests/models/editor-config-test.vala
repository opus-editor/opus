private void test_no_editorconfig_file_loads_to_null () {
    string folder = Path.build_filename (Environment.get_tmp_dir (), "opus-editor-config-test-%u".printf (Random.next_int ()));
    DirUtils.create (folder, 0700);

    var config = EditorConfig.load (folder);

    assert_null (config);

    DirUtils.remove (folder);
}

private void test_global_section_applies_to_any_path () {
    var config = EditorConfig.parse ("""
[*]
indent_size = 2
""");

    assert_cmpint (config.indent_size_for ("main.vala"), CompareOperator.EQ, 2);
    assert_cmpint (config.indent_size_for ("src/models/document.vala"), CompareOperator.EQ, 2);
}

private void test_language_specific_section_overrides_the_global_one () {
    var config = EditorConfig.parse ("""
[*]
indent_size = 2

[*.py]
indent_size = 4
""");

    assert_cmpint (config.indent_size_for ("main.vala"), CompareOperator.EQ, 2);
    assert_cmpint (config.indent_size_for ("scripts/build.py"), CompareOperator.EQ, 4);
}

private void test_brace_alternation_matches_any_listed_extension () {
    var config = EditorConfig.parse ("""
[*.{js,ts}]
indent_size = 2
""");

    assert_cmpint (config.indent_size_for ("app.js"), CompareOperator.EQ, 2);
    assert_cmpint (config.indent_size_for ("app.ts"), CompareOperator.EQ, 2);
    assert_true (config.indent_size_for ("app.py") == null);
}

private void test_pattern_without_a_slash_matches_at_any_depth () {
    var config = EditorConfig.parse ("""
[Makefile]
indent_size = tab
tab_width = 8
""");

    assert_cmpint (config.indent_size_for ("Makefile"), CompareOperator.EQ, 8);
    assert_cmpint (config.indent_size_for ("vendor/lib/Makefile"), CompareOperator.EQ, 8);
}

private void test_indent_size_tab_falls_back_to_tab_width () {
    var config = EditorConfig.parse ("""
[*]
indent_style = tab
indent_size = tab
tab_width = 4
""");

    assert_cmpint (config.indent_size_for ("main.vala"), CompareOperator.EQ, 4);
}

private void test_indent_size_tab_without_tab_width_is_null () {
    var config = EditorConfig.parse ("""
[*]
indent_size = tab
""");

    assert_true (config.indent_size_for ("main.vala") == null);
}

private void test_no_matching_section_is_null () {
    var config = EditorConfig.parse ("""
[*.py]
indent_size = 4
""");

    assert_true (config.indent_size_for ("main.vala") == null);
}

private void test_later_section_wins_when_both_match_the_same_path () {
    var config = EditorConfig.parse ("""
[*.vala]
indent_size = 2

[*.vala]
indent_size = 4
""");

    assert_cmpint (config.indent_size_for ("main.vala"), CompareOperator.EQ, 4);
}

private void test_comments_and_blank_lines_are_ignored () {
    var config = EditorConfig.parse ("""
; a comment
root = true

# another comment
[*]
indent_size = 2
""");

    assert_cmpint (config.indent_size_for ("main.vala"), CompareOperator.EQ, 2);
}

private void test_indent_style_space_resolves_to_insert_spaces_true () {
    var config = EditorConfig.parse ("""
[*]
indent_style = space
""");

    assert_true (config.insert_spaces_for ("main.vala") == true);
}

private void test_indent_style_tab_resolves_to_insert_spaces_false () {
    var config = EditorConfig.parse ("""
[*]
indent_style = tab
""");

    assert_true (config.insert_spaces_for ("main.vala") == false);
}

private void test_indent_style_unset_resolves_to_null () {
    var config = EditorConfig.parse ("""
[*]
indent_size = 2
""");

    assert_true (config.insert_spaces_for ("main.vala") == null);
}

private void test_indent_style_language_override_wins_over_the_global_default () {
    var config = EditorConfig.parse ("""
[*]
indent_style = tab

[*.py]
indent_style = space
""");

    assert_true (config.insert_spaces_for ("main.vala") == false);
    assert_true (config.insert_spaces_for ("scripts/build.py") == true);
}

private void test_load_reads_indent_size_from_a_real_file () {
    string folder = Path.build_filename (Environment.get_tmp_dir (), "opus-editor-config-test-%u".printf (Random.next_int ()));
    DirUtils.create (folder, 0700);
    string path = Path.build_filename (folder, ".editorconfig");

    try {
        FileUtils.set_contents (path, "[*]\nindent_size = 3\n");

        var config = EditorConfig.load (folder);

        assert_nonnull (config);
        assert_cmpint (config.indent_size_for ("main.vala"), CompareOperator.EQ, 3);
    } catch (Error e) {
        error ("failed to create fixture file: %s", e.message);
    } finally {
        FileUtils.remove (path);
        DirUtils.remove (folder);
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/editor-config/no_editorconfig_file_loads_to_null", test_no_editorconfig_file_loads_to_null);
    Test.add_func ("/models/editor-config/global_section_applies_to_any_path", test_global_section_applies_to_any_path);
    Test.add_func ("/models/editor-config/language_specific_section_overrides_the_global_one", test_language_specific_section_overrides_the_global_one);
    Test.add_func ("/models/editor-config/brace_alternation_matches_any_listed_extension", test_brace_alternation_matches_any_listed_extension);
    Test.add_func ("/models/editor-config/pattern_without_a_slash_matches_at_any_depth", test_pattern_without_a_slash_matches_at_any_depth);
    Test.add_func ("/models/editor-config/indent_size_tab_falls_back_to_tab_width", test_indent_size_tab_falls_back_to_tab_width);
    Test.add_func ("/models/editor-config/indent_size_tab_without_tab_width_is_null", test_indent_size_tab_without_tab_width_is_null);
    Test.add_func ("/models/editor-config/no_matching_section_is_null", test_no_matching_section_is_null);
    Test.add_func ("/models/editor-config/later_section_wins_when_both_match_the_same_path", test_later_section_wins_when_both_match_the_same_path);
    Test.add_func ("/models/editor-config/comments_and_blank_lines_are_ignored", test_comments_and_blank_lines_are_ignored);
    Test.add_func ("/models/editor-config/indent_style_space_resolves_to_insert_spaces_true", test_indent_style_space_resolves_to_insert_spaces_true);
    Test.add_func ("/models/editor-config/indent_style_tab_resolves_to_insert_spaces_false", test_indent_style_tab_resolves_to_insert_spaces_false);
    Test.add_func ("/models/editor-config/indent_style_unset_resolves_to_null", test_indent_style_unset_resolves_to_null);
    Test.add_func ("/models/editor-config/indent_style_language_override_wins_over_the_global_default", test_indent_style_language_override_wins_over_the_global_default);
    Test.add_func ("/models/editor-config/load_reads_indent_size_from_a_real_file", test_load_reads_indent_size_from_a_real_file);
    return Test.run ();
}
