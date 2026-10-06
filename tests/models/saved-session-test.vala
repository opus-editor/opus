private const string FULL = """{
  "folder": "/home/me/project",
  "active": "/home/me/project/b.rb",
  "tabs": [
    { "path": "/home/me/project/a.rb", "line": 1, "column": 0, "top_line": 1 },
    { "path": "/home/me/project/b.rb", "line": 42, "column": 7, "top_line": 30, "preview": true }
  ]
}""";

private SavedSession parse (string json) {
    try {
        return SavedSession.parse (json);
    } catch (SessionError e) {
        error ("the session should have parsed: %s", e.message);
    }
}

private void assert_invalid (string json, string message_part) {
    try {
        SavedSession.parse (json);
        assert_not_reached ();
    } catch (SessionError e) {
        assert_true (e.message.contains (message_part));
    }
}

private string new_folder () {
    try {
        return DirUtils.make_tmp ("opus-saved-session-test-XXXXXX");
    } catch (Error e) {
        error ("%s", e.message);
    }
}

private string write_file (string folder, string name) {
    var path = Path.build_filename (folder, name);
    try {
        FileUtils.set_contents (path, "");
    } catch (FileError e) {
        error ("%s", e.message);
    }
    return path;
}

private void test_a_session_reads_its_folder_tabs_and_active_tab () {
    var session = parse (FULL);

    assert_cmpstr (session.folder, CompareOperator.EQ, "/home/me/project");
    assert_cmpstr (session.active, CompareOperator.EQ, "/home/me/project/b.rb");
    assert_cmpuint (session.tabs.length, CompareOperator.EQ, 2);
    assert_cmpstr (session.tabs[0].path, CompareOperator.EQ, "/home/me/project/a.rb");
}

private void test_a_tab_reads_where_its_cursor_and_scroll_were () {
    var session = parse (FULL);

    var tab = session.tabs[1];

    assert_cmpint (tab.line, CompareOperator.EQ, 42);
    assert_cmpint (tab.column, CompareOperator.EQ, 7);
    assert_cmpint (tab.top_line, CompareOperator.EQ, 30);
    assert_true (tab.preview);
}

private void test_what_a_tab_leaves_out_starts_at_the_top_as_a_permanent_tab () {
    var session = parse ("""{ "folder": "/p", "tabs": [ { "path": "/p/a.rb" } ] }""");

    var tab = session.tabs[0];

    assert_cmpint (tab.line, CompareOperator.EQ, 1);
    assert_cmpint (tab.column, CompareOperator.EQ, 0);
    assert_cmpint (tab.top_line, CompareOperator.EQ, 1);
    assert_false (tab.preview);
}

private void test_a_session_with_no_tabs_and_no_active_tab_is_a_folder_alone () {
    var session = parse ("""{ "folder": "/p" }""");

    assert_cmpuint (session.tabs.length, CompareOperator.EQ, 0);
    assert_null (session.active);
}

private void test_a_session_written_reads_back_the_same () {
    var session = parse (FULL);

    var again = parse (session.to_json ());

    assert_cmpstr (again.to_json (), CompareOperator.EQ, session.to_json ());
    assert_cmpstr (again.active, CompareOperator.EQ, session.active);
    assert_cmpint (again.tabs[1].top_line, CompareOperator.EQ, 30);
}

private void test_text_that_is_not_json_is_invalid () {
    assert_invalid ("not json", "not valid JSON");
}

private void test_a_session_that_is_not_an_object_is_invalid () {
    assert_invalid ("[]", "must be a JSON object");
}

private void test_a_session_without_a_folder_is_invalid () {
    assert_invalid ("""{ "tabs": [] }""", "\"folder\" must be a string");
}

private void test_a_tab_without_a_path_is_invalid_and_says_which () {
    assert_invalid ("""{ "folder": "/p", "tabs": [ { "path": "/p/a" }, { "line": 3 } ] }""", "tabs[1].path must be a string");
}

private void test_a_tab_with_a_line_that_is_not_a_number_is_invalid () {
    assert_invalid ("""{ "folder": "/p", "tabs": [ { "path": "/p/a", "line": "3" } ] }""", "tabs[0].line must be a whole number");
}

private void test_tabs_that_are_not_an_array_are_invalid () {
    assert_invalid ("""{ "folder": "/p", "tabs": {} }""", "\"tabs\" must be an array");
}

private void test_restoring_keeps_only_the_tabs_whose_files_still_exist () {
    var folder = new_folder ();
    var kept = write_file (folder, "kept.rb");
    var session = parse ("""{ "folder": "%s", "tabs": [ { "path": "%s" }, { "path": "%s/gone.rb" } ] }""".printf (folder, kept, folder));

    var restorable = session.restorable ();

    assert_cmpuint (restorable.tabs.length, CompareOperator.EQ, 1);
    assert_cmpstr (restorable.tabs[0].path, CompareOperator.EQ, kept);
}

private void test_restoring_drops_the_active_tab_when_its_file_is_gone () {
    var folder = new_folder ();
    var kept = write_file (folder, "kept.rb");
    var session = parse ("""{ "folder": "%s", "active": "%s/gone.rb", "tabs": [ { "path": "%s" }, { "path": "%s/gone.rb" } ] }""".printf (folder, folder, kept, folder));

    var restorable = session.restorable ();

    assert_null (restorable.active);
}

private void test_restoring_keeps_the_active_tab_when_its_file_exists () {
    var folder = new_folder ();
    var kept = write_file (folder, "kept.rb");
    var session = parse ("""{ "folder": "%s", "active": "%s", "tabs": [ { "path": "%s" } ] }""".printf (folder, kept, kept));

    var restorable = session.restorable ();

    assert_cmpstr (restorable.active, CompareOperator.EQ, kept);
}

private void test_a_session_whose_folder_is_gone_cannot_be_restored () {
    var session = parse ("""{ "folder": "/no/such/folder", "tabs": [] }""");

    assert_null (session.restorable ());
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/saved-session/a_session_reads_its_folder_tabs_and_active_tab", test_a_session_reads_its_folder_tabs_and_active_tab);
    Test.add_func ("/models/saved-session/a_tab_reads_where_its_cursor_and_scroll_were", test_a_tab_reads_where_its_cursor_and_scroll_were);
    Test.add_func ("/models/saved-session/what_a_tab_leaves_out_starts_at_the_top_as_a_permanent_tab", test_what_a_tab_leaves_out_starts_at_the_top_as_a_permanent_tab);
    Test.add_func ("/models/saved-session/a_session_with_no_tabs_and_no_active_tab_is_a_folder_alone", test_a_session_with_no_tabs_and_no_active_tab_is_a_folder_alone);
    Test.add_func ("/models/saved-session/a_session_written_reads_back_the_same", test_a_session_written_reads_back_the_same);
    Test.add_func ("/models/saved-session/text_that_is_not_json_is_invalid", test_text_that_is_not_json_is_invalid);
    Test.add_func ("/models/saved-session/a_session_that_is_not_an_object_is_invalid", test_a_session_that_is_not_an_object_is_invalid);
    Test.add_func ("/models/saved-session/a_session_without_a_folder_is_invalid", test_a_session_without_a_folder_is_invalid);
    Test.add_func ("/models/saved-session/a_tab_without_a_path_is_invalid_and_says_which", test_a_tab_without_a_path_is_invalid_and_says_which);
    Test.add_func ("/models/saved-session/a_tab_with_a_line_that_is_not_a_number_is_invalid", test_a_tab_with_a_line_that_is_not_a_number_is_invalid);
    Test.add_func ("/models/saved-session/tabs_that_are_not_an_array_are_invalid", test_tabs_that_are_not_an_array_are_invalid);
    Test.add_func ("/models/saved-session/restoring_keeps_only_the_tabs_whose_files_still_exist", test_restoring_keeps_only_the_tabs_whose_files_still_exist);
    Test.add_func ("/models/saved-session/restoring_drops_the_active_tab_when_its_file_is_gone", test_restoring_drops_the_active_tab_when_its_file_is_gone);
    Test.add_func ("/models/saved-session/restoring_keeps_the_active_tab_when_its_file_exists", test_restoring_keeps_the_active_tab_when_its_file_exists);
    Test.add_func ("/models/saved-session/a_session_whose_folder_is_gone_cannot_be_restored", test_a_session_whose_folder_is_gone_cannot_be_restored);
    Test.run ();
}
