/**
 * Text that arrives through the input method rather than as a key —
 * what a dead key or a compose sequence resolves into (`ã` on a layout
 * where `~` is dead, `` ` `` on one where it waits for a space), or a
 * word from a CJK input method. What is still being composed shows at
 * every cursor as marked text; what is committed is typed like any
 * key: at every cursor, over every selection, auto-closed, undone
 * together with the typing around it (see CodeEditorComposition).
 */
private const uint DISPLAY = 146;

private SystemTestSession open (string? folder = null) throws Error {
    var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
    if (folder == null) {
        opus.new_file ();
    }
    return opus;
}

/** A folder holding `name` with `contents`; returns the file's path. */
private string write_fixture (string name, string contents) throws Error {
    var folder = DirUtils.make_tmp ("opus-input-method-test-XXXXXX");
    var path = Path.build_filename (folder, name);
    FileUtils.set_contents (path, contents);
    return path;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/input_method/a_committed_character_lands_at_every_cursor", () => {
        try {
            var opus = open ();
            opus.editor_write ("a\na\na");
            opus.set_cursors ({ {0, 1}, {1, 1}, {2, 1} });

            opus.commit ("ã");
            opus.type ("o");

            opus.assert_editor_text ("aão\naão\naão");
            opus.assert_cursors ({ {3, 3}, {7, 7}, {11, 11} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/input_method/a_committed_quote_auto_closes", () => {
        try {
            var opus = open ();

            opus.commit ("\"");

            opus.assert_editor_text ("\"\"");
            opus.assert_cursors ({ {1, 1} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/input_method/a_committed_backtick_auto_closes_where_the_language_pairs_it", () => {
        try {
            var path = write_fixture ("example.js", "const s = ");
            var opus = open (Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {0, 10} });

            opus.commit ("`");

            opus.assert_editor_text ("const s = ``");
            opus.assert_cursors ({ {11, 11} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/input_method/a_committed_character_replaces_every_selection", () => {
        try {
            var opus = open ();
            opus.editor_write ("ab\nab");
            opus.set_selections ({ {0, 0, 2}, {1, 0, 2} });

            opus.commit ("ã");

            opus.assert_editor_text ("ã\nã");
            opus.assert_cursors ({ {1, 1}, {3, 3} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/input_method/a_committed_quote_wraps_the_selection", () => {
        try {
            var opus = open ();
            opus.editor_write ("foo");
            opus.set_selections ({ {0, 0, 3} });

            opus.commit ("\"");

            opus.assert_editor_text ("\"foo\"");
            opus.assert_cursors ({ {1, 4} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/input_method/a_committed_word_lands_whole_at_every_cursor", () => {
        try {
            var opus = open ();
            opus.editor_write ("x\nx");
            opus.set_cursors ({ {0, 1}, {1, 1} });

            opus.commit ("日本");

            opus.assert_editor_text ("x日本\nx日本");
            opus.assert_cursors ({ {3, 3}, {7, 7} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/input_method/a_committed_character_undoes_with_the_typing_around_it", () => {
        try {
            var opus = open ();

            opus.type ("a");
            opus.commit ("ç");
            opus.type ("o");
            opus.type_cmd ("undo");

            opus.assert_editor_text ("");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/input_method/the_preedit_shows_at_every_cursor_with_the_caret_inside", () => {
        try {
            var opus = open ();
            opus.editor_write ("a\na\na");
            opus.set_cursors ({ {0, 1}, {1, 1}, {2, 1} });

            opus.preedit ("~", 1);

            opus.assert_editor_text ("a~\na~\na~");
            opus.assert_cursors ({ {2, 2}, {5, 5}, {8, 8} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/input_method/a_changed_preedit_replaces_the_one_showing", () => {
        try {
            var opus = open ();
            opus.editor_write ("x\nx");
            opus.set_cursors ({ {0, 1}, {1, 1} });

            opus.preedit ("に", 1);
            opus.preedit ("にほ", 2);

            opus.assert_editor_text ("xにほ\nxにほ");
            opus.assert_cursors ({ {3, 3}, {7, 7} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/input_method/the_commit_takes_the_preedit_s_place", () => {
        try {
            var opus = open ();
            opus.editor_write ("a\na\na");
            opus.set_cursors ({ {0, 1}, {1, 1}, {2, 1} });

            opus.preedit ("~", 1);
            opus.commit ("ã");

            opus.assert_editor_text ("aã\naã\naã");
            opus.assert_cursors ({ {2, 2}, {5, 5}, {8, 8} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/input_method/an_empty_preedit_takes_the_text_back_out", () => {
        try {
            var opus = open ();
            opus.editor_write ("ab");
            opus.set_cursors ({ {0, 1} });

            opus.preedit ("~", 1);
            opus.preedit ("", 0);

            opus.assert_editor_text ("ab");
            opus.assert_cursors ({ {1, 1} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/input_method/a_key_the_composer_let_through_ends_the_preedit", () => {
        try {
            var opus = open ();
            opus.editor_write ("ab\ncd");
            opus.set_cursors ({ {0, 1} });

            opus.preedit ("~", 1);
            opus.type_cmd ("down");

            opus.assert_editor_text ("ab\ncd");
            opus.assert_cursors ({ {4, 4} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/input_method/the_preedit_keeps_the_selections_for_the_commit_to_wrap", () => {
        try {
            var opus = open ();
            opus.editor_write ("foo bar");
            opus.set_selections ({ {0, 0, 3}, {0, 4, 7} });

            opus.preedit ("¨", 1);
            opus.commit ("\"");

            opus.assert_editor_text ("\"foo\" \"bar\"");
            opus.assert_cursors ({ {1, 4}, {7, 10} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/input_method/the_preedit_is_no_edit_to_undo", () => {
        try {
            var opus = open ();

            opus.type ("a");
            opus.preedit ("~", 1);
            opus.commit ("ã");
            opus.type_cmd ("undo");

            opus.assert_editor_text ("");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
