/**
 * Ctrl+Right/Left word-jump, verified against VS Code's real source
 * (wordOperations.ts): Ctrl+Right (cursorWordEndRight) lands at the end
 * of the current/next word, Ctrl+Left (cursorWordLeft) at the start of
 * the previous one.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/word_jump/ctrl_right_walks_word_by_word_to_the_end_of_text", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 95);
            opus.new_file ();
            opus.editor_write ("aaaa bbbb cccc");
            opus.set_cursors ({ {0, 2} }); // "aa|aa bbbb cccc"

            opus.type_cmd ("ctrl+right");
            opus.assert_cursors ({ {4, 4} }); // "aaaa| bbbb cccc"

            opus.type_cmd ("ctrl+right");
            opus.assert_cursors ({ {9, 9} }); // "aaaa bbbb| cccc"

            opus.type_cmd ("ctrl+right");
            opus.assert_cursors ({ {14, 14} }); // "aaaa bbbb cccc|"

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/word_jump/ctrl_left_walks_word_by_word_back_to_the_start_of_text", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 95);
            opus.new_file ();
            opus.editor_write ("aaaa bbbb cccc");
            opus.set_cursors ({ {0, 12} }); // "aaaa bbbb cc|cc"

            opus.type_cmd ("ctrl+left");
            opus.assert_cursors ({ {10, 10} }); // "aaaa bbbb |cccc"

            opus.type_cmd ("ctrl+left");
            opus.assert_cursors ({ {5, 5} }); // "aaaa |bbbb cccc"

            opus.type_cmd ("ctrl+left");
            opus.assert_cursors ({ {0, 0} }); // "|aaaa bbbb cccc"

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    // Each cursor moves independently, and word_right() works on the
    // whole document's char array (not per-line, treating "\n" as just
    // another whitespace char to skip over) — so a cursor that runs out
    // of words on its own line keeps going onto the next one. Here that
    // means the line-0 cursor, one word-jump ahead of the line-1 cursor
    // at every step, eventually overtakes it: by the last press it has
    // crossed onto line 1 too, landing behind the line-1 cursor (which
    // already hit the end of the document and can't move further).
    Test.add_func ("/system/word_jump/two_cursors_on_different_lines_move_independently_and_can_cross_lines", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 95);
            opus.new_file ();
            opus.editor_write ("aaaa   bbbb cccc\ndddd eeee ffff");
            opus.set_cursors ({ {0, 2}, {1, 2} }); // "aa|aa   bbbb cccc" / "dd|dd eeee ffff"

            opus.type_cmd ("ctrl+right");
            opus.assert_cursors ({ {4, 4}, {21, 21} }); // "aaaa|   bbbb cccc" / "dddd| eeee ffff"

            opus.type_cmd ("ctrl+right");
            opus.assert_cursors ({ {11, 11}, {26, 26} }); // "aaaa   bbbb| cccc" / "dddd eeee| ffff"

            opus.type_cmd ("ctrl+right");
            opus.assert_cursors ({ {16, 16}, {31, 31} }); // "aaaa   bbbb cccc|" / "dddd eeee ffff|"

            opus.type_cmd ("ctrl+right");
            // the line-0 cursor crossed onto line 1, landing at "dddd|";
            // the line-1 cursor was already at the end of the document
            // and stays put — both now on line 1
            opus.assert_cursors ({ {21, 21}, {31, 31} }); // "aaaa   bbbb cccc" / "dddd| eeee ffff|"

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
