private string make_temp_file (string content) {
    string path = Path.build_filename (
        Environment.get_tmp_dir (),
        "codi-gtk-editor-controller-test-%u-%u".printf (Random.next_int (), Random.next_int ())
    );

    try {
        FileUtils.set_contents (path, content);
    } catch (Error e) {
        error ("failed to create fixture file: %s", e.message);
    }

    return path;
}

private string make_invalid_utf8_file () {
    string path = Path.build_filename (
        Environment.get_tmp_dir (),
        "codi-gtk-editor-controller-test-%u-%u".printf (Random.next_int (), Random.next_int ())
    );

    uint8[] invalid_bytes = { 0xff, 0xfe, 0x00, 0x01 };
    try {
        FileUtils.set_contents (path, (string) invalid_bytes, invalid_bytes.length);
    } catch (Error e) {
        error ("failed to create fixture file: %s", e.message);
    }

    return path;
}

/**
 * Drains any pending main-context sources (e.g. the idle callback that
 * completes an async call with no real yield point) so a signal handler
 * that fires an async operation with `.begin ()` has settled by the time
 * this returns.
 */
private void pump_loop () {
    var context = MainContext.default ();
    while (context.iteration (false)) {
        // keep draining
    }
}

private void test_open_as_preview_reuses_preview_slot () throws Error {
    string path_a = make_temp_file ("a content");
    string path_b = make_temp_file ("b content");

    try {
        var tab_bar_view = new FakeTabBarView ();
        var editor_view = new FakeEditorView ();
        var controller = new EditorController (tab_bar_view, editor_view);

        controller.open (path_a, false);
        assert_true (tab_bar_view.open_paths.length == 1);
        assert_cmpstr (tab_bar_view.active_path, CompareOperator.EQ, path_a);
        assert_true (tab_bar_view.preview_flags[path_a]);
        assert_cmpstr (editor_view.text, CompareOperator.EQ, "a content");

        controller.open (path_b, false);
        assert_true (tab_bar_view.open_paths.length == 1);
        assert_false (tab_bar_view.open_paths.find_with_equal_func (path_a, str_equal));
        assert_true (tab_bar_view.open_paths.find_with_equal_func (path_b, str_equal));
        assert_cmpstr (tab_bar_view.active_path, CompareOperator.EQ, path_b);
        assert_true (tab_bar_view.preview_flags[path_b]);
        assert_cmpstr (editor_view.text, CompareOperator.EQ, "b content");
    } finally {
        FileUtils.remove (path_a);
        FileUtils.remove (path_b);
    }
}

private void test_open_as_permanent_creates_separate_tab () throws Error {
    string preview_path = make_temp_file ("preview content");
    string permanent_path = make_temp_file ("permanent content");

    try {
        var tab_bar_view = new FakeTabBarView ();
        var editor_view = new FakeEditorView ();
        var controller = new EditorController (tab_bar_view, editor_view);

        controller.open (preview_path, false);
        controller.open (permanent_path, true);

        assert_true (tab_bar_view.open_paths.length == 2);
        assert_false (tab_bar_view.preview_flags[permanent_path]);
        assert_cmpstr (tab_bar_view.active_path, CompareOperator.EQ, permanent_path);
    } finally {
        FileUtils.remove (preview_path);
        FileUtils.remove (permanent_path);
    }
}

private void test_double_click_promotes_preview_tab () throws Error {
    string path = make_temp_file ("content");

    try {
        var tab_bar_view = new FakeTabBarView ();
        var editor_view = new FakeEditorView ();
        var controller = new EditorController (tab_bar_view, editor_view);

        controller.open (path, false);
        assert_true (tab_bar_view.preview_flags[path]);

        tab_bar_view.double_click_tab (path);
        assert_false (tab_bar_view.preview_flags[path]);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_editing_preview_promotes_and_marks_modified () throws Error {
    string path = make_temp_file ("original");

    try {
        var tab_bar_view = new FakeTabBarView ();
        var editor_view = new FakeEditorView ();
        var controller = new EditorController (tab_bar_view, editor_view);

        controller.open (path, false);
        assert_true (tab_bar_view.preview_flags[path]);
        assert_false (tab_bar_view.modified_flags[path]);

        editor_view.edit_text ("changed");

        assert_false (tab_bar_view.preview_flags[path]);
        assert_true (tab_bar_view.modified_flags[path]);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_reopening_same_path_activates_without_duplicating () throws Error {
    string path = make_temp_file ("content");

    try {
        var tab_bar_view = new FakeTabBarView ();
        var editor_view = new FakeEditorView ();
        var controller = new EditorController (tab_bar_view, editor_view);

        controller.open (path, false);
        controller.open (path, false);

        assert_true (tab_bar_view.open_paths.length == 1);
        assert_cmpstr (tab_bar_view.active_path, CompareOperator.EQ, path);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_close_clean_tab_closes_immediately () throws Error {
    string path = make_temp_file ("content");

    try {
        var tab_bar_view = new FakeTabBarView ();
        var editor_view = new FakeEditorView ();
        var controller = new EditorController (tab_bar_view, editor_view);

        controller.open (path, true);
        tab_bar_view.request_close (path);
        pump_loop ();

        assert_false (tab_bar_view.open_paths.find_with_equal_func (path, str_equal));
        assert_null (tab_bar_view.active_path);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_close_dirty_tab_save_choice_saves_and_closes () throws Error {
    string path = make_temp_file ("original");

    try {
        var tab_bar_view = new FakeTabBarView ();
        var editor_view = new FakeEditorView ();
        var controller = new EditorController (tab_bar_view, editor_view);

        controller.open (path, true);
        editor_view.edit_text ("changed");

        tab_bar_view.next_discard_choice = DiscardChoice.SAVE;
        tab_bar_view.request_close (path);
        pump_loop ();

        assert_false (tab_bar_view.open_paths.find_with_equal_func (path, str_equal));

        string on_disk;
        FileUtils.get_contents (path, out on_disk);
        assert_cmpstr (on_disk, CompareOperator.EQ, "changed");
    } finally {
        FileUtils.remove (path);
    }
}

private void test_close_dirty_tab_discard_choice_closes_without_saving () throws Error {
    string path = make_temp_file ("original");

    try {
        var tab_bar_view = new FakeTabBarView ();
        var editor_view = new FakeEditorView ();
        var controller = new EditorController (tab_bar_view, editor_view);

        controller.open (path, true);
        editor_view.edit_text ("changed");

        tab_bar_view.next_discard_choice = DiscardChoice.DISCARD;
        tab_bar_view.request_close (path);
        pump_loop ();

        assert_false (tab_bar_view.open_paths.find_with_equal_func (path, str_equal));

        string on_disk;
        FileUtils.get_contents (path, out on_disk);
        assert_cmpstr (on_disk, CompareOperator.EQ, "original");
    } finally {
        FileUtils.remove (path);
    }
}

private void test_close_dirty_tab_cancel_choice_keeps_tab_open () throws Error {
    string path = make_temp_file ("original");

    try {
        var tab_bar_view = new FakeTabBarView ();
        var editor_view = new FakeEditorView ();
        var controller = new EditorController (tab_bar_view, editor_view);

        controller.open (path, true);
        editor_view.edit_text ("changed");

        tab_bar_view.next_discard_choice = DiscardChoice.CANCEL;
        tab_bar_view.request_close (path);
        pump_loop ();

        assert_true (tab_bar_view.open_paths.find_with_equal_func (path, str_equal));
        assert_true (tab_bar_view.modified_flags[path]);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_open_invalid_utf8_shows_placeholder () throws Error {
    string path = make_invalid_utf8_file ();

    try {
        var tab_bar_view = new FakeTabBarView ();
        var editor_view = new FakeEditorView ();
        var controller = new EditorController (tab_bar_view, editor_view);

        controller.open (path, true);

        assert_true (editor_view.showing_placeholder);
        assert_cmpstr (editor_view.text, CompareOperator.EQ, "");
    } finally {
        FileUtils.remove (path);
    }
}

private void test_save_active_saves_dirty_document () throws Error {
    string path = make_temp_file ("original");

    try {
        var tab_bar_view = new FakeTabBarView ();
        var editor_view = new FakeEditorView ();
        var controller = new EditorController (tab_bar_view, editor_view);

        controller.open (path, true);
        editor_view.edit_text ("changed");
        assert_true (tab_bar_view.modified_flags[path]);

        controller.save_active ();

        assert_false (tab_bar_view.modified_flags[path]);

        string on_disk;
        FileUtils.get_contents (path, out on_disk);
        assert_cmpstr (on_disk, CompareOperator.EQ, "changed");
    } finally {
        FileUtils.remove (path);
    }
}

private delegate void ThrowingTestFunc () throws Error;

private void run_test (owned ThrowingTestFunc test_func) {
    try {
        test_func ();
    } catch (Error e) {
        error ("unexpected error: %s", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/controllers/editor-controller/open_as_preview_reuses_preview_slot", () => {
        run_test (() => test_open_as_preview_reuses_preview_slot ());
    });
    Test.add_func ("/controllers/editor-controller/open_as_permanent_creates_separate_tab", () => {
        run_test (() => test_open_as_permanent_creates_separate_tab ());
    });
    Test.add_func ("/controllers/editor-controller/double_click_promotes_preview_tab", () => {
        run_test (() => test_double_click_promotes_preview_tab ());
    });
    Test.add_func ("/controllers/editor-controller/editing_preview_promotes_and_marks_modified", () => {
        run_test (() => test_editing_preview_promotes_and_marks_modified ());
    });
    Test.add_func ("/controllers/editor-controller/reopening_same_path_activates_without_duplicating", () => {
        run_test (() => test_reopening_same_path_activates_without_duplicating ());
    });
    Test.add_func ("/controllers/editor-controller/close_clean_tab_closes_immediately", () => {
        run_test (() => test_close_clean_tab_closes_immediately ());
    });
    Test.add_func ("/controllers/editor-controller/close_dirty_tab_save_choice_saves_and_closes", () => {
        run_test (() => test_close_dirty_tab_save_choice_saves_and_closes ());
    });
    Test.add_func ("/controllers/editor-controller/close_dirty_tab_discard_choice_closes_without_saving", () => {
        run_test (() => test_close_dirty_tab_discard_choice_closes_without_saving ());
    });
    Test.add_func ("/controllers/editor-controller/close_dirty_tab_cancel_choice_keeps_tab_open", () => {
        run_test (() => test_close_dirty_tab_cancel_choice_keeps_tab_open ());
    });
    Test.add_func ("/controllers/editor-controller/open_invalid_utf8_shows_placeholder", () => {
        run_test (() => test_open_invalid_utf8_shows_placeholder ());
    });
    Test.add_func ("/controllers/editor-controller/save_active_saves_dirty_document", () => {
        run_test (() => test_save_active_saves_dirty_document ());
    });

    return Test.run ();
}
