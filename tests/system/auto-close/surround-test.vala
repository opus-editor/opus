/**
 * Auto-surround end to end (docs/AUTO_CLOSE.md §7): typing a pair's
 * open or close over a selection wraps it and keeps it selected, undo
 * unwraps it, and what doesn't surround replaces the selection as
 * typing always has.
 */
private const uint DISPLAY = 144;

private SystemTestSession open (string? settings_json = null, string? folder = null) throws Error {
    var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder, settings_json);
    if (folder == null) {
        opus.new_file ();
    }
    return opus;
}

/** A folder holding `name` with `contents`; returns the file's path. */
private string write_fixture (string name, string contents) throws Error {
    var folder = DirUtils.make_tmp ("opus-auto-close-surround-test-XXXXXX");
    var path = Path.build_filename (folder, name);
    FileUtils.set_contents (path, contents);
    return path;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/auto_close/surround/an_opener_wraps_the_selection_and_keeps_it", () => {
        try {
            var opus = open ();
            opus.editor_write ("foo");
            opus.set_selections ({ {0, 0, 3} });

            opus.type ("(");

            opus.assert_editor_text ("(foo)");
            opus.assert_cursors ({ {1, 4} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/surround/a_closer_wraps_the_selection_too", () => {
        try {
            var opus = open ();
            opus.editor_write ("foo");
            opus.set_selections ({ {0, 0, 3} });

            opus.type (")");

            opus.assert_editor_text ("(foo)");
            opus.assert_cursors ({ {1, 4} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/surround/wrapping_twice_nests_and_keeps_the_selection", () => {
        try {
            var opus = open ();
            opus.editor_write ("foo");
            opus.set_selections ({ {0, 0, 3} });

            opus.type ("((");

            opus.assert_editor_text ("((foo))");
            opus.assert_cursors ({ {2, 5} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/surround/one_undo_unwraps_and_restores_the_selection", () => {
        try {
            var opus = open ();
            opus.editor_write ("foo");
            opus.set_selections ({ {0, 0, 3} });

            opus.type ("(");
            opus.type_cmd ("undo");

            opus.assert_editor_text ("foo");
            opus.assert_cursors ({ {0, 3} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/surround/a_quote_wraps_the_selection", () => {
        try {
            var opus = open ();
            opus.editor_write ("foo");
            opus.set_selections ({ {0, 0, 3} });

            opus.type ("\"");

            opus.assert_editor_text ("\"foo\"");
            opus.assert_cursors ({ {1, 4} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/surround/the_first_character_of_a_longer_pair_replaces_the_selection", () => {
        try {
            var path = write_fixture ("example.c", "foo");
            var opus = open (null, Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_selections ({ {0, 0, 3} });

            opus.type ("/");

            opus.assert_editor_text ("/");
            opus.assert_cursors ({ {1, 1} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/surround/the_surround_setting_off_replaces_the_selection", () => {
        try {
            var opus = open ("""{ "editor.auto_close.surround_selection": false }""");
            opus.editor_write ("foo");
            opus.set_selections ({ {0, 0, 3} });

            opus.type ("(");

            opus.assert_editor_text ("(");
            opus.assert_cursors ({ {1, 1} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
