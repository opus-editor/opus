private UserSettings settings_with (string json) {
    string config_dir;
    try {
        config_dir = DirUtils.make_tmp ("opus-indentation-test-XXXXXX");
        DirUtils.create (Path.build_filename (config_dir, "opus"), 0700);
        FileUtils.set_contents (Path.build_filename (config_dir, "opus", "settings.json"), json);
    } catch (Error e) {
        error ("failed to create fixture: %s", e.message);
    }
    return new UserSettings (config_dir);
}

private void test_without_any_source_it_is_four_spaces_indenting_by_itself () {
    var file = new FileSettings.Values ();

    var indentation = Indentation.resolve (file, settings_with ("{}"), null);

    assert_cmpint (indentation.size, CompareOperator.EQ, 4);
    assert_true (indentation.insert_spaces);
    assert_cmpint (indentation.tab_width, CompareOperator.EQ, 4);
    assert_true (indentation.auto_indent);
}

private void test_settings_json_is_read_for_the_language () {
    var file = new FileSettings.Values ();
    var settings = settings_with ("""{ "editor.indent_style": "tab", "editor.indent_size": 2, "editor.auto_indent": false, "language.go": { "editor.indent_size": 8 } }""");

    var indentation = Indentation.resolve (file, settings, "go");

    assert_cmpint (indentation.size, CompareOperator.EQ, 8);
    assert_false (indentation.insert_spaces);
    assert_false (indentation.auto_indent);
}

private void test_the_folders_word_wins_over_settings_json () {
    var file = new FileSettings.Values () { indent_size = 3, insert_spaces = true, tab_width = 6 };
    var settings = settings_with ("""{ "editor.indent_style": "tab", "editor.indent_size": 2 }""");

    var indentation = Indentation.resolve (file, settings, null);

    assert_cmpint (indentation.size, CompareOperator.EQ, 3);
    assert_true (indentation.insert_spaces);
    assert_cmpint (indentation.tab_width, CompareOperator.EQ, 6);
}

private void test_the_documents_own_picks_win_over_the_folder () {
    var file = new FileSettings.Values () { indent_size = 3, insert_spaces = true };
    var document = Document.untitled ("1", "Untitled-1");
    document.indent_size_override = 5;
    document.insert_spaces_override = Document.Override.OFF;
    document.auto_indent_override = Document.Override.OFF;

    var indentation = Indentation.resolve (file, settings_with ("{}"), null, document);

    assert_cmpint (indentation.size, CompareOperator.EQ, 5);
    assert_false (indentation.insert_spaces);
    assert_false (indentation.auto_indent);
}

private void test_a_tab_renders_as_wide_as_the_indent_unless_something_says () {
    var file = new FileSettings.Values () { indent_size = 3 };

    var indentation = Indentation.resolve (file, settings_with ("{}"), null);

    assert_cmpint (indentation.tab_width, CompareOperator.EQ, 3);
    assert_true (indentation.tab_width_from_size);
}

private void test_settings_json_sets_the_tab_width_apart_from_the_indent () {
    var file = new FileSettings.Values ();
    var settings = settings_with ("""{ "editor.indent_size": 2, "editor.tab_width": 8 }""");

    var indentation = Indentation.resolve (file, settings, null);

    assert_cmpint (indentation.tab_width, CompareOperator.EQ, 8);
    assert_false (indentation.tab_width_from_size);
}

private void test_the_documents_own_tab_width_wins_over_the_folder () {
    var file = new FileSettings.Values () { tab_width = 8 };
    var document = Document.untitled ("1", "Untitled-1");
    document.tab_width_override = 6;

    var indentation = Indentation.resolve (file, settings_with ("{}"), null, document);

    assert_cmpint (indentation.tab_width, CompareOperator.EQ, 6);
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/indentation/without_any_source_it_is_four_spaces_indenting_by_itself", test_without_any_source_it_is_four_spaces_indenting_by_itself);
    Test.add_func ("/models/indentation/settings_json_is_read_for_the_language", test_settings_json_is_read_for_the_language);
    Test.add_func ("/models/indentation/the_folders_word_wins_over_settings_json", test_the_folders_word_wins_over_settings_json);
    Test.add_func ("/models/indentation/the_documents_own_picks_win_over_the_folder", test_the_documents_own_picks_win_over_the_folder);
    Test.add_func ("/models/indentation/a_tab_renders_as_wide_as_the_indent_unless_something_says", test_a_tab_renders_as_wide_as_the_indent_unless_something_says);
    Test.add_func ("/models/indentation/settings_json_sets_the_tab_width_apart_from_the_indent", test_settings_json_sets_the_tab_width_apart_from_the_indent);
    Test.add_func ("/models/indentation/the_documents_own_tab_width_wins_over_the_folder", test_the_documents_own_tab_width_wins_over_the_folder);
    Test.run ();
}
