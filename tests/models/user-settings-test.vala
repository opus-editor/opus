private string make_temp_config_dir () {
    try {
        return DirUtils.make_tmp ("opus-user-settings-test-XXXXXX");
    } catch (Error e) {
        error ("failed to create fixture directory: %s", e.message);
    }
}

private string settings_path (string config_dir) {
    return Path.build_filename (config_dir, "opus", "settings.json");
}

private void remove_temp_config_dir (string config_dir) {
    FileUtils.remove (settings_path (config_dir));
    DirUtils.remove (Path.build_filename (config_dir, "opus"));
    DirUtils.remove (config_dir);
}

private void write_settings (string config_dir, string contents) {
    string path = settings_path (config_dir);
    try {
        DirUtils.create_with_parents (Path.get_dirname (path), 0700);
        FileUtils.set_contents (path, contents);
    } catch (Error e) {
        error ("failed to write fixture settings.json: %s", e.message);
    }
}

private string read_settings (string config_dir) {
    string contents;
    try {
        FileUtils.get_contents (settings_path (config_dir), out contents);
    } catch (Error e) {
        error ("failed to read fixture settings.json: %s", e.message);
    }
    return contents;
}

private void test_path_is_settings_json_under_an_opus_subdirectory () {
    string config_dir = make_temp_config_dir ();

    var settings = new UserSettings (config_dir);

    assert_true (settings.path == Path.build_filename (config_dir, "opus", "settings.json"));

    remove_temp_config_dir (config_dir);
}

private void test_creates_the_file_with_default_content () {
    string config_dir = make_temp_config_dir ();

    new UserSettings (config_dir);

    assert_true (read_settings (config_dir).contains ("\"editor.font_size\": %d".printf (UserSettings.system_monospace_font_size ())));

    remove_temp_config_dir (config_dir);
}

private void test_default_content_lists_save_session_first () {
    string config_dir = make_temp_config_dir ();

    new UserSettings (config_dir);

    assert_true (read_settings (config_dir).has_prefix ("{\n  \"window.save_session\": false,\n"));

    remove_temp_config_dir (config_dir);
}

private void test_the_themes_default_to_the_bundled_github_pair () {
    string config_dir = make_temp_config_dir ();

    var settings = new UserSettings (config_dir);

    assert_cmpstr (settings.theme_light, CompareOperator.EQ, "github");
    assert_cmpstr (settings.theme_dark, CompareOperator.EQ, "github");

    remove_temp_config_dir (config_dir);
}

private void test_the_themes_are_read_from_the_file () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"editor.theme_light\": \"paper\", \"editor.theme_dark\": \"ink\"}");

    var settings = new UserSettings (config_dir);

    assert_cmpstr (settings.theme_light, CompareOperator.EQ, "paper");
    assert_cmpstr (settings.theme_dark, CompareOperator.EQ, "ink");

    remove_temp_config_dir (config_dir);
}

private void test_a_theme_of_the_wrong_type_falls_back_to_the_default () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"editor.theme_light\": 3}");

    var settings = new UserSettings (config_dir);

    assert_cmpstr (settings.theme_light, CompareOperator.EQ, "github");

    remove_temp_config_dir (config_dir);
}

private void test_changes_sort_defaults_to_path () {
    string config_dir = make_temp_config_dir ();

    var settings = new UserSettings (config_dir);

    assert_cmpstr (settings.changes_sort, CompareOperator.EQ, "path");

    remove_temp_config_dir (config_dir);
}

private void test_changes_sort_is_read_from_the_file () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"git.changes_sort\": \"status\"}");

    var settings = new UserSettings (config_dir);

    assert_cmpstr (settings.changes_sort, CompareOperator.EQ, "status");

    remove_temp_config_dir (config_dir);
}

private void test_changes_sort_of_the_wrong_type_falls_back_to_path () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"git.changes_sort\": 3}");

    var settings = new UserSettings (config_dir);

    assert_cmpstr (settings.changes_sort, CompareOperator.EQ, "path");

    remove_temp_config_dir (config_dir);
}

private void test_leaves_an_existing_file_untouched () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"editor.font_size\": 20}");

    new UserSettings (config_dir);

    assert_true (read_settings (config_dir) == "{\"editor.font_size\": 20}");

    remove_temp_config_dir (config_dir);
}

private void test_ensure_exists_recreates_a_deleted_file () {
    string config_dir = make_temp_config_dir ();
    var settings = new UserSettings (config_dir);
    FileUtils.remove (settings.path);

    try {
        settings.ensure_exists ();
    } catch (Error e) {
        error ("failed to exercise ensure_exists: %s", e.message);
    }

    assert_true (FileUtils.test (settings.path, FileTest.EXISTS));

    remove_temp_config_dir (config_dir);
}

private void test_reads_defaults_from_a_freshly_created_file () {
    string config_dir = make_temp_config_dir ();

    var settings = new UserSettings (config_dir);

    assert_false (settings.save_session);
    assert_null (settings.font_family);
    assert_cmpint (settings.font_size, CompareOperator.EQ, UserSettings.system_monospace_font_size ());
    assert_true (settings.font_weight == "normal");
    assert_false (settings.font_ligatures);
    assert_cmpfloat (settings.line_height, CompareOperator.EQ, 1);
    assert_cmpfloat (settings.letter_spacing, CompareOperator.EQ, 0);
    assert_false (settings.word_wrap);

    remove_temp_config_dir (config_dir);
}

private void test_reads_custom_editor_values () {
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

    var settings = new UserSettings (config_dir);

    assert_true (settings.font_family == "Fira Code");
    assert_cmpint (settings.font_size, CompareOperator.EQ, 16);
    assert_true (settings.font_weight == "600");
    assert_true (settings.font_ligatures);
    assert_cmpfloat (settings.line_height, CompareOperator.EQ, 1.5);
    assert_cmpfloat (settings.letter_spacing, CompareOperator.EQ, 0.5);
    assert_true (settings.word_wrap);

    remove_temp_config_dir (config_dir);
}

private void test_reads_save_session () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"window.save_session\": true}");

    var settings = new UserSettings (config_dir);

    assert_true (settings.save_session);

    remove_temp_config_dir (config_dir);
}

private void test_save_session_is_off_when_null () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"window.save_session\": null}");

    var settings = new UserSettings (config_dir);

    assert_false (settings.save_session);

    remove_temp_config_dir (config_dir);
}

private void test_save_session_is_off_when_absent () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"editor.font_size\": 20}");

    var settings = new UserSettings (config_dir);

    assert_false (settings.save_session);

    remove_temp_config_dir (config_dir);
}

private void test_falls_back_to_defaults_on_invalid_json () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{ not valid json");

    var settings = new UserSettings (config_dir);

    assert_cmpint (settings.font_size, CompareOperator.EQ, UserSettings.system_monospace_font_size ());

    remove_temp_config_dir (config_dir);
}

private void test_falls_back_per_key_when_a_value_has_the_wrong_type () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{
  "editor.font_size": "big",
  "editor.font_weight": "bold"
}""");

    var settings = new UserSettings (config_dir);

    assert_cmpint (settings.font_size, CompareOperator.EQ, UserSettings.system_monospace_font_size ());
    assert_true (settings.font_weight == "bold");

    remove_temp_config_dir (config_dir);
}

private void test_word_wrap_for_a_language_reads_its_block () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{ "editor.word_wrap": false, "language.markdown": { "editor.word_wrap": true } }""");
    var settings = new UserSettings (config_dir);

    bool wraps = settings.word_wrap_for ("markdown");

    assert_true (wraps);
    remove_temp_config_dir (config_dir);
}

private void test_word_wrap_for_a_language_without_a_block_is_the_plain_key () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{ "editor.word_wrap": true, "language.markdown": { "editor.word_wrap": false } }""");
    var settings = new UserSettings (config_dir);

    bool wraps = settings.word_wrap_for ("ruby");

    assert_true (wraps);
    remove_temp_config_dir (config_dir);
}

private void test_word_wrap_for_no_language_is_the_plain_key () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{ "editor.word_wrap": true }""");
    var settings = new UserSettings (config_dir);

    bool wraps = settings.word_wrap_for (null);

    assert_true (wraps);
    remove_temp_config_dir (config_dir);
}

private void test_word_wrap_for_a_language_block_of_the_wrong_type_is_the_plain_key () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{ "editor.word_wrap": false, "language.markdown": { "editor.word_wrap": "yes" } }""");
    var settings = new UserSettings (config_dir);

    bool wraps = settings.word_wrap_for ("markdown");

    assert_false (wraps);
    remove_temp_config_dir (config_dir);
}

private void test_editorconfig_max_line_length_is_off_unless_asked () {
    string config_dir = make_temp_config_dir ();
    var settings = new UserSettings (config_dir);
    assert_false (settings.editorconfig_max_line_length_for (null));
    remove_temp_config_dir (config_dir);

    string on_dir = make_temp_config_dir ();
    write_settings (on_dir, """{ "editorconfig.max_line_length": true, "language.markdown": { "editorconfig.max_line_length": false } }""");
    var on = new UserSettings (on_dir);

    assert_true (on.editorconfig_max_line_length_for ("ruby"));
    assert_false (on.editorconfig_max_line_length_for ("markdown"));
    remove_temp_config_dir (on_dir);
}

private void test_rulers_read_the_columns () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{ "editor.rulers": [80, 120] }""");
    var settings = new UserSettings (config_dir);

    var columns = settings.rulers_for (null);

    assert_cmpint (columns.length, CompareOperator.EQ, 2);
    assert_cmpint (columns[0], CompareOperator.EQ, 80);
    assert_cmpint (columns[1], CompareOperator.EQ, 120);
    remove_temp_config_dir (config_dir);
}

private void test_rulers_for_a_language_are_its_blocks_own () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{ "editor.rulers": [80], "language.markdown": { "editor.rulers": [] } }""");
    var settings = new UserSettings (config_dir);

    assert_cmpint (settings.rulers_for ("markdown").length, CompareOperator.EQ, 0);
    assert_cmpint (settings.rulers_for ("ruby").length, CompareOperator.EQ, 1);
    remove_temp_config_dir (config_dir);
}

private void test_rulers_without_the_key_are_none_and_odd_entries_are_skipped () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{ "editor.rulers": [80, "100", 0, -5, 2.5] }""");
    var settings = new UserSettings (config_dir);

    var columns = settings.rulers_for (null);

    assert_cmpint (columns.length, CompareOperator.EQ, 1);
    assert_cmpint (columns[0], CompareOperator.EQ, 80);
    remove_temp_config_dir (config_dir);
    string empty_dir = make_temp_config_dir ();
    assert_cmpint (new UserSettings (empty_dir).rulers_for (null).length, CompareOperator.EQ, 0);
    remove_temp_config_dir (empty_dir);
}

private void test_on_save_reads_the_list_in_order () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{ "editor.on_save": ["trim-trailing-whitespace", "insert-final-newline"] }""");
    var settings = new UserSettings (config_dir);

    var ids = settings.on_save_for (null);

    assert_cmpstrv (ids, { "trim-trailing-whitespace", "insert-final-newline" });
    remove_temp_config_dir (config_dir);
}

private void test_on_save_for_a_language_is_its_blocks_own_list () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{ "editor.on_save": ["trim-trailing-whitespace"], "language.markdown": { "editor.on_save": [] } }""");
    var settings = new UserSettings (config_dir);

    var ids = settings.on_save_for ("markdown");

    assert_cmpint (ids.length, CompareOperator.EQ, 0);
    remove_temp_config_dir (config_dir);
}

private void test_on_save_without_the_key_is_empty () {
    string config_dir = make_temp_config_dir ();
    var settings = new UserSettings (config_dir);

    assert_cmpint (settings.on_save_for ("ruby").length, CompareOperator.EQ, 0);
    remove_temp_config_dir (config_dir);
}

private void test_on_save_skips_entries_that_are_not_strings () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{ "editor.on_save": ["trim-trailing-whitespace", 3, null] }""");
    var settings = new UserSettings (config_dir);

    assert_cmpstrv (settings.on_save_for (null), { "trim-trailing-whitespace" });
    remove_temp_config_dir (config_dir);
}

private void test_setting_word_wrap_reads_back_right_away () {
    string config_dir = make_temp_config_dir ();
    var settings = new UserSettings (config_dir);

    settings.word_wrap = true;

    assert_true (settings.word_wrap);

    remove_temp_config_dir (config_dir);
}

private void test_setting_word_wrap_announces_a_change () {
    string config_dir = make_temp_config_dir ();
    var settings = new UserSettings (config_dir);
    int announced = 0;
    settings.changed.connect (() => announced++);

    settings.word_wrap = true;

    assert_cmpint (announced, CompareOperator.EQ, 1);

    remove_temp_config_dir (config_dir);
}

private void test_setting_word_wrap_does_not_write_the_file () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"editor.word_wrap\": false}");
    var settings = new UserSettings (config_dir);

    settings.word_wrap = true;

    assert_true (read_settings (config_dir) == "{\"editor.word_wrap\": false}");

    remove_temp_config_dir (config_dir);
}

private void test_save_writes_a_changed_value () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"editor.word_wrap\": true}");
    var settings = new UserSettings (config_dir);
    settings.word_wrap = false;

    try {
        settings.save ();
    } catch (Error e) {
        error ("failed to exercise save: %s", e.message);
    }

    assert_false (new UserSettings (config_dir).word_wrap);

    remove_temp_config_dir (config_dir);
}

private void test_save_writes_a_key_the_file_did_not_have () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"editor.font_size\": 16}");
    var settings = new UserSettings (config_dir);
    settings.word_wrap = true;

    try {
        settings.save ();
    } catch (Error e) {
        error ("failed to exercise save: %s", e.message);
    }

    assert_true (new UserSettings (config_dir).word_wrap);

    remove_temp_config_dir (config_dir);
}

private void test_save_preserves_every_other_key () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, """{
  "editor.font_family": "Fira Code",
  "editor.font_size": 16,
  "some.other_tool": "kept"
}""");
    var settings = new UserSettings (config_dir);
    settings.word_wrap = true;

    try {
        settings.save ();
    } catch (Error e) {
        error ("failed to exercise save: %s", e.message);
    }

    var saved = new UserSettings (config_dir);
    assert_true (saved.font_family == "Fira Code");
    assert_cmpint (saved.font_size, CompareOperator.EQ, 16);
    assert_true (read_settings (config_dir).contains ("\"some.other_tool\""));

    remove_temp_config_dir (config_dir);
}

private void test_reload_reads_a_rewritten_file () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"editor.font_size\": 16}");
    var settings = new UserSettings (config_dir);
    write_settings (config_dir, "{\"editor.font_size\": 20}");

    settings.reload ();

    assert_cmpint (settings.font_size, CompareOperator.EQ, 20);

    remove_temp_config_dir (config_dir);
}

private void test_reload_announces_a_change () {
    string config_dir = make_temp_config_dir ();
    var settings = new UserSettings (config_dir);
    int announced = 0;
    settings.changed.connect (() => announced++);

    settings.reload ();

    assert_cmpint (announced, CompareOperator.EQ, 1);

    remove_temp_config_dir (config_dir);
}

private void test_reload_keeps_the_last_values_while_the_file_is_invalid () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"editor.font_size\": 16}");
    var settings = new UserSettings (config_dir);
    write_settings (config_dir, "{ \"editor.font_size\": ");

    settings.reload ();

    assert_cmpint (settings.font_size, CompareOperator.EQ, 16);

    remove_temp_config_dir (config_dir);
}

private void test_reload_of_an_invalid_file_announces_nothing () {
    string config_dir = make_temp_config_dir ();
    var settings = new UserSettings (config_dir);
    int announced = 0;
    settings.changed.connect (() => announced++);
    write_settings (config_dir, "{ not valid json");

    settings.reload ();

    assert_cmpint (announced, CompareOperator.EQ, 0);

    remove_temp_config_dir (config_dir);
}

private void test_reload_keeps_the_last_values_when_the_file_is_gone () {
    string config_dir = make_temp_config_dir ();
    write_settings (config_dir, "{\"editor.font_size\": 16}");
    var settings = new UserSettings (config_dir);
    FileUtils.remove (settings.path);

    settings.reload ();

    assert_cmpint (settings.font_size, CompareOperator.EQ, 16);

    remove_temp_config_dir (config_dir);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/user-settings/path_is_settings_json_under_an_opus_subdirectory", test_path_is_settings_json_under_an_opus_subdirectory);
    Test.add_func ("/models/user-settings/creates_the_file_with_default_content", test_creates_the_file_with_default_content);
    Test.add_func ("/models/user-settings/default_content_lists_save_session_first", test_default_content_lists_save_session_first);
    Test.add_func ("/models/user-settings/leaves_an_existing_file_untouched", test_leaves_an_existing_file_untouched);
    Test.add_func ("/models/user-settings/ensure_exists_recreates_a_deleted_file", test_ensure_exists_recreates_a_deleted_file);
    Test.add_func ("/models/user-settings/reads_defaults_from_a_freshly_created_file", test_reads_defaults_from_a_freshly_created_file);
    Test.add_func ("/models/user-settings/reads_custom_editor_values", test_reads_custom_editor_values);
    Test.add_func ("/models/user-settings/reads_save_session", test_reads_save_session);
    Test.add_func ("/models/user-settings/save_session_is_off_when_null", test_save_session_is_off_when_null);
    Test.add_func ("/models/user-settings/save_session_is_off_when_absent", test_save_session_is_off_when_absent);
    Test.add_func ("/models/user-settings/falls_back_to_defaults_on_invalid_json", test_falls_back_to_defaults_on_invalid_json);
    Test.add_func ("/models/user-settings/falls_back_per_key_when_a_value_has_the_wrong_type", test_falls_back_per_key_when_a_value_has_the_wrong_type);
    Test.add_func ("/models/user-settings/setting_word_wrap_reads_back_right_away", test_setting_word_wrap_reads_back_right_away);
    Test.add_func ("/models/user-settings/setting_word_wrap_announces_a_change", test_setting_word_wrap_announces_a_change);
    Test.add_func ("/models/user-settings/setting_word_wrap_does_not_write_the_file", test_setting_word_wrap_does_not_write_the_file);
    Test.add_func ("/models/user-settings/save_writes_a_changed_value", test_save_writes_a_changed_value);
    Test.add_func ("/models/user-settings/save_writes_a_key_the_file_did_not_have", test_save_writes_a_key_the_file_did_not_have);
    Test.add_func ("/models/user-settings/save_preserves_every_other_key", test_save_preserves_every_other_key);
    Test.add_func ("/models/user-settings/reload_reads_a_rewritten_file", test_reload_reads_a_rewritten_file);
    Test.add_func ("/models/user-settings/reload_announces_a_change", test_reload_announces_a_change);
    Test.add_func ("/models/user-settings/reload_keeps_the_last_values_while_the_file_is_invalid", test_reload_keeps_the_last_values_while_the_file_is_invalid);
    Test.add_func ("/models/user-settings/reload_of_an_invalid_file_announces_nothing", test_reload_of_an_invalid_file_announces_nothing);
    Test.add_func ("/models/user-settings/reload_keeps_the_last_values_when_the_file_is_gone", test_reload_keeps_the_last_values_when_the_file_is_gone);
    Test.add_func ("/models/user-settings/the_themes_default_to_the_bundled_github_pair", test_the_themes_default_to_the_bundled_github_pair);
    Test.add_func ("/models/user-settings/the_themes_are_read_from_the_file", test_the_themes_are_read_from_the_file);
    Test.add_func ("/models/user-settings/a_theme_of_the_wrong_type_falls_back_to_the_default", test_a_theme_of_the_wrong_type_falls_back_to_the_default);
    Test.add_func ("/models/user-settings/word_wrap_for_a_language_reads_its_block", test_word_wrap_for_a_language_reads_its_block);
    Test.add_func ("/models/user-settings/word_wrap_for_a_language_without_a_block_is_the_plain_key", test_word_wrap_for_a_language_without_a_block_is_the_plain_key);
    Test.add_func ("/models/user-settings/word_wrap_for_no_language_is_the_plain_key", test_word_wrap_for_no_language_is_the_plain_key);
    Test.add_func ("/models/user-settings/word_wrap_for_a_language_block_of_the_wrong_type_is_the_plain_key", test_word_wrap_for_a_language_block_of_the_wrong_type_is_the_plain_key);
    Test.add_func ("/models/user-settings/editorconfig_max_line_length_is_off_unless_asked", test_editorconfig_max_line_length_is_off_unless_asked);
    Test.add_func ("/models/user-settings/rulers_read_the_columns", test_rulers_read_the_columns);
    Test.add_func ("/models/user-settings/rulers_for_a_language_are_its_blocks_own", test_rulers_for_a_language_are_its_blocks_own);
    Test.add_func ("/models/user-settings/rulers_without_the_key_are_none_and_odd_entries_are_skipped", test_rulers_without_the_key_are_none_and_odd_entries_are_skipped);
    Test.add_func ("/models/user-settings/on_save_reads_the_list_in_order", test_on_save_reads_the_list_in_order);
    Test.add_func ("/models/user-settings/on_save_for_a_language_is_its_blocks_own_list", test_on_save_for_a_language_is_its_blocks_own_list);
    Test.add_func ("/models/user-settings/on_save_without_the_key_is_empty", test_on_save_without_the_key_is_empty);
    Test.add_func ("/models/user-settings/on_save_skips_entries_that_are_not_strings", test_on_save_skips_entries_that_are_not_strings);
    Test.add_func ("/models/user-settings/changes_sort_defaults_to_path", test_changes_sort_defaults_to_path);
    Test.add_func ("/models/user-settings/changes_sort_is_read_from_the_file", test_changes_sort_is_read_from_the_file);
    Test.add_func ("/models/user-settings/changes_sort_of_the_wrong_type_falls_back_to_path", test_changes_sort_of_the_wrong_type_falls_back_to_path);
    return Test.run ();
}
