/**
 * `window.save_session` end to end, across two runs of the real app on
 * one data directory: the first links a folder, opens tabs, picks the
 * active one, moves its cursor and closes; the second, started bare,
 * has it all back. Also what a saved session never records.
 */

private const uint DISPLAY = 112;
private const string SAVING = """{ "window.save_session": true }""";

// 200 lines of ten characters each: line N starts at offset (N - 1) * 11.
private string long_text () {
    var text = new StringBuilder ();
    for (int i = 1; i <= 200; i++) {
        text.append_printf ("line %05d\n", i);
    }
    return text.str;
}

private string make_folder () throws Error {
    var folder = DirUtils.make_tmp ("opus-save-session-test-XXXXXX");
    FileUtils.set_contents (Path.build_filename (folder, "a.rb"), long_text ());
    FileUtils.set_contents (Path.build_filename (folder, "b.rb"), "b\n");
    FileUtils.set_contents (Path.build_filename (folder, "c.rb"), "c\n");
    return folder;
}

private SystemTestSession first_run (string? folder) throws Error {
    return new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder, SAVING);
}

private SystemTestSession second_run () throws Error {
    return new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, null, SAVING, true);
}

/** The open tabs are exactly `expected`, in any order: the listing has no order of its own. */
private void assert_tabs (SystemTestSession opus, string[] expected) throws Error {
    var tabs = opus.open_tabs ();
    assert_cmpint (tabs.length, CompareOperator.EQ, expected.length);
    foreach (unowned string path in expected) {
        assert_true (path in tabs);
    }
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/save_session/the_tabs_come_back", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            var first = first_run (folder);
            first.open_tab (a);
            first.open_tab (b);
            first.quit ();

            var second = second_run ();

            assert_tabs (second, { a, b });

            second.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/save_session/the_active_tab_comes_back_active", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            var c = Path.build_filename (folder, "c.rb");
            var first = first_run (folder);
            first.open_tab (a);
            first.open_tab (b);
            first.open_tab (c);
            first.open_tab (b);
            first.quit ();

            var second = second_run ();

            second.wait_for_active_tab (b);

            second.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/save_session/the_cursor_comes_back_where_it_was", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var first = first_run (folder);
            first.open_tab (a);
            first.set_cursor_offsets ({ 25 }, { 25 }); // line 3, column 3
            first.quit ();

            var second = second_run ();

            second.wait_for_active_tab (a);
            second.assert_cursors ({ { 25, 25 } });

            second.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/save_session/the_scroll_comes_back_where_it_was", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var first = first_run (folder);
            first.open_tab (a);
            go_to_line (first, 150);
            int top_before = wait_for_scroll (first);
            first.quit ();

            var second = second_run ();

            second.wait_for_active_tab (a);
            assert_cmpint (wait_for_scroll (second), CompareOperator.EQ, top_before);

            second.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/save_session/opening_the_same_folder_again_brings_its_tabs_back", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            var first = first_run (folder);
            first.open_tab (a);
            first.open_tab (b);
            first.quit ();

            var second = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder, SAVING, true);

            assert_tabs (second, { a, b });
            second.wait_for_active_tab (b);

            second.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/save_session/opening_another_folder_starts_a_session_of_its_own", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var first = first_run (folder);
            first.open_tab (a);
            first.quit ();

            var second = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, make_folder (), SAVING, true);

            assert_cmpint (second.open_tabs ().length, CompareOperator.EQ, 0);

            second.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/save_session/a_file_gone_between_runs_is_left_out", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            var first = first_run (folder);
            first.open_tab (a);
            first.open_tab (b);
            first.quit ();
            FileUtils.remove (b);

            var second = second_run ();

            assert_tabs (second, { a });

            second.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/save_session/an_untitled_tab_is_not_kept", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var first = first_run (folder);
            first.open_tab (a);
            first.new_file ();
            first.quit ();

            var second = second_run ();

            assert_tabs (second, { a });

            second.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/save_session/with_the_setting_off_nothing_comes_back", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var first = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            first.open_tab (a);
            first.quit ();

            var second = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, null, null, true);

            assert_cmpint (second.open_tabs ().length, CompareOperator.EQ, 0);

            second.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/save_session/a_lone_file_leaves_the_saved_session_alone", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var c = Path.build_filename (folder, "c.rb");
            var first = first_run (folder);
            first.open_tab (a);
            first.quit ();
            var lone = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, c, SAVING, true);
            lone.quit ();

            var third = second_run ();

            assert_tabs (third, { a });

            third.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/save_session/coming_back_to_a_tab_brings_its_scroll_back", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            var opus = first_run (folder);
            opus.open_tab (a);
            go_to_line (opus, 150);
            int top_before = wait_for_scroll (opus);
            opus.open_tab (b);

            opus.open_tab (a);

            assert_cmpint (wait_for_scroll (opus), CompareOperator.EQ, top_before);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}

/** The Command Bar's `:line` — the one way in that scrolls the editor to the cursor. */
private void go_to_line (SystemTestSession opus, int line) throws Error {
    opus.open_command_bar ();
    opus.command_bar_type (":%d".printf (line));
    opus.command_bar_accept ();
}

/** The first line showing once the editor has scrolled off the top — scrolling is deferred to the main loop, so it is polled for. */
private int wait_for_scroll (SystemTestSession opus) throws Error {
    int64 deadline = get_monotonic_time () + 5 * 1000 * 1000;
    int top = 1;
    while (get_monotonic_time () < deadline) {
        top = opus.top_line ();
        if (top > 1) {
            return top;
        }
        Thread.usleep (50 * 1000);
    }
    error ("the editor never scrolled off the top (top line still %d)", top);
}
