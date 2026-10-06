private string new_store_path () {
    try {
        return Path.build_filename (DirUtils.make_tmp ("opus-session-store-test-XXXXXX"), "opus", "session.json");
    } catch (Error e) {
        error ("%s", e.message);
    }
}

/** A session on a folder that exists, so it survives SavedSession.restorable(). */
private SavedSession a_session () {
    var tabs = new GenericArray<SessionTab> ();
    return new SavedSession (Environment.get_tmp_dir (), tabs, null);
}

private bool file_exists (string path) {
    return FileUtils.test (path, FileTest.IS_REGULAR);
}

/** Spins the main loop until SessionStore's own delayed write has had its chance. */
private void let_the_delay_pass () {
    var loop = new MainLoop ();
    Timeout.add (SessionStore.WRITE_DELAY_MSEC * 2, () => {
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();
}

private void test_a_recorded_session_is_written_after_the_delay () {
    var path = new_store_path ();
    var store = new SessionStore (true, path);

    store.record (a_session ());

    assert_false (file_exists (path));
    let_the_delay_pass ();
    assert_true (file_exists (path));
}

private void test_what_was_written_loads_back () {
    var path = new_store_path ();
    var store = new SessionStore (true, path);
    var tabs = new GenericArray<SessionTab> ();
    tabs.add (new SessionTab (Path.build_filename (Environment.get_tmp_dir (), "a.rb"), 3, 1, 2, false));
    store.record (new SavedSession (Environment.get_tmp_dir (), tabs, null));
    store.flush ();

    var loaded = new SessionStore (true, path).load ();

    assert_cmpstr (loaded.folder, CompareOperator.EQ, Environment.get_tmp_dir ());
}

private void test_a_burst_of_records_is_one_write_of_the_last () {
    var path = new_store_path ();
    var store = new SessionStore (true, path);
    var tabs = new GenericArray<SessionTab> ();
    tabs.add (new SessionTab ("/p/last.rb", 1, 0, 1, false));

    store.record (new SavedSession (Environment.get_tmp_dir (), new GenericArray<SessionTab> (), null));
    store.record (new SavedSession (Environment.get_tmp_dir (), tabs, null));
    let_the_delay_pass ();

    string json;
    try {
        FileUtils.get_contents (path, out json);
    } catch (FileError e) {
        error ("%s", e.message);
    }
    assert_true (json.contains ("/p/last.rb"));
}

private void test_flushing_writes_at_once () {
    var path = new_store_path ();
    var store = new SessionStore (true, path);
    store.record (a_session ());

    store.flush ();

    assert_true (file_exists (path));
}

private void test_flushing_with_nothing_recorded_writes_nothing () {
    var path = new_store_path ();
    var store = new SessionStore (true, path);

    store.flush ();

    assert_false (file_exists (path));
}

private void test_with_the_setting_off_nothing_is_written () {
    var path = new_store_path ();
    var store = new SessionStore (false, path);

    store.record (a_session ());
    store.flush ();

    assert_false (file_exists (path));
}

private void test_with_the_setting_off_nothing_loads () {
    var path = new_store_path ();
    new SessionStore (true, path).record (a_session ());

    var loaded = new SessionStore (false, path).load ();

    assert_null (loaded);
}

private void test_starting_with_the_setting_off_removes_a_leftover_file () {
    var path = new_store_path ();
    var on = new SessionStore (true, path);
    on.record (a_session ());
    on.flush ();

    new SessionStore (false, path);

    assert_false (file_exists (path));
}

private void test_clearing_removes_the_file_and_what_was_pending () {
    var path = new_store_path ();
    var store = new SessionStore (true, path);
    store.record (a_session ());
    store.flush ();
    store.record (a_session ());

    store.clear ();
    let_the_delay_pass ();

    assert_false (file_exists (path));
}

private void test_turning_the_setting_on_keeps_the_session_given_right_away () {
    var path = new_store_path ();
    var store = new SessionStore (false, path);

    store.apply_setting (true, a_session ());

    assert_true (store.enabled);
    assert_true (file_exists (path));
}

private void test_turning_the_setting_on_with_no_session_keeps_nothing_yet () {
    var path = new_store_path ();
    var store = new SessionStore (false, path);

    store.apply_setting (true, null);

    assert_true (store.enabled);
    assert_false (file_exists (path));
}

private void test_turning_the_setting_off_removes_the_file () {
    var path = new_store_path ();
    var store = new SessionStore (true, path);
    store.record (a_session ());
    store.flush ();

    store.apply_setting (false, a_session ());

    assert_false (store.enabled);
    assert_false (file_exists (path));
}

private void test_an_unchanged_setting_changes_nothing () {
    var path = new_store_path ();
    var store = new SessionStore (true, path);
    store.record (a_session ());
    store.flush ();

    store.apply_setting (true, null);

    assert_true (file_exists (path));
}

private void test_a_missing_file_loads_nothing () {
    var store = new SessionStore (true, new_store_path ());

    assert_null (store.load ());
}

private void test_a_broken_file_loads_nothing () {
    var path = new_store_path ();
    DirUtils.create_with_parents (Path.get_dirname (path), 0700);
    try {
        FileUtils.set_contents (path, "{ broken");
    } catch (FileError e) {
        error ("%s", e.message);
    }

    var loaded = new SessionStore (true, path).load ();

    assert_null (loaded);
}

private void test_a_session_whose_folder_is_gone_loads_nothing () {
    var path = new_store_path ();
    var store = new SessionStore (true, path);
    store.record (new SavedSession ("/no/such/folder", new GenericArray<SessionTab> (), null));
    store.flush ();

    assert_null (store.load ());
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/session-store/a_recorded_session_is_written_after_the_delay", test_a_recorded_session_is_written_after_the_delay);
    Test.add_func ("/models/session-store/what_was_written_loads_back", test_what_was_written_loads_back);
    Test.add_func ("/models/session-store/a_burst_of_records_is_one_write_of_the_last", test_a_burst_of_records_is_one_write_of_the_last);
    Test.add_func ("/models/session-store/flushing_writes_at_once", test_flushing_writes_at_once);
    Test.add_func ("/models/session-store/flushing_with_nothing_recorded_writes_nothing", test_flushing_with_nothing_recorded_writes_nothing);
    Test.add_func ("/models/session-store/with_the_setting_off_nothing_is_written", test_with_the_setting_off_nothing_is_written);
    Test.add_func ("/models/session-store/with_the_setting_off_nothing_loads", test_with_the_setting_off_nothing_loads);
    Test.add_func ("/models/session-store/starting_with_the_setting_off_removes_a_leftover_file", test_starting_with_the_setting_off_removes_a_leftover_file);
    Test.add_func ("/models/session-store/clearing_removes_the_file_and_what_was_pending", test_clearing_removes_the_file_and_what_was_pending);
    Test.add_func ("/models/session-store/turning_the_setting_on_keeps_the_session_given_right_away", test_turning_the_setting_on_keeps_the_session_given_right_away);
    Test.add_func ("/models/session-store/turning_the_setting_on_with_no_session_keeps_nothing_yet", test_turning_the_setting_on_with_no_session_keeps_nothing_yet);
    Test.add_func ("/models/session-store/turning_the_setting_off_removes_the_file", test_turning_the_setting_off_removes_the_file);
    Test.add_func ("/models/session-store/an_unchanged_setting_changes_nothing", test_an_unchanged_setting_changes_nothing);
    Test.add_func ("/models/session-store/a_missing_file_loads_nothing", test_a_missing_file_loads_nothing);
    Test.add_func ("/models/session-store/a_broken_file_loads_nothing", test_a_broken_file_loads_nothing);
    Test.add_func ("/models/session-store/a_session_whose_folder_is_gone_loads_nothing", test_a_session_whose_folder_is_gone_loads_nothing);
    Test.run ();
}
