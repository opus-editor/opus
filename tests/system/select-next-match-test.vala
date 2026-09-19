/**
 * Ctrl+D ("add selection to next find match", CursorCollection's own
 * add_cursor_at_next_match): with a selection already on the last-added
 * cursor, adds a new cursor on the next occurrence of the selected text
 * — existing cursors are left exactly as they are, and once there's no
 * further occurrence left, it's a no-op.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/select_next_match/ctrl_d_selects_each_next_occurrence_then_stops", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 97);
            opus.new_file ();
            opus.editor_write ("aaaa bbbb cccc\naaaa dddd aaaa");
            opus.set_cursors ({ {0, 0} });
            for (int i = 0; i < 4; i++) {
                opus.type_cmd ("shift+right");
            }
            opus.assert_cursors ({ {0, 4} }); // "[aaaa]| bbbb cccc"

            opus.type_cmd ("ctrl+d");
            // "[aaaa]| bbbb cccc" / "[aaaa]| bbbb aaaa" — first "aaaa" on
            // line 1 selected too, the original selection untouched
            opus.assert_cursors ({ {0, 4}, {15, 19} });

            opus.type_cmd ("ctrl+d");
            // "[aaaa]| bbbb cccc" / "[aaaa]| bbbb [aaaa]|" — both "aaaa"
            // occurrences on line 1 selected now
            opus.assert_cursors ({ {0, 4}, {15, 19}, {25, 29} });

            opus.type_cmd ("ctrl+d");
            // no more occurrences left — a no-op, nothing changes
            opus.assert_cursors ({ {0, 4}, {15, 19}, {25, 29} });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
