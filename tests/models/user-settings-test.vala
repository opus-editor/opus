private string make_temp_config_dir () {
    try {
        return DirUtils.make_tmp ("opus-user-settings-test-XXXXXX");
    } catch (Error e) {
        error ("failed to create fixture directory: %s", e.message);
    }
}

private void remove_temp_config_dir (string config_dir) {
    FileUtils.remove (UserSettings.path (config_dir));
    DirUtils.remove (Path.build_filename (config_dir, "opus"));
    DirUtils.remove (config_dir);
}

private void write_settings (string config_dir, string contents) {
    string path = UserSettings.path (config_dir);
    try {
        DirUtils.create_with_parents (Path.get_dirname (path), 0700);
        FileUtils.set_contents (path, contents);
    } catch (Error e) {
        error ("failed to write fixture settings.json: %s", e.message);
    }
}

private void test_path_is_settings_json_under_an_opus_subdirectory () {
    string config_dir = make_temp_config_dir ();

    string path = UserSettings.path (config_dir);

    assert_true (path == Path.build_filename (config_dir, "opus", "settings.json"));

    DirUtils.remove (config_dir);
}

private void test_ensure_exists_creates_the_file_with_default_content () {
    string config_dir = make_temp_config_dir ();

    try {
        string path = UserSettings.ensure_exists (config_dir);

        assert_true (FileUtils.test (path, FileTest.EXISTS));

        string contents;
        FileUtils.get_contents (path, out contents);
        assert_true (contents.contains ("\"themes.syntaxHighlight\": \"Opus Colors\""));
        assert_true (contents.contains ("\"editor.fontSize\": %d".printf (UserSettings.system_monospace_font_size ())));
    } catch (Error e) {
        error ("failed to exercise ensure_exists: %s", e.message);
    } finally {
        remove_temp_config_dir (config_dir);
    }
}

private void test_ensure_exists_leaves_an_existing_file_untouched () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"editor.fontSize\": 20}");

    try {
        UserSettings.ensure_exists (config_dir);
    } catch (Error e) {
        error ("failed to exercise ensure_exists: %s", e.message);
    }

    string contents;
    try {
        FileUtils.get_contents (UserSettings.path (config_dir), out contents);
    } catch (Error e) {
        error ("failed to read fixture settings.json: %s", e.message);
    }
    assert_true (contents == "{\"editor.fontSize\": 20}");

    remove_temp_config_dir (config_dir);
}

private void test_load_returns_defaults_for_a_freshly_created_file () {
    string config_dir = make_temp_config_dir ();

    var settings = UserSettings.load (config_dir);

    assert_null (settings.font_family);
    assert_cmpint (settings.font_size, CompareOperator.EQ, UserSettings.system_monospace_font_size ());
    assert_true (settings.font_weight == "normal");
    assert_false (settings.font_ligatures);
    assert_cmpfloat (settings.line_height, CompareOperator.EQ, 1);
    assert_cmpfloat (settings.letter_spacing, CompareOperator.EQ, 0);
    assert_false (settings.word_wrap);

    remove_temp_config_dir (config_dir);
}

private void test_load_reads_custom_editor_values () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{
  "editor.fontFamily": "Fira Code",
  "editor.fontSize": 16,
  "editor.fontWeight": "600",
  "editor.fontLigatures": true,
  "editor.lineHeight": 1.5,
  "editor.letterSpacing": 0.5,
  "editor.wordWrap": true
}""");

    var settings = UserSettings.load (config_dir);

    assert_true (settings.font_family == "Fira Code");
    assert_cmpint (settings.font_size, CompareOperator.EQ, 16);
    assert_true (settings.font_weight == "600");
    assert_true (settings.font_ligatures);
    assert_cmpfloat (settings.line_height, CompareOperator.EQ, 1.5);
    assert_cmpfloat (settings.letter_spacing, CompareOperator.EQ, 0.5);
    assert_true (settings.word_wrap);

    remove_temp_config_dir (config_dir);
}

private void test_load_falls_back_to_defaults_on_invalid_json () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{ not valid json");

    var settings = UserSettings.load (config_dir);

    assert_cmpint (settings.font_size, CompareOperator.EQ, UserSettings.system_monospace_font_size ());

    remove_temp_config_dir (config_dir);
}

private void test_load_falls_back_per_key_when_a_value_has_the_wrong_type () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{
  "editor.fontSize": "big",
  "editor.fontWeight": "bold"
}""");

    var settings = UserSettings.load (config_dir);

    assert_cmpint (settings.font_size, CompareOperator.EQ, UserSettings.system_monospace_font_size ());
    assert_true (settings.font_weight == "bold");

    remove_temp_config_dir (config_dir);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/user-settings/path_is_settings_json_under_an_opus_subdirectory", test_path_is_settings_json_under_an_opus_subdirectory);
    Test.add_func ("/models/user-settings/ensure_exists_creates_the_file_with_default_content", test_ensure_exists_creates_the_file_with_default_content);
    Test.add_func ("/models/user-settings/ensure_exists_leaves_an_existing_file_untouched", test_ensure_exists_leaves_an_existing_file_untouched);
    Test.add_func ("/models/user-settings/load_returns_defaults_for_a_freshly_created_file", test_load_returns_defaults_for_a_freshly_created_file);
    Test.add_func ("/models/user-settings/load_reads_custom_editor_values", test_load_reads_custom_editor_values);
    Test.add_func ("/models/user-settings/load_falls_back_to_defaults_on_invalid_json", test_load_falls_back_to_defaults_on_invalid_json);
    Test.add_func ("/models/user-settings/load_falls_back_per_key_when_a_value_has_the_wrong_type", test_load_falls_back_per_key_when_a_value_has_the_wrong_type);
    return Test.run ();
}
