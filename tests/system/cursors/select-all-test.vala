/**
 * Ctrl+A (select all): GTK's own native gtk_text_view_select_all()
 * always places `insert` (the caret) at the document's start and
 * `selection_bound` (the anchor) at its end — verified against GTK's
 * real source — opposite of VS Code's own convention, where the caret
 * lands at the end. EditorView.on_mark_set() normalizes this; see its
 * own doc comment.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/select_all/ctrl_a_selects_everything_with_the_caret_at_the_end", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 98);
            opus.new_file ();
            opus.editor_write ("aaaa bbbb cccc");

            opus.select_all ();

            opus.assert_cursors ({ {0, 14} }); // anchor at the start, caret at the end

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
