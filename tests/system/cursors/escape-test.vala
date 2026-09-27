/**
 * Escape's three cases, verified against VS Code's real
 * coreCommands.ts (RemoveSecondaryCursors + CancelSelection).
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/escape/multiple_cursors_collapse_to_primary", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 91);
            opus.new_file ();
            opus.editor_write ("aaaa\nbbbb");
            opus.set_cursors ({ {0, 2}, {1, 2} }); // primary at offset 2, secondary at offset 7

            bool claimed = opus.type_cmd ("escape");

            assert_true (claimed);
            opus.assert_cursors ({ {2, 2} }); // only the primary is left, exactly where it was
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/escape/one_cursor_with_a_selection_collapses_to_the_caret_end", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 91);
            opus.new_file ();
            opus.editor_write ("aaaa");
            opus.set_cursors ({ {0, 0} });
            opus.type_cmd ("shift+right");
            opus.type_cmd ("shift+right");
            opus.assert_cursors ({ {0, 2} }); // sanity check: a real selection, anchor 0 to position 2

            bool claimed = opus.type_cmd ("escape");

            assert_true (claimed);
            opus.assert_cursors ({ {2, 2} }); // collapsed to the caret end, not the anchor
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/escape/one_cursor_no_selection_is_a_no_op", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 91);
            opus.new_file ();
            opus.editor_write ("hi");
            opus.set_cursors ({ {0, 1} });

            bool claimed = opus.type_cmd ("escape");

            assert_false (claimed); // neither command's precondition applies — genuinely unclaimed
            opus.assert_cursors ({ {1, 1} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
