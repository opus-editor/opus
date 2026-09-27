/**
 * Two collapsed cursors at the same column on two different lines,
 * extended downward (each keeps its own column, ending up touching but
 * not merged), then extended right once more — which finally makes them
 * overlap and merge into a single selection. Reproduces a scenario
 * checked by hand against real VS Code; already covered at the model
 * level (cursor-collection-test.vala's own version of this scenario).
 *
 *   aa|aa      Shift+Down       aa[aa      Shift+Right      aa[aa
 *   bb|bb      ------------>    bb]|[bb    ------------>    bbbb
 *   cccc                        cc]|cc                      ccc]c
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/cursor_merge/two_cursors_extended_down_then_right_merge_once_they_overlap", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 93);
            opus.new_file ();
            opus.editor_write ("aaaa\nbbbb\ncccc");
            opus.set_cursors ({ {0, 2}, {1, 2} }); // "aa|aa" / "bb|bb", offsets 2 and 7

            opus.type_cmd ("shift+down");

            // still two cursors: they touch exactly at column 2 of the
            // middle line ("bb]|[bb") but a touch between two non-empty
            // selections isn't a merge — only a real overlap is
            opus.assert_cursors ({ {2, 7}, {7, 12} });

            opus.type_cmd ("shift+right");

            // both selections grew by one character and now genuinely
            // overlap (7 falls strictly inside [2,8)) — they merge into one
            opus.assert_cursors ({ {2, 13} });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
