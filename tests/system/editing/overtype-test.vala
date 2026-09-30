/**
 * Insert/overtype mode — plain Insert toggles Session.get_default().
 * insert_mode (src/models/session.vala), a session-wide flag that makes
 * typed and pasted text replace what's under the caret instead of
 * pushing it right. Exercises the real key-press pipeline end to end
 * (CodeEditorCursors -> CursorCollection.compute_edits/
 * compute_distributed_paste_edits -> the real buffer).
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/overtype/toggle_replaces_character_mid_line", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 104);
            opus.new_file ();
            opus.editor_write ("aaaa bbbb cccc");
            opus.set_cursors ({ {0, 5} }); // just before "bbbb"

            opus.type_cmd ("insert");
            opus.type ("XYZ");
            opus.assert_editor_text ("aaaa XYZb cccc");
            opus.assert_cursors ({ {8, 8} }); // { anchor_offset, position_offset } — both 8, collapsed

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/overtype/degrades_to_insert_at_line_end", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 104);
            opus.new_file ();
            opus.editor_write ("abc\ndef");
            opus.set_cursors ({ {0, 3} }); // end of "abc", right before the newline

            opus.type_cmd ("insert");
            opus.type ("XY");
            opus.assert_editor_text ("abcXY\ndef"); // never eats the line break

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/overtype/toggle_off_resumes_plain_insert", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 104);
            opus.new_file ();
            opus.editor_write ("aaaa");
            opus.set_cursors ({ {0, 0} });

            opus.type_cmd ("insert");
            opus.type ("X");
            opus.assert_editor_text ("Xaaa");

            opus.type_cmd ("insert"); // toggle back off
            opus.set_cursors ({ {0, 0} });
            opus.type ("Y");
            opus.assert_editor_text ("YXaaa");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/overtype/multi_cursor_each_overtypes_independently", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 104);
            opus.new_file ();
            opus.editor_write ("aaaa\nbbbb");
            opus.set_cursors ({ {0, 1}, {1, 1} });

            opus.type_cmd ("insert");
            opus.type ("X");
            opus.assert_editor_text ("aXaa\nbXbb");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/overtype/paste_single_string_respects_overtype", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 104);
            opus.new_file ();
            opus.editor_write ("aaaa bbbb");
            opus.set_cursors ({ {0, 0} });
            for (int i = 0; i < 4; i++) {
                opus.type_cmd ("shift+right");
            }
            opus.type_cmd ("ctrl+x"); // clipboard now holds "aaaa", buffer is " bbbb"
            opus.assert_editor_text (" bbbb");

            opus.set_cursors ({ {0, 1} }); // just before "bbbb"
            opus.type_cmd ("insert");
            opus.type_cmd ("ctrl+v");
            opus.assert_editor_text (" aaaa"); // "bbbb" overwritten, not pushed right

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/overtype/distributed_paste_respects_overtype", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 104);
            opus.new_file ();
            opus.editor_write ("aaa\nbbb\nccc\ndddd\neeee\nffff");
            opus.set_selections ({ {0, 0, 3}, {1, 0, 3}, {2, 0, 3} }); // "aaa", "bbb", "ccc"
            opus.type_cmd ("ctrl+x"); // 3 pieces, matching the 3-cursor paste below
            opus.assert_editor_text ("\n\n\ndddd\neeee\nffff");

            opus.set_cursors ({ {3, 0}, {4, 0}, {5, 0} }); // start of "dddd"/"eeee"/"ffff"
            opus.type_cmd ("insert");
            opus.type_cmd ("ctrl+v");
            // each 3-char piece overtypes 3 of its own line's 4 characters, leaving the 4th untouched
            opus.assert_editor_text ("\n\n\naaad\nbbbe\ncccf");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
