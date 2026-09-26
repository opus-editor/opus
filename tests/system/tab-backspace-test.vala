/**
 * Tab/Backspace honoring .editorconfig's `indent_style` — two real bugs
 * found by hand in the running app this session, both already covered at
 * the model level (cursor-collection-test.vala's own compute_tab_edits/
 * compute_backspace_edits cases): first Tab/Backspace not respecting
 * `indent_style = space` at all, then Backspace silently doing nothing on
 * an empty line (see CursorCollection.compute_backspace_edits()'s own doc
 * comment for that one's root cause). This confirms the real wiring — an
 * actual `.editorconfig` on disk, read by EditorConfig, resolved by
 * EditorController, pushed into CursorController, and a real keystroke
 * reaching CursorCollection through all of that — holds together
 * end-to-end, not just the model logic in isolation.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/tab_backspace/indent_style_space_inserts_and_removes_a_whole_stop_at_once", () => {
        string folder = Path.build_filename (Environment.get_tmp_dir (), "opus-tab-backspace-test-%u".printf (Random.next_int ()));
        try {
            DirUtils.create (folder, 0700);
            FileUtils.set_contents (Path.build_filename (folder, ".editorconfig"), "[*]\nindent_style = space\nindent_size = 2\n");

            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 101, folder);
            opus.new_file ();

            opus.type_cmd ("tab");
            opus.assert_editor_text ("  ");

            opus.type_cmd ("tab");
            opus.assert_editor_text ("    ");

            opus.type_cmd ("backspace");
            opus.assert_editor_text ("  "); // a whole indent_size removed at once, not just one space

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        } finally {
            FileUtils.remove (Path.build_filename (folder, ".editorconfig"));
            DirUtils.remove (folder);
        }
    });

    Test.add_func ("/system/tab_backspace/without_indent_style_tab_still_inserts_a_literal_tab_character", () => {
        try {
            // No linked folder at all — same as every other existing
            // system test — so there's no .editorconfig to find, matching
            // today's real default (unconfigured) behavior.
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 101);
            opus.new_file ();

            opus.type_cmd ("tab");
            opus.assert_editor_text ("\t");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/tab_backspace/backspace_on_an_empty_line_merges_with_the_line_above", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 101);
            opus.new_file ();
            opus.editor_write ("abcd\n");
            opus.set_cursors ({ {1, 0} }); // start of the empty second line

            opus.type_cmd ("backspace");
            opus.assert_editor_text ("abcd");
            opus.assert_cursors ({ {4, 4} });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
