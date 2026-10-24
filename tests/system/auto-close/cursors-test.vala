/**
 * Auto-close with several cursors and selections at once
 * (docs/AUTO_CLOSE.md §8): every cursor closes, skips, wraps and
 * deletes on its own, each judged by its own context, and the few that
 * collide are resolved. The guarantee Opus's multi-cursor rests on,
 * through the real key-press pipeline.
 */
private const uint DISPLAY = 141;

private SystemTestSession open (string? settings_json = null) throws Error {
    var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, null, settings_json);
    opus.new_file ();
    return opus;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/auto_close/cursors/three_cursors_each_close_their_own_nested_pairs", () => {
        try {
            var opus = open ();
            opus.editor_write ("a\nb\nc");
            opus.set_cursors ({ {0, 1}, {1, 1}, {2, 1} });

            opus.type ("{{{");

            opus.assert_editor_text ("a{{{}}}\nb{{{}}}\nc{{{}}}");
            opus.assert_cursors ({ {4, 4}, {12, 12}, {20, 20} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/cursors/a_different_closer_is_inserted_at_every_cursor", () => {
        try {
            var opus = open ();
            opus.editor_write ("a\nb\nc");
            opus.set_cursors ({ {0, 1}, {1, 1}, {2, 1} });

            opus.type ("{{{)");

            opus.assert_editor_text ("a{{{)}}}\nb{{{)}}}\nc{{{)}}}");
            opus.assert_cursors ({ {5, 5}, {14, 14}, {23, 23} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/cursors/the_closers_opus_inserted_are_skipped_at_every_cursor", () => {
        try {
            var opus = open ();
            opus.editor_write ("a\nb\nc");
            opus.set_cursors ({ {0, 1}, {1, 1}, {2, 1} });

            opus.type ("{{{}}}");

            opus.assert_editor_text ("a{{{}}}\nb{{{}}}\nc{{{}}}");
            opus.assert_cursors ({ {7, 7}, {15, 15}, {23, 23} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/cursors/each_cursor_decides_on_its_own_context", () => {
        try {
            var opus = open ();
            opus.editor_write ("a\n b");
            opus.set_cursors ({ {0, 0}, {1, 0} });

            opus.type ("(");

            // before a word the opener stays alone; before a space it closes
            opus.assert_editor_text ("(a\n() b");
            opus.assert_cursors ({ {1, 1}, {4, 4} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/cursors/three_selections_are_wrapped_and_stay_selected", () => {
        try {
            var opus = open ();
            opus.editor_write ("a\nb\nc");
            opus.set_selections ({ {0, 0, 1}, {1, 0, 1}, {2, 0, 1} });

            opus.type ("{{{");

            opus.assert_editor_text ("{{{a}}}\n{{{b}}}\n{{{c}}}");
            opus.assert_cursors ({ {3, 4}, {11, 12}, {19, 20} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/cursors/one_undo_unwraps_three_selections_and_restores_them", () => {
        try {
            var opus = open ();
            opus.editor_write ("a\nb\nc");
            opus.set_selections ({ {0, 0, 1}, {1, 0, 1}, {2, 0, 1} });

            opus.type ("{{{");
            opus.type_cmd ("undo");

            opus.assert_editor_text ("a\nb\nc");
            opus.assert_cursors ({ {0, 1}, {2, 3}, {4, 5} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/cursors/backspace_takes_a_fresh_pair_out_at_every_cursor", () => {
        try {
            var opus = open ();
            opus.editor_write ("a\nb\nc");
            opus.set_cursors ({ {0, 1}, {1, 1}, {2, 1} });

            opus.type ("{{_");
            opus.type_cmd ("backspace");
            opus.type_cmd ("backspace");

            opus.assert_editor_text ("a{}\nb{}\nc{}");
            opus.assert_cursors ({ {2, 2}, {6, 6}, {10, 10} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/cursors/a_cursor_in_a_fresh_pair_and_one_outside_each_delete_their_own", () => {
        try {
            var opus = open ();
            opus.editor_write ("x\ny");
            opus.set_cursors ({ {0, 1}, {1, 0} });

            opus.type ("(");
            opus.type_cmd ("backspace");

            opus.assert_editor_text ("x\ny");
            opus.assert_cursors ({ {1, 1}, {2, 2} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/cursors/adjacent_cursors_whose_pair_deletes_collide_keep_one", () => {
        try {
            var opus = open ("""{ "editor.auto_close.track_inserted_pairs": false }""");
            opus.editor_write ("()");
            opus.set_cursors ({ {0, 1}, {0, 2} });

            opus.type_cmd ("backspace");

            opus.assert_editor_text ("");
            opus.assert_cursors ({ {0, 0} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
