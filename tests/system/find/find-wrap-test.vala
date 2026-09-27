/**
 * Next/Previous Match must wrap around the buffer's own start/end
 * instead of getting stuck reporting "no match" once nothing is left
 * ahead of/behind the current one — a regression test for
 * TextEditorSearch's own constructor explicitly enabling
 * GtkSourceSearchSettings.wrap_around (its real default is false, not
 * true — confirmed against the real library directly, not assumed).
 * Left at that default, Next Match from the last occurrence (or from
 * wherever the caret starts once nothing else remains ahead of it)
 * reported position 0 forever instead of cycling back to the first.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/find_wrap/next_match_wraps_from_last_occurrence_to_first", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 105);
            opus.new_file ();
            opus.editor_write ("aaa aaa aaa\naaa bbb aaa");
            // Caret at the buffer's very end — same as just having typed
            // the text above, nothing left ahead of it to search forward
            // into without wrapping.
            opus.set_cursors ({ {1, 11} });

            opus.search_set_text ("aaa");
            opus.assert_search_position (1, 5);

            opus.search_next ();
            opus.assert_search_position (2, 5);
            opus.search_next ();
            opus.assert_search_position (3, 5);
            opus.search_next ();
            opus.assert_search_position (4, 5);
            opus.search_next ();
            opus.assert_search_position (5, 5);

            // The regression itself: one more Next Match past the last
            // occurrence must wrap back to the first, not get stuck.
            opus.search_next ();
            opus.assert_search_position (1, 5);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/find_wrap/previous_match_wraps_from_first_occurrence_to_last", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 105);
            opus.new_file ();
            opus.editor_write ("aaa aaa aaa\naaa bbb aaa");
            opus.set_cursors ({ {1, 11} });

            opus.search_set_text ("aaa");
            opus.assert_search_position (1, 5);

            // Already on the first occurrence — one Previous Match must
            // wrap back to the last, not get stuck.
            opus.search_previous ();
            opus.assert_search_position (5, 5);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
