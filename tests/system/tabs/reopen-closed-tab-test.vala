/**
 * Ctrl+Shift+T end to end through the real window: the file tabs
 * closed in a window come back latest first, each with its cursor where
 * it was; one already open again, one gone from disk, and an untitled
 * one are passed over.
 */

private const uint DISPLAY = 111;

private string make_folder () throws Error {
    var folder = DirUtils.make_tmp ("opus-reopen-closed-test-XXXXXX");
    FileUtils.set_contents (Path.build_filename (folder, "a.rb"), "first\nsecond\nthird\n");
    FileUtils.set_contents (Path.build_filename (folder, "b.rb"), "b\n");
    return folder;
}


/** The open tabs, sorted: the listing has no order of its own. */
private string[] sorted_tabs (SystemTestSession opus) throws Error {
    var tabs = opus.open_tabs ();
    GLib.qsort_with_data<string> (tabs, sizeof (string), (a, b) => strcmp (a, b));
    return tabs;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/reopen_closed_tab/the_latest_closed_tab_comes_back", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (a);
            opus.close_tab (a);

            opus.reopen_closed_tab ();

            opus.wait_for_active_tab (a);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/reopen_closed_tab/pressing_again_walks_back_through_the_closed_tabs", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (a);
            opus.open_tab (b);
            opus.close_tab (a);
            opus.close_tab (b);

            opus.reopen_closed_tab ();
            opus.wait_for_active_tab (b);
            opus.reopen_closed_tab ();

            opus.wait_for_active_tab (a);
            assert_cmpstrv (sorted_tabs (opus), { a, b });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/reopen_closed_tab/the_cursor_comes_back_where_it_was", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (a);
            opus.set_cursor_offsets ({ 9 }, { 9 }); // "second" + 3
            opus.close_tab (a);

            opus.reopen_closed_tab ();

            opus.wait_for_active_tab (a);
            opus.assert_cursors ({ { 9, 9 } });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/reopen_closed_tab/nothing_closed_changes_nothing", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (a);

            opus.reopen_closed_tab ();

            assert_cmpstrv (opus.open_tabs (), { a });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/reopen_closed_tab/a_file_open_again_is_passed_over_for_the_one_before_it", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (a);
            opus.close_tab (a);
            opus.open_tab (b);
            opus.close_tab (b);
            opus.open_tab (b);

            opus.reopen_closed_tab ();

            opus.wait_for_active_tab (a);
            assert_cmpstrv (sorted_tabs (opus), { a, b });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/reopen_closed_tab/a_file_gone_from_disk_is_passed_over", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (a);
            opus.open_tab (b);
            opus.close_tab (a);
            opus.close_tab (b);
            FileUtils.remove (b);

            opus.reopen_closed_tab ();

            opus.wait_for_active_tab (a);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/reopen_closed_tab/an_untitled_tab_does_not_come_back", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (a);
            opus.close_tab (a);
            opus.new_file ();
            opus.close_tab ("Untitled-1");

            opus.reopen_closed_tab ();

            opus.wait_for_active_tab (a);
            assert_cmpstrv (opus.open_tabs (), { a });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
