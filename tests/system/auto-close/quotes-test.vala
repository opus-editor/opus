/**
 * Quotes end to end (docs/AUTO_CLOSE.md §3): symmetric, so the editor
 * has to guess whether one opens or closes — after a word, after an odd
 * count, inside a string or a comment of a real language, and with
 * multi-byte characters before it, where a byte offset off by one
 * would show.
 */
private const uint DISPLAY = 143;

private SystemTestSession open (string? folder = null) throws Error {
    var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
    if (folder == null) {
        opus.new_file ();
    }
    return opus;
}

/** A folder holding `name` with `contents`; returns the file's path. */
private string write_fixture (string name, string contents) throws Error {
    var folder = DirUtils.make_tmp ("opus-auto-close-quotes-test-XXXXXX");
    var path = Path.build_filename (folder, name);
    FileUtils.set_contents (path, contents);
    return path;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/auto_close/quotes/a_quote_after_a_word_is_an_apostrophe", () => {
        try {
            var opus = open ();
            opus.editor_write ("don");
            opus.set_cursors ({ {0, 3} });

            opus.type ("'");

            opus.assert_editor_text ("don'");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/quotes/a_quote_closing_an_open_string_is_typed_alone", () => {
        try {
            var opus = open ();
            opus.editor_write ("s = \"a");
            opus.set_cursors ({ {0, 6} });

            opus.type ("\"");

            opus.assert_editor_text ("s = \"a\"");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/quotes/a_quote_after_a_closed_string_opens_a_new_pair", () => {
        try {
            var opus = open ();
            opus.editor_write ("s = \"a\" ");
            opus.set_cursors ({ {0, 8} });

            opus.type ("\"");

            opus.assert_editor_text ("s = \"a\" \"\"");
            opus.assert_cursors ({ {9, 9} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/quotes/a_quote_after_an_emoji_closes_at_the_right_place", () => {
        try {
            var opus = open ();
            opus.editor_write ("🏀 ");
            opus.set_cursors ({ {0, 2} });

            opus.type ("\"");

            opus.assert_editor_text ("🏀 \"\"");
            opus.assert_cursors ({ {3, 3} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/quotes/a_quote_at_the_end_of_a_c_line_comment_is_typed_alone", () => {
        try {
            var path = write_fixture ("example.c", "// say ");
            var opus = open (Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {0, 7} });

            opus.type ("'");

            opus.assert_editor_text ("// say '");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/quotes/a_quote_inside_a_c_string_is_typed_alone", () => {
        try {
            var path = write_fixture ("example.c", "char *s = \"a\";");
            var opus = open (Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {0, 12} });

            opus.type ("\"");

            opus.assert_editor_text ("char *s = \"a\"\";");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/quotes/a_quote_in_c_code_closes", () => {
        try {
            var path = write_fixture ("example.c", "char *s = ;");
            var opus = open (Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {0, 10} });

            opus.type ("\"");

            opus.assert_editor_text ("char *s = \"\";");
            opus.assert_cursors ({ {11, 11} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
