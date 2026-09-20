/**
 * Shift+Alt+Up/Down ("Add Cursor Above/Below") — VS Code's own Linux
 * keybinding for this (not Ctrl+Alt+Up/Down, its Windows/Mac one):
 * Ctrl+Alt+Up/Down is GNOME's own default "switch workspace" shortcut,
 * intercepted by the compositor before Opus ever sees it — confirmed
 * live via `gsettings get org.gnome.desktop.wm.keybindings
 * switch-to-workspace-up`. See cursor-controller.vala's own comment on
 * this check for the full reasoning.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/add_cursor_vertical/shift_alt_down_adds_a_cursor_below_at_the_same_column", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 100);
            opus.new_file ();
            opus.editor_write ("abc\ndefg\nhi");
            opus.set_cursors ({ {0, 1} }); // column 1 on line 0

            opus.type_cmd ("shift+alt+down");

            opus.assert_cursors ({ {1, 1}, {5, 5} }); // "defg" starts at offset 4, column 1 is offset 5

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/add_cursor_vertical/shift_alt_up_adds_a_cursor_above_at_the_same_column", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 100);
            opus.new_file ();
            opus.editor_write ("abc\ndefg\nhi");
            opus.set_cursors ({ {1, 1} }); // column 1 on line 1 ("defg"), offset 5

            opus.type_cmd ("shift+alt+up");

            // normalize() preserves each survivor's own relative order
            // rather than re-sorting by position — the original cursor
            // (offset 5) stays first, the newly-added one (offset 1,
            // numerically earlier in the text) comes after it.
            opus.assert_cursors ({ {5, 5}, {1, 1} });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
