/**
 * Auto-close end to end through the real window, one cursor
 * (docs/AUTO_CLOSE.md §2, §5, §8): an opener inserts its closer, the
 * closer Opus inserted is skipped, one from the file is not, and the
 * settings and Insert mode switch it off. The rules themselves are
 * tested in tests/models/auto-close-test; this is the key-press
 * pipeline down to the real buffer.
 */
private const uint DISPLAY = 140;

private SystemTestSession open (string? settings_json = null, string? folder = null) throws Error {
    var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder, settings_json);
    if (folder == null) {
        opus.new_file ();
    }
    return opus;
}

/** A folder holding `name` with `contents`; returns the file's path. */
private string write_fixture (string name, string contents) throws Error {
    var folder = DirUtils.make_tmp ("opus-auto-close-pairs-test-XXXXXX");
    var path = Path.build_filename (folder, name);
    FileUtils.set_contents (path, contents);
    return path;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/auto_close/pairs/an_opener_inserts_its_closer_with_the_caret_between", () => {
        try {
            var opus = open ();

            opus.type ("(");

            opus.assert_editor_text ("()");
            opus.assert_cursors ({ {1, 1} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/pairs/nested_openers_each_close_before_the_closer_already_there", () => {
        try {
            var opus = open ();

            opus.type ("([{");

            opus.assert_editor_text ("([{}])");
            opus.assert_cursors ({ {3, 3} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/pairs/a_different_closer_typed_inside_is_inserted_not_skipped", () => {
        try {
            var opus = open ();

            opus.type ("{)");

            opus.assert_editor_text ("{)}");
            opus.assert_cursors ({ {2, 2} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/pairs/typing_the_closer_opus_inserted_skips_it", () => {
        try {
            var opus = open ();

            opus.type ("(a)");

            opus.assert_editor_text ("(a)");
            opus.assert_cursors ({ {3, 3} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/pairs/a_closer_already_in_the_file_is_inserted", () => {
        try {
            var opus = open ();
            opus.editor_write ("(a)");
            opus.set_cursors ({ {0, 2} });

            opus.type (")");

            opus.assert_editor_text ("(a))");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/pairs/an_opener_before_a_word_stays_alone", () => {
        try {
            var opus = open ();
            opus.editor_write ("value");
            opus.set_cursors ({ {0, 0} });

            opus.type ("(");

            opus.assert_editor_text ("(value");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/pairs/an_opener_before_a_closer_still_closes", () => {
        try {
            var opus = open ();
            opus.editor_write (")");
            opus.set_cursors ({ {0, 0} });

            opus.type ("(");

            opus.assert_editor_text ("())");
            opus.assert_cursors ({ {1, 1} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/pairs/the_brackets_setting_leaves_quotes_closing", () => {
        try {
            var opus = open ("""{ "editor.auto_close.brackets": false }""");

            opus.type ("(\"");

            opus.assert_editor_text ("(\"\"");
            opus.assert_cursors ({ {2, 2} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/pairs/the_quotes_setting_leaves_brackets_closing", () => {
        try {
            var opus = open ("""{ "editor.auto_close.quotes": false }""");

            opus.type ("\"(");

            opus.assert_editor_text ("\"()");
            opus.assert_cursors ({ {2, 2} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/pairs/insert_mode_types_plainly_over_the_text", () => {
        try {
            var opus = open ();
            opus.editor_write ("x");
            opus.set_cursors ({ {0, 0} });

            opus.type_cmd ("insert");
            opus.type ("(");

            opus.assert_editor_text ("(");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/pairs/a_block_comment_closes_on_its_second_character", () => {
        try {
            var path = write_fixture ("example.c", "int x = 1; ");
            var opus = open (null, Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {0, 11} });

            opus.type ("/*");

            opus.assert_editor_text ("int x = 1; /* */");
            opus.assert_cursors ({ {13, 13} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
