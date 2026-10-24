/**
 * The inserted-pair memory end to end (docs/AUTO_CLOSE.md §4-§6):
 * what makes a `)` Opus inserted differ from a `)` already in the
 * file, when the editor forgets it, and `track_inserted_pairs` off
 * treating every pair alike.
 */
private const uint DISPLAY = 142;

private SystemTestSession open (string? settings_json = null) throws Error {
    var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, null, settings_json);
    opus.new_file ();
    return opus;
}

private const string TRACKING_OFF = """{ "editor.auto_close.track_inserted_pairs": false }""";

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/auto_close/memory/once_the_cursor_left_the_pair_its_closer_is_typed_again", () => {
        try {
            var opus = open ();
            opus.editor_write ("\nz");
            opus.set_cursors ({ {0, 0} });

            opus.type ("x=(");
            opus.type_cmd ("down");
            opus.type_cmd ("up"); // back to the same column, between the parentheses
            opus.type (")");

            opus.assert_editor_text ("x=())\nz");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/memory/the_closer_is_skipped_only_once", () => {
        try {
            var opus = open ();

            opus.type ("x=()");
            opus.set_cursors ({ {0, 3} });
            opus.type (")");

            opus.assert_editor_text ("x=())");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/memory/nested_pairs_are_each_remembered", () => {
        try {
            var opus = open ();

            opus.type ("x=((");
            opus.type ("))");

            opus.assert_editor_text ("x=(())");
            opus.assert_cursors ({ {6, 6} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/memory/backspace_takes_out_only_what_opus_inserted", () => {
        try {
            var opus = open ();

            opus.type ("x=(asd");
            opus.type_cmd ("backspace");
            opus.type_cmd ("backspace");
            opus.type_cmd ("backspace");
            bool emptied_the_pair_first = opus.active_text () == "x=()";
            opus.type_cmd ("backspace");

            assert_true (emptied_the_pair_first);
            opus.assert_editor_text ("x=");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/memory/backspace_inside_a_pair_from_the_file_removes_one_character", () => {
        try {
            var opus = open ();
            opus.editor_write ("y=();");
            opus.set_cursors ({ {0, 3} });

            opus.type_cmd ("backspace");

            opus.assert_editor_text ("y=);");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/memory/without_tracking_any_matching_closer_is_skipped", () => {
        try {
            var opus = open (TRACKING_OFF);
            opus.editor_write ("{)");
            opus.set_cursors ({ {0, 1} });

            opus.type ("})"); // the } finds a ) ahead and is inserted; the ) then skips it

            opus.assert_editor_text ("{})");
            opus.assert_cursors ({ {3, 3} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/memory/without_tracking_closers_are_skipped_at_every_cursor", () => {
        try {
            var opus = open (TRACKING_OFF);
            opus.editor_write ("x)\ny)");
            opus.set_cursors ({ {0, 1}, {1, 1} });

            opus.type (")");

            opus.assert_editor_text ("x)\ny)");
            opus.assert_cursors ({ {2, 2}, {5, 5} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/memory/without_tracking_a_closer_of_another_pair_is_inserted", () => {
        try {
            var opus = open (TRACKING_OFF);
            opus.editor_write ("{}");
            opus.set_cursors ({ {0, 1} });

            opus.type ("]");

            opus.assert_editor_text ("{]}");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/memory/without_tracking_backspace_takes_any_empty_pair_out", () => {
        try {
            var opus = open (TRACKING_OFF);
            opus.editor_write ("a{}");
            opus.set_cursors ({ {0, 2} });

            opus.type_cmd ("backspace");

            opus.assert_editor_text ("a");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
