/**
 * Enter between the two halves of a pair, end to end
 * (docs/AUTO_CLOSE.md §9): `{|}` opens a line between them, indented
 * one level in from the line, with the closer on a third line at the
 * line's own level — whether Opus inserted the pair or the file had it,
 * for the pairs the language says open up, at every cursor.
 */
private const uint DISPLAY = 147;

private SystemTestSession open (string? settings_json = null, string? folder = null) throws Error {
    var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder, settings_json);
    if (folder == null) {
        opus.new_file ();
    }
    return opus;
}

/** A folder holding `name` with `contents`; returns the file's path. */
private string write_fixture (string name, string contents) throws Error {
    var folder = DirUtils.make_tmp ("opus-auto-close-enter-test-XXXXXX");
    var path = Path.build_filename (folder, name);
    FileUtils.set_contents (path, contents);
    return path;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/auto_close/enter/between_a_pair_just_typed_opens_an_indented_line", () => {
        try {
            var opus = open ();

            opus.type ("{");
            opus.type_cmd ("enter");

            opus.assert_editor_text ("{\n    \n}");
            opus.assert_cursors ({ {6, 6} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/enter/between_a_pair_the_file_already_had_does_the_same", () => {
        try {
            var opus = open ();
            opus.editor_write ("{}");
            opus.set_cursors ({ {0, 1} });

            opus.type_cmd ("enter");

            opus.assert_editor_text ("{\n    \n}");
            opus.assert_cursors ({ {6, 6} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/enter/the_closer_keeps_the_line_s_own_indentation", () => {
        try {
            var opus = open ();
            opus.editor_write ("    {}");
            opus.set_cursors ({ {0, 5} });

            opus.type_cmd ("enter");

            opus.assert_editor_text ("    {\n        \n    }");
            opus.assert_cursors ({ {14, 14} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/enter/blanks_between_the_halves_go_with_the_edit", () => {
        try {
            var opus = open ();
            opus.editor_write ("{  }");
            opus.set_cursors ({ {0, 2} });

            opus.type_cmd ("enter");

            opus.assert_editor_text ("{\n    \n}");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/enter/between_quotes_is_an_ordinary_line_break", () => {
        try {
            var opus = open ();
            opus.editor_write ("\"\"");
            opus.set_cursors ({ {0, 1} });

            opus.type_cmd ("enter");

            opus.assert_editor_text ("\"\n\"");
            opus.assert_cursors ({ {2, 2} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/enter/every_cursor_between_a_pair_opens_its_own", () => {
        try {
            var opus = open ();
            opus.editor_write ("{}\n{}");
            opus.set_cursors ({ {0, 1}, {1, 1} });

            opus.type_cmd ("enter");

            opus.assert_editor_text ("{\n    \n}\n{\n    \n}");
            opus.assert_cursors ({ {6, 6}, {15, 15} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/enter/one_undo_closes_the_lines_back_up", () => {
        try {
            var opus = open ();
            opus.editor_write ("{}");
            opus.set_cursors ({ {0, 1} });

            opus.type_cmd ("enter");
            opus.type_cmd ("undo");

            opus.assert_editor_text ("{}");
            opus.assert_cursors ({ {1, 1} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/enter/the_language_s_own_brackets_open_up", () => {
        try {
            var path = write_fixture ("example.rs", "let v = [];");
            var opus = open (null, Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {0, 9} });

            opus.type_cmd ("enter");

            opus.assert_editor_text ("let v = [\n    \n];");
            opus.assert_cursors ({ {14, 14} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/enter/a_block_comment_does_not_open_up", () => {
        try {
            var path = write_fixture ("example.c", "/* */");
            var opus = open (null, Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {0, 2} });

            opus.type_cmd ("enter");

            opus.assert_editor_text ("/*\n */");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/enter/inside_a_page_s_script_the_script_s_brackets_open_up", () => {
        try {
            var path = write_fixture ("example.html", "<script>\nf({})\n</script>");
            var opus = open (null, Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {1, 3} });

            opus.type_cmd ("enter");

            opus.assert_editor_text ("<script>\nf({\n    \n})\n</script>");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/enter/with_auto_indent_off_enter_is_a_plain_line_break", () => {
        try {
            var opus = open ("""{ "editor.auto_indent": false }""");
            opus.editor_write ("{}");
            opus.set_cursors ({ {0, 1} });

            opus.type_cmd ("enter");

            opus.assert_editor_text ("{\n}");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
