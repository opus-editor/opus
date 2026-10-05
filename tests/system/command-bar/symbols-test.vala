/**
 * The Command Bar's `#` list end to end through the real window: it
 * lists what the open file defines, shows the one under its cursor in
 * the editor without going there, and Return goes — all of it with no
 * folder open, which Ctrl+P no longer needs.
 */

private const uint DISPLAY = 109;

private const string HINT_WITHOUT_FOLDER = "Open a folder to search files\n: Go to line\n# Go to symbol\n> Run commands";
private const string HINT_WITH_FOLDER = "Search files\n: Go to line\n# Go to symbol\n> Run commands";

// Where each name is: `Cart` on line 1, `total` on line 2 (offset 17), `clear` on line 6 (offset 42).
private const string CART = "class Cart\n  def total\n    1\n  end\n\n  def clear\n    2\n  end\nend\n";

private string write_file (string name, string content) throws Error {
    var folder = DirUtils.make_tmp ("opus-symbols-test-XXXXXX");
    var path = Path.build_filename (folder, name);
    FileUtils.set_contents (path, content);
    return path;
}

/** Opus with `cart.rb` open and painted — so its tree is there to ask — and no folder. */
private SystemTestSession opus_with_cart () throws Error {
    var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
    opus.open_tab (write_file ("cart.rb", CART));
    opus.wait_for_syntax_style (17, "function");
    return opus;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/symbols/the_bar_opens_with_no_folder_and_says_what_it_can_do", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);

            opus.open_command_bar ();

            assert_cmpstr (opus.command_bar_empty_message (), CompareOperator.EQ, HINT_WITHOUT_FOLDER);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/with_a_folder_and_nothing_recent_the_bar_says_what_it_can_do", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, DirUtils.make_tmp ("opus-symbols-test-XXXXXX"));

            opus.open_command_bar ();

            assert_cmpstr (opus.command_bar_empty_message (), CompareOperator.EQ, HINT_WITH_FOLDER);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/a_line_is_reached_with_no_folder", () => {
        try {
            var opus = opus_with_cart ();
            opus.open_command_bar ();
            opus.command_bar_type (":3");

            opus.command_bar_accept ();

            opus.assert_cursors ({ { 23, 23 } });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/a_hash_lists_what_the_file_defines", () => {
        try {
            var opus = opus_with_cart ();
            opus.open_command_bar ();

            opus.command_bar_type ("#");

            assert_cmpstrv (opus.command_bar_items (), { "1:6", "2:6", "6:6" });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/typing_narrows_the_symbols", () => {
        try {
            var opus = opus_with_cart ();
            opus.open_command_bar ();

            opus.command_bar_type ("#clear");

            assert_cmpstrv (opus.command_bar_items (), { "6:6" });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/return_takes_the_cursor_to_the_symbols_name", () => {
        try {
            var opus = opus_with_cart ();
            opus.open_command_bar ();
            opus.command_bar_type ("#clear");

            opus.command_bar_accept ();

            opus.assert_cursors ({ { 42, 42 } });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/the_symbol_under_the_lists_cursor_is_shown_in_the_editor", () => {
        try {
            var opus = opus_with_cart ();
            opus.open_command_bar ();

            opus.command_bar_type ("#clear");

            assert_cmpint (opus.previewed_line (), CompareOperator.EQ, 6);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/showing_a_symbol_does_not_move_the_cursor", () => {
        try {
            var opus = opus_with_cart ();
            opus.set_cursor_offsets ({ 3 }, { 3 });
            opus.open_command_bar ();

            opus.command_bar_type ("#clear");

            opus.assert_cursors ({ { 3, 3 } });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/the_list_starts_on_the_symbol_the_cursor_is_in", () => {
        try {
            var opus = opus_with_cart ();
            opus.set_cursor_offsets ({ 50 }, { 50 });
            opus.open_command_bar ();

            opus.command_bar_type ("#");

            assert_cmpint (opus.previewed_line (), CompareOperator.EQ, 6);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/escape_stops_showing_the_symbol_and_leaves_the_cursor", () => {
        try {
            var opus = opus_with_cart ();
            opus.set_cursor_offsets ({ 3 }, { 3 });
            opus.open_command_bar ();
            opus.command_bar_type ("#clear");

            opus.command_bar_close ();

            assert_cmpint (opus.previewed_line (), CompareOperator.EQ, 0);
            opus.assert_cursors ({ { 3, 3 } });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/a_symbol_gone_to_is_no_longer_tinted", () => {
        try {
            var opus = opus_with_cart ();
            opus.open_command_bar ();
            opus.command_bar_type ("#clear");

            opus.command_bar_accept ();

            assert_cmpint (opus.previewed_line (), CompareOperator.EQ, 0);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/leaving_the_symbols_for_another_list_stops_showing_one", () => {
        try {
            var opus = opus_with_cart ();
            opus.open_command_bar ();
            opus.command_bar_type ("#clear");

            opus.command_bar_type (">");

            assert_cmpint (opus.previewed_line (), CompareOperator.EQ, 0);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/with_no_tab_open_the_list_says_to_open_a_file", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_command_bar ();

            opus.command_bar_type ("#");

            assert_cmpint (opus.command_bar_items ().length, CompareOperator.EQ, 0);
            assert_cmpstr (opus.command_bar_empty_message (), CompareOperator.EQ, "Open a file to go to a symbol");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/a_language_with_no_symbols_says_so", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (write_file ("data.json", "{ \"port\": 80 }\n"));
            opus.open_command_bar ();

            opus.command_bar_type ("#");

            assert_cmpstr (opus.command_bar_empty_message (), CompareOperator.EQ, "No symbols for this language");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/symbols/a_file_given_a_language_by_hand_lists_its_symbols", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.new_file ();
            opus.editor_write ("def greet\nend\n");
            opus.open_commands ();
            opus.command_bar_type (">set language");
            opus.command_bar_accept ();
            opus.command_bar_type ("ruby");
            opus.command_bar_accept ();
            opus.open_command_bar ();

            opus.command_bar_type ("#");

            assert_cmpstrv (opus.command_bar_items (), { "1:4" });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
