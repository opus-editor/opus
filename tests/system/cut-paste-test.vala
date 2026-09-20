/**
 * Ctrl+X/Ctrl+V, claimed directly by CursorController and routed through
 * its own apply_edit() (see cursor-controller.vala's own doc comment on
 * that block) — unlike GTK's native cut/paste, or drag-and-drop, these
 * now push real EditHistory entries, so undo reverts them exactly like
 * any other edit instead of corrupting the buffer.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/cut_paste/cut_then_paste_round_trips_through_undo", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 96);
            opus.new_file ();
            opus.editor_write ("aaaa bbbb cccc");
            opus.set_cursors ({ {0, 0} });
            for (int i = 0; i < 4; i++) {
                opus.type_cmd ("shift+right");
            }
            opus.assert_cursors ({ {0, 4} }); // "[aaaa]" selected

            opus.type_cmd ("ctrl+x");
            opus.assert_editor_text (" bbbb cccc");
            opus.assert_cursors ({ {0, 0} }); // collapsed where the cut text used to start

            opus.set_cursors ({ {0, 10} }); // end of " bbbb cccc"
            opus.type_cmd ("ctrl+v");
            opus.assert_editor_text (" bbbb ccccaaaa");

            opus.type_cmd ("undo"); // undoes the paste only
            opus.assert_editor_text (" bbbb cccc");

            opus.type_cmd ("undo"); // undoes the cut only — separate step, not merged with the paste
            opus.assert_editor_text ("aaaa bbbb cccc");
            opus.assert_cursors ({ {0, 4} }); // the original selection, restored

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    // Regression: Ctrl+X only ever copied the primary cursor's own
    // selection (GTK's native copy_clipboard() has no notion of more
    // than one selection), so a following Ctrl+V pasted that same one
    // piece into every cursor instead of distributing "aaa"/"bbb"/"ccc"
    // back to where each came from.
    Test.add_func ("/system/cut_paste/multi_cursor_cut_then_paste_distributes_one_piece_per_cursor", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 96);
            opus.new_file ();
            opus.editor_write ("aaa\nbbb\nccc");
            opus.set_selections ({ {0, 0, 3}, {1, 0, 3}, {2, 0, 3} }); // "aaa", "bbb", "ccc" each fully selected

            opus.type_cmd ("ctrl+x");
            opus.assert_editor_text ("\n\n");

            opus.type_cmd ("ctrl+v");
            opus.assert_editor_text ("aaa\nbbb\nccc");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
