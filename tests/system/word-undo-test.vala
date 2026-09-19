/**
 * Typing three words in a row and undoing them one word at a time —
 * a space closes off the word behind it as its own undo step, but
 * typing right after a single space doesn't force a boundary of its
 * own (see EditHistory's own can_coalesce, ported from VS Code's
 * shouldPushStackElementBetween). Already covered at the model level
 * (edit-history-test.vala); lower priority for a system-level duplicate
 * than the other three scenarios, but cheap belt-and-suspenders coverage
 * for the real keyboard -> EditHistory wiring.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/word_undo/three_words_typed_in_a_row_undo_one_word_at_a_time", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 94);
            opus.new_file ();

            opus.type ("asdasd asdasd asdasd");
            opus.assert_editor_text ("asdasd asdasd asdasd");

            opus.type_cmd ("undo");
            opus.assert_editor_text ("asdasd asdasd");

            opus.type_cmd ("undo");
            opus.assert_editor_text ("asdasd");

            opus.type_cmd ("undo");
            opus.assert_editor_text ("");

            opus.type_cmd ("redo");
            opus.assert_editor_text ("asdasd");

            opus.type_cmd ("redo");
            opus.assert_editor_text ("asdasd asdasd");

            opus.type_cmd ("redo");
            opus.assert_editor_text ("asdasd asdasd asdasd");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
