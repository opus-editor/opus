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
        assert_true (contents.contains ("\"editor.font_size\": %d".printf (UserSettings.system_monospace_font_size ())));
    } catch (Error e) {
        error ("failed to exercise ensure_exists: %s", e.message);
    } finally {
        remove_temp_config_dir (config_dir);
    }
}

private void test_ensure_exists_leaves_an_existing_file_untouched () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"editor.font_size\": 20}");

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
    assert_true (contents == "{\"editor.font_size\": 20}");

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

private void test_ensure_exists_lists_restore_folder_first () {
    string config_dir = make_temp_config_dir ();

    try {
        string path = UserSettings.ensure_exists (config_dir);

        string contents;
        FileUtils.get_contents (path, out contents);
        assert_true (contents.has_prefix ("{\n  \"window.restore_folder\": false,\n"));
    } catch (Error e) {
        error ("failed to exercise ensure_exists: %s", e.message);
    } finally {
        remove_temp_config_dir (config_dir);
    }
}

private void test_load_reads_restore_folder () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"window.restore_folder\": true}");

    var settings = UserSettings.load (config_dir);

    assert_true (settings.restore_folder);

    remove_temp_config_dir (config_dir);
}

private void test_load_restore_folder_is_off_for_a_freshly_created_file () {
    string config_dir = make_temp_config_dir ();

    var settings = UserSettings.load (config_dir);

    assert_false (settings.restore_folder);

    remove_temp_config_dir (config_dir);
}

private void test_load_restore_folder_is_off_when_null () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"window.restore_folder\": null}");

    var settings = UserSettings.load (config_dir);

    assert_false (settings.restore_folder);

    remove_temp_config_dir (config_dir);
}

private void test_load_restore_folder_is_off_when_absent () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"editor.font_size\": 20}");

    var settings = UserSettings.load (config_dir);

    assert_false (settings.restore_folder);

    remove_temp_config_dir (config_dir);
}

private void test_load_reads_custom_editor_values () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{
  "editor.font_family": "Fira Code",
  "editor.font_size": 16,
  "editor.font_weight": "600",
  "editor.font_ligatures": true,
  "editor.line_height": 1.5,
  "editor.letter_spacing": 0.5,
  "editor.word_wrap": true
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
  "editor.font_size": "big",
  "editor.font_weight": "bold"
}""");

    var settings = UserSettings.load (config_dir);

    assert_cmpint (settings.font_size, CompareOperator.EQ, UserSettings.system_monospace_font_size ());
    assert_true (settings.font_weight == "bold");

    remove_temp_config_dir (config_dir);
}

private void test_toggle_word_wrap_defaults_to_off_when_the_key_is_absent () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{
  "editor.font_size": 16
}""");

    try {
        bool new_value = UserSettings.toggle_word_wrap (config_dir);
        assert_true (new_value);
    } catch (Error e) {
        error ("failed to exercise toggle_word_wrap: %s", e.message);
    }
    assert_true (UserSettings.load (config_dir).word_wrap);

    remove_temp_config_dir (config_dir);
}

private void test_toggle_word_wrap_flips_an_existing_value () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{
  "editor.word_wrap": true
}""");

    try {
        bool new_value = UserSettings.toggle_word_wrap (config_dir);
        assert_false (new_value);
    } catch (Error e) {
        error ("failed to exercise toggle_word_wrap: %s", e.message);
    }
    assert_false (UserSettings.load (config_dir).word_wrap);

    remove_temp_config_dir (config_dir);
}

private void test_toggle_word_wrap_preserves_every_other_key () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{
  "editor.font_family": "Fira Code",
  "editor.font_size": 16
}""");

    try {
        UserSettings.toggle_word_wrap (config_dir);
    } catch (Error e) {
        error ("failed to exercise toggle_word_wrap: %s", e.message);
    }
    var settings = UserSettings.load (config_dir);

    assert_true (settings.font_family == "Fira Code");
    assert_cmpint (settings.font_size, CompareOperator.EQ, 16);

    remove_temp_config_dir (config_dir);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/user-settings/path_is_settings_json_under_an_opus_subdirectory", test_path_is_settings_json_under_an_opus_subdirectory);
    Test.add_func ("/models/user-settings/ensure_exists_creates_the_file_with_default_content", test_ensure_exists_creates_the_file_with_default_content);
    Test.add_func ("/models/user-settings/ensure_exists_leaves_an_existing_file_untouched", test_ensure_exists_leaves_an_existing_file_untouched);
    Test.add_func ("/models/user-settings/load_returns_defaults_for_a_freshly_created_file", test_load_returns_defaults_for_a_freshly_created_file);
    Test.add_func ("/models/user-settings/ensure_exists_lists_restore_folder_first", test_ensure_exists_lists_restore_folder_first);
    Test.add_func ("/models/user-settings/load_reads_restore_folder", test_load_reads_restore_folder);
    Test.add_func ("/models/user-settings/load_restore_folder_is_off_for_a_freshly_created_file", test_load_restore_folder_is_off_for_a_freshly_created_file);
    Test.add_func ("/models/user-settings/load_restore_folder_is_off_when_null", test_load_restore_folder_is_off_when_null);
    Test.add_func ("/models/user-settings/load_restore_folder_is_off_when_absent", test_load_restore_folder_is_off_when_absent);
    Test.add_func ("/models/user-settings/load_reads_custom_editor_values", test_load_reads_custom_editor_values);
    Test.add_func ("/models/user-settings/load_falls_back_to_defaults_on_invalid_json", test_load_falls_back_to_defaults_on_invalid_json);
    Test.add_func ("/models/user-settings/load_falls_back_per_key_when_a_value_has_the_wrong_type", test_load_falls_back_per_key_when_a_value_has_the_wrong_type);
    Test.add_func ("/models/user-settings/toggle_word_wrap_defaults_to_off_when_the_key_is_absent", test_toggle_word_wrap_defaults_to_off_when_the_key_is_absent);
    Test.add_func ("/models/user-settings/toggle_word_wrap_flips_an_existing_value", test_toggle_word_wrap_flips_an_existing_value);
    Test.add_func ("/models/user-settings/toggle_word_wrap_preserves_every_other_key", test_toggle_word_wrap_preserves_every_other_key);
    return Test.run ();
}
