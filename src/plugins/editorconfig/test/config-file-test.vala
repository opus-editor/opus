// Opus.Plugins.EditorConfig.ConfigFile: one parsed .editorconfig, its sections resolved for a file under its directory.

private const string ROOT = "/r";

private Opus.Plugins.EditorConfig.ConfigFile parsed (string contents) {
    return Opus.Plugins.EditorConfig.ConfigFile.parse (contents, ROOT);
}

private GenericArray<Opus.Plugins.EditorConfig.ConfigFile> one (Opus.Plugins.EditorConfig.ConfigFile file) {
    var files = new GenericArray<Opus.Plugins.EditorConfig.ConfigFile> ();
    files.add (file);
    return files;
}

/** The properties `relative` (under ROOT) gets from `file` alone. */
private Opus.Plugins.EditorConfig.Resolved resolved (Opus.Plugins.EditorConfig.ConfigFile file, string relative) {
    return new Opus.Plugins.EditorConfig.Hierarchy (one (file)).resolve (Path.build_filename (ROOT, relative));
}

private void test_root_true_in_the_preamble_is_read_and_a_property_there_is_not () {
    var file = parsed ("""
root = true
indent_size = 9
[*]
indent_size = 2
""");

    assert_true (file.is_root);
    assert_cmpint ((int) resolved (file, "main.vala").indent_size (), CompareOperator.EQ, 2);
}

private void test_a_file_outside_the_configs_directory_matches_nothing () {
    var file = parsed ("""
[*]
indent_size = 2
""");

    assert_true (new Opus.Plugins.EditorConfig.Hierarchy (one (file)).resolve ("/elsewhere/main.vala").indent_size () == null);
}

private void test_no_editorconfig_file_loads_to_null () {
    string folder = Path.build_filename (Environment.get_tmp_dir (), "opus-editor-config-test-%u".printf (Random.next_int ()));
    DirUtils.create (folder, 0700);

    var config = Opus.Plugins.EditorConfig.ConfigFile.in_directory (folder);

    assert_null (config);

    DirUtils.remove (folder);
}

private void test_global_section_applies_to_any_path () {
    var config = parsed ("""
[*]
indent_size = 2
""");

    assert_cmpint ((int) resolved (config, "main.vala").indent_size (), CompareOperator.EQ, 2);
    assert_cmpint ((int) resolved (config, "src/models/document.vala").indent_size (), CompareOperator.EQ, 2);
}

private void test_language_specific_section_overrides_the_global_one () {
    var config = parsed ("""
[*]
indent_size = 2

[*.py]
indent_size = 4
""");

    assert_cmpint ((int) resolved (config, "main.vala").indent_size (), CompareOperator.EQ, 2);
    assert_cmpint ((int) resolved (config, "scripts/build.py").indent_size (), CompareOperator.EQ, 4);
}

private void test_brace_alternation_matches_any_listed_extension () {
    var config = parsed ("""
[*.{js,ts}]
indent_size = 2
""");

    assert_cmpint ((int) resolved (config, "app.js").indent_size (), CompareOperator.EQ, 2);
    assert_cmpint ((int) resolved (config, "app.ts").indent_size (), CompareOperator.EQ, 2);
    assert_true (resolved (config, "app.py").indent_size () == null);
}

private void test_pattern_without_a_slash_matches_at_any_depth () {
    var config = parsed ("""
[Makefile]
indent_size = tab
tab_width = 8
""");

    assert_cmpint ((int) resolved (config, "Makefile").indent_size (), CompareOperator.EQ, 8);
    assert_cmpint ((int) resolved (config, "vendor/lib/Makefile").indent_size (), CompareOperator.EQ, 8);
}

private void test_indent_size_tab_falls_back_to_tab_width () {
    var config = parsed ("""
[*]
indent_style = tab
indent_size = tab
tab_width = 4
""");

    assert_cmpint ((int) resolved (config, "main.vala").indent_size (), CompareOperator.EQ, 4);
}

private void test_indent_size_tab_without_tab_width_is_null () {
    var config = parsed ("""
[*]
indent_size = tab
""");

    assert_true (resolved (config, "main.vala").indent_size () == null);
}

private void test_no_matching_section_is_null () {
    var config = parsed ("""
[*.py]
indent_size = 4
""");

    assert_true (resolved (config, "main.vala").indent_size () == null);
}

private void test_later_section_wins_when_both_match_the_same_path () {
    var config = parsed ("""
[*.vala]
indent_size = 2

[*.vala]
indent_size = 4
""");

    assert_cmpint ((int) resolved (config, "main.vala").indent_size (), CompareOperator.EQ, 4);
}

private void test_comments_and_blank_lines_are_ignored () {
    var config = parsed ("""
; a comment
root = true

# another comment
[*]
indent_size = 2
""");

    assert_cmpint ((int) resolved (config, "main.vala").indent_size (), CompareOperator.EQ, 2);
}

private void test_the_save_switches_resolve_true_false_and_unset () {
    var config = parsed ("""
[*]
trim_trailing_whitespace = true
[*.md]
trim_trailing_whitespace = false
insert_final_newline = true
""");

    assert_true (resolved (config, "main.vala").trim_trailing_whitespace () == true);
    assert_true (resolved (config, "notes.md").trim_trailing_whitespace () == false);
    assert_true (resolved (config, "notes.md").insert_final_newline () == true);
    assert_true (resolved (config, "main.vala").insert_final_newline () == null);
}

private void test_end_of_line_resolves_lf_and_crlf () {
    var config = parsed ("""
[*]
end_of_line = lf
[*.bat]
end_of_line = crlf
""");

    assert_true (resolved (config, "main.vala").end_of_line () == Document.LineEnding.LF);
    assert_true (resolved (config, "run.bat").end_of_line () == Document.LineEnding.CRLF);
}

private void test_end_of_line_unset_or_unsupported_is_null () {
    var config = parsed ("""
[*.txt]
end_of_line = cr
""");

    assert_true (resolved (config, "main.vala").end_of_line () == null);
    assert_true (resolved (config, "notes.txt").end_of_line () == null);
}

private void test_indent_style_space_resolves_to_insert_spaces_true () {
    var config = parsed ("""
[*]
indent_style = space
""");

    assert_true (resolved (config, "main.vala").insert_spaces () == true);
}

private void test_indent_style_tab_resolves_to_insert_spaces_false () {
    var config = parsed ("""
[*]
indent_style = tab
""");

    assert_true (resolved (config, "main.vala").insert_spaces () == false);
}

private void test_indent_style_unset_resolves_to_null () {
    var config = parsed ("""
[*]
indent_size = 2
""");

    assert_true (resolved (config, "main.vala").insert_spaces () == null);
}

private void test_indent_style_language_override_wins_over_the_global_default () {
    var config = parsed ("""
[*]
indent_style = tab

[*.py]
indent_style = space
""");

    assert_true (resolved (config, "main.vala").insert_spaces () == false);
    assert_true (resolved (config, "scripts/build.py").insert_spaces () == true);
}

private void test_load_reads_indent_size_from_a_real_file () {
    string folder = Path.build_filename (Environment.get_tmp_dir (), "opus-editor-config-test-%u".printf (Random.next_int ()));
    DirUtils.create (folder, 0700);
    string path = Path.build_filename (folder, ".editorconfig");

    try {
        FileUtils.set_contents (path, "[*]\nindent_size = 3\n");

        var config = Opus.Plugins.EditorConfig.ConfigFile.in_directory (folder);

        assert_nonnull (config);
        assert_cmpint (new Opus.Plugins.EditorConfig.Hierarchy (one (config)).resolve (Path.build_filename (folder, "main.vala")).indent_size (), CompareOperator.EQ, 3);
    } catch (Error e) {
        error ("failed to create fixture file: %s", e.message);
    } finally {
        FileUtils.remove (path);
        DirUtils.remove (folder);
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/plugins/editorconfig/config-file/root_true_in_the_preamble_is_read_and_a_property_there_is_not", test_root_true_in_the_preamble_is_read_and_a_property_there_is_not);
    Test.add_func ("/plugins/editorconfig/config-file/a_file_outside_the_configs_directory_matches_nothing", test_a_file_outside_the_configs_directory_matches_nothing);
    Test.add_func ("/plugins/editorconfig/config-file/no_editorconfig_file_loads_to_null", test_no_editorconfig_file_loads_to_null);
    Test.add_func ("/plugins/editorconfig/config-file/global_section_applies_to_any_path", test_global_section_applies_to_any_path);
    Test.add_func ("/plugins/editorconfig/config-file/language_specific_section_overrides_the_global_one", test_language_specific_section_overrides_the_global_one);
    Test.add_func ("/plugins/editorconfig/config-file/brace_alternation_matches_any_listed_extension", test_brace_alternation_matches_any_listed_extension);
    Test.add_func ("/plugins/editorconfig/config-file/pattern_without_a_slash_matches_at_any_depth", test_pattern_without_a_slash_matches_at_any_depth);
    Test.add_func ("/plugins/editorconfig/config-file/indent_size_tab_falls_back_to_tab_width", test_indent_size_tab_falls_back_to_tab_width);
    Test.add_func ("/plugins/editorconfig/config-file/indent_size_tab_without_tab_width_is_null", test_indent_size_tab_without_tab_width_is_null);
    Test.add_func ("/plugins/editorconfig/config-file/no_matching_section_is_null", test_no_matching_section_is_null);
    Test.add_func ("/plugins/editorconfig/config-file/later_section_wins_when_both_match_the_same_path", test_later_section_wins_when_both_match_the_same_path);
    Test.add_func ("/plugins/editorconfig/config-file/comments_and_blank_lines_are_ignored", test_comments_and_blank_lines_are_ignored);
    Test.add_func ("/plugins/editorconfig/config-file/the_save_switches_resolve_true_false_and_unset", test_the_save_switches_resolve_true_false_and_unset);
    Test.add_func ("/plugins/editorconfig/config-file/end_of_line_resolves_lf_and_crlf", test_end_of_line_resolves_lf_and_crlf);
    Test.add_func ("/plugins/editorconfig/config-file/end_of_line_unset_or_unsupported_is_null", test_end_of_line_unset_or_unsupported_is_null);
    Test.add_func ("/plugins/editorconfig/config-file/indent_style_space_resolves_to_insert_spaces_true", test_indent_style_space_resolves_to_insert_spaces_true);
    Test.add_func ("/plugins/editorconfig/config-file/indent_style_tab_resolves_to_insert_spaces_false", test_indent_style_tab_resolves_to_insert_spaces_false);
    Test.add_func ("/plugins/editorconfig/config-file/indent_style_unset_resolves_to_null", test_indent_style_unset_resolves_to_null);
    Test.add_func ("/plugins/editorconfig/config-file/indent_style_language_override_wins_over_the_global_default", test_indent_style_language_override_wins_over_the_global_default);
    Test.add_func ("/plugins/editorconfig/config-file/load_reads_indent_size_from_a_real_file", test_load_reads_indent_size_from_a_real_file);
    return Test.run ();
}
