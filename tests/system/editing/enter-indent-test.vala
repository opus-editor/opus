/**
 * Enter carries the current line's own leading indentation forward to the
 * new line — VS Code's/gnome-text-editor's own baseline auto-indent
 * behavior, ported from VS Code's "Keep" strategy (see
 * CursorCollection.compute_enter_edits()'s own doc comment for why only
 * that one, not its bracket/language-aware ones). Already covered at the
 * model level (cursor-collection-test.vala's own compute_enter_edits
 * cases); this confirms the real wiring — a real .editorconfig on disk,
 * resolved into indent_size/insert_spaces, reaching a real Enter
 * keystroke end-to-end — holds together, not just the model logic alone.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/enter_indent/enter_carries_the_current_lines_indentation_forward", () => {
        string folder = Path.build_filename (Environment.get_tmp_dir (), "opus-enter-indent-test-%u".printf (Random.next_int ()));
        try {
            DirUtils.create (folder, 0700);
            FileUtils.set_contents (Path.build_filename (folder, ".editorconfig"), "[*]\nindent_style = space\nindent_size = 2\n");

            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 102, folder);
            opus.new_file ();
            opus.editor_write ("def foo\n  bar");
            opus.set_cursors ({ {1, 5} }); // end of "  bar"

            opus.type_cmd ("enter");
            opus.assert_editor_text ("def foo\n  bar\n  ");
            opus.assert_cursors ({ {16, 16} });

            // Deepens with the line it's now on, same as a real editing
            // session would: Tab first, then Enter again.
            opus.type_cmd ("tab");
            opus.type_cmd ("enter");
            opus.assert_editor_text ("def foo\n  bar\n    \n    ");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        } finally {
            FileUtils.remove (Path.build_filename (folder, ".editorconfig"));
            DirUtils.remove (folder);
        }
    });

    Test.add_func ("/system/enter_indent/enter_inside_the_leading_whitespace_does_not_grow_the_indentation", () => {
        string folder = Path.build_filename (Environment.get_tmp_dir (), "opus-enter-indent-test-%u".printf (Random.next_int ()));
        try {
            DirUtils.create (folder, 0700);
            FileUtils.set_contents (Path.build_filename (folder, ".editorconfig"), "[*]\nindent_style = space\nindent_size = 2\n");

            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 102, folder);
            opus.new_file ();
            opus.editor_write ("    bar"); // 4 leading spaces
            opus.set_cursors ({ {0, 2} }); // halfway through the leading whitespace

            opus.type_cmd ("enter");
            // Enter never deletes what's after the cursor (there's no
            // selection here), so the other 2 original spaces just end
            // up on the new line unchanged, right after the *newly
            // typed* indentation — which is what this actually checks:
            // exactly 2 spaces typed (truncated to the cursor's own
            // column), not the whole line's own 4 (an untruncated copy
            // would leave 6 spaces before "bar" here, not 4).
            opus.assert_editor_text ("  \n    bar");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        } finally {
            FileUtils.remove (Path.build_filename (folder, ".editorconfig"));
            DirUtils.remove (folder);
        }
    });

    return Test.run ();
}
