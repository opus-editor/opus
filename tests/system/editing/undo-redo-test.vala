/**
 * The multi-cursor undo/redo round trip behind a real data-corruption
 * bug found by hand in the running app — already covered at the
 * model level (edit-history-test.vala's own "two simultaneous cursors"
 * tests); this confirms the real wiring (keyboard -> CursorController ->
 * EditHistory -> EditorView.apply_edits -> buffer) holds together
 * end-to-end, not just the EditHistory logic in isolation.
 *
 * Both keystrokes land within the same typing run, so EditHistory
 * coalesces them into one undo step — one type_cmd("undo") reverts both
 * characters together, not one at a time.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/undo_redo/two_cursors_typing_two_characters_round_trips", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 92);
            opus.new_file ();
            opus.editor_write ("aaaa\nbbbb\ncccc");
            opus.set_cursors ({ {0, 2}, {1, 2} }); // "aa|aa" / "bb|bb", offsets 2 and 7

            opus.type ("z");
            opus.type ("z");
            opus.assert_editor_text ("aazzaa\nbbzzbb\ncccc");
            opus.assert_cursors ({ {4, 4}, {11, 11} });

            opus.type_cmd ("undo");
            opus.assert_editor_text ("aaaa\nbbbb\ncccc");
            opus.assert_cursors ({ {2, 2}, {7, 7} });

            opus.type_cmd ("redo");
            opus.assert_editor_text ("aazzaa\nbbzzbb\ncccc");
            opus.assert_cursors ({ {4, 4}, {11, 11} });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
