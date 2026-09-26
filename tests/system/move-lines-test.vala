/**
 * Alt+Up/Alt+Down (Move Lines Up/Down) — the real keyboard binding
 * reaching CursorController and landing on the real buffer, cursor shape
 * preserved. The trickier edge case (a multi-line selection's own shape
 * surviving the move, including a reversed selection) is already covered
 * precisely at the model level (cursor-collection-test.vala's own
 * compute_move_lines_edits cases, offset-exact) — this just confirms the
 * real wiring for the common case: a plain Alt+Down/Up on the current
 * line, and that a line already at the buffer's own edge doesn't move.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/move_lines/alt_down_moves_the_current_line_down", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 103);
            opus.new_file ();
            opus.editor_write ("aaa\nbbb\nccc");
            opus.set_cursors ({ {0, 1} }); // 2nd character of "aaa"

            opus.type_cmd ("alt+down");
            opus.assert_editor_text ("bbb\naaa\nccc");
            opus.assert_cursors ({ {5, 5} }); // 2nd character of "aaa", now on line 1

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/move_lines/alt_up_moves_the_current_line_up", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 103);
            opus.new_file ();
            opus.editor_write ("aaa\nbbb\nccc");
            opus.set_cursors ({ {1, 1} }); // 2nd character of "bbb"

            opus.type_cmd ("alt+up");
            opus.assert_editor_text ("bbb\naaa\nccc");
            opus.assert_cursors ({ {1, 1} }); // 2nd character of "bbb", now on line 0

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/move_lines/alt_down_on_the_last_line_is_a_no_op", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 103);
            opus.new_file ();
            opus.editor_write ("aaa\nbbb");
            opus.set_cursors ({ {1, 1} }); // 2nd character of "bbb", the last line

            opus.type_cmd ("alt+down");
            opus.assert_editor_text ("aaa\nbbb");
            opus.assert_cursors ({ {5, 5} }); // unchanged

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
