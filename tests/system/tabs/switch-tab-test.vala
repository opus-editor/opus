/**
 * Switching tabs end to end through the real window: each tab is its
 * own editor kept alive, so coming back shows it as it was left, at
 * once — no deferred scroll — and what happens in one tab stays there.
 * Also the preview rule and that a closed tab is really gone.
 */

private const uint DISPLAY = 113;

private string long_text () {
    var text = new StringBuilder ();
    for (int i = 1; i <= 200; i++) {
        text.append_printf ("line %05d\n", i);
    }
    return text.str;
}

private string make_folder () throws Error {
    var folder = DirUtils.make_tmp ("opus-switch-tab-test-XXXXXX");
    FileUtils.set_contents (Path.build_filename (folder, "a.rb"), long_text ());
    FileUtils.set_contents (Path.build_filename (folder, "b.rb"), "def b\nend\n");
    FileUtils.set_contents (Path.build_filename (folder, "c.rb"), "c\n");
    return folder;
}

/** The Command Bar's `:line` — the one way in that scrolls the editor to the cursor. */
private void go_to_line (SystemTestSession opus, int line) throws Error {
    opus.open_command_bar ();
    opus.command_bar_type (":%d".printf (line));
    opus.command_bar_accept ();
}

/** The first line showing once the editor has scrolled off the top — the go-to-line reveal is deferred to the main loop, so it is polled for. */
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

    Test.add_func ("/system/switch_tab/coming_back_shows_the_tab_where_it_was_at_once", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_tab (a);
            go_to_line (opus, 150);
            int top_before = wait_for_scroll (opus);
            opus.open_tab (b);

            opus.open_tab (a);

            // Read right away, no polling: the scroll is in the widget, not re-done.
            assert_cmpint (opus.top_line (), CompareOperator.EQ, top_before);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/switch_tab/each_tab_keeps_its_own_text_and_cursor", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_tab (a);
            opus.set_cursor_offsets ({ 7 }, { 7 });
            opus.open_tab (b);
            opus.set_cursor_offsets ({ 3 }, { 3 });
            opus.type ("x");

            opus.open_tab (a);

            opus.assert_cursors ({ { 7, 7 } });
            assert_true (opus.active_text ().has_prefix ("line 00001\n"));
            opus.open_tab (b);
            opus.assert_editor_text ("defx b\nend\n");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/switch_tab/the_highlighting_is_still_right_after_coming_back", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_tab (b);
            opus.wait_for_syntax_style (4, "function");
            opus.open_tab (a);

            opus.open_tab (b);

            assert_cmpstr (opus.syntax_style_at (4), CompareOperator.EQ, "function");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/switch_tab/the_find_query_follows_to_the_next_tab", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_tab (a);
            opus.search_set_text ("line 0001");

            opus.open_tab (b);
            opus.search_set_text ("end");

            opus.open_tab (a);
            // Still searching for "end" in a: it has none.
            opus.assert_search_position (0, 0);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/switch_tab/a_closed_tab_is_taken_apart", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_tab (a);
            int before = opus.live_tabs ();
            opus.open_tab (b);
            assert_cmpint (opus.live_tabs (), CompareOperator.EQ, before + 1);

            opus.close_tab (b);

            assert_cmpint (opus.live_tabs (), CompareOperator.EQ, before);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/switch_tab/a_second_preview_replaces_the_first", () => {
        try {
            var folder = make_folder ();
            var b = Path.build_filename (folder, "b.rb");
            var c = Path.build_filename (folder, "c.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_preview_tab (b);

            opus.open_preview_tab (c);

            assert_tabs (opus, { c });
            opus.assert_active_tab (c);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/switch_tab/typing_in_a_preview_makes_it_permanent", () => {
        try {
            var folder = make_folder ();
            var b = Path.build_filename (folder, "b.rb");
            var c = Path.build_filename (folder, "c.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_preview_tab (b);
            opus.type ("x");

            opus.open_preview_tab (c);

            assert_tabs (opus, { b, c });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/switch_tab/opening_a_preview_permanently_keeps_it", () => {
        try {
            var folder = make_folder ();
            var b = Path.build_filename (folder, "b.rb");
            var c = Path.build_filename (folder, "c.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_preview_tab (b);
            opus.open_tab (b);

            opus.open_preview_tab (c);

            assert_tabs (opus, { b, c });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
