/**
 * Selections, carets and the overtype block under `editor.wordWrap`:
 * every one is hand-painted (CodeEditorSelections, CodeEditorSourceView)
 * one display row at a time, and a logical line that wraps has several.
 * Each scenario seeds that painting through the real D-Bus surface and
 * then checks the editor is still alive and consistent — the cursor set
 * reads back as seeded, the text is intact, a keystroke still lands.
 *
 * Honest scope: nothing here reads pixels. What a scenario does verify
 * is that the per-row walk (`CodeEditorSourceView.next_row_start()`/
 * `row_band()`, `CodeEditorSelections.paint_rows()`) runs over real
 * wrapped rows in a real GTK process without tripping an iter
 * assertion or a GTK-level critical — a crash there takes the process
 * down and the next D-Bus call fails. Painting happens on the frame
 * clock between calls, so a sweep over many offsets is what gives the
 * painter rows to walk; which exact offsets got a frame isn't
 * deterministic, and the one-frame wait before each final assertion
 * only guarantees the *last* state painted. The pixel geometry itself
 * was checked against GTK's own display-line API by hand (see the
 * doc comments on the methods named above).
 */

// Long enough to wrap into several rows at any plausible window width
// (the default is 900px, minus the sidebar, at ~8px per character).
private const string LONG_LINE =
    "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu "
  + "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu "
  + "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu";

// One unbreakable word, so WORD_CHAR has to split it mid-word — the
// row then ends on a real glyph (plus Pango's inserted hyphen), the
// case the overtype block's width guard is for.
private const string LONG_WORD =
    "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  + "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  + "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";

private const string WRAP_ON = "{ \"editor.wordWrap\": true }";

private SystemTestSession launch (string? settings_json) throws Error {
    return new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 106, null, settings_json);
}

/** One frame-clock tick's worth of wall time, so whatever state was seeded last has actually been painted before the assertion that follows. */
private void let_a_frame_paint () {
    Thread.usleep (100 * 1000);
}

/** Selects [0, end) for every `end` up to `length`, one at a time — so the selection's end lands on every row, including exactly at each wrap boundary, whichever columns those turn out to be. */
private void sweep_selection_end (SystemTestSession opus, int length) throws Error {
    for (int end = 1; end <= length; end++) {
        opus.set_selections ({ {0, 0, end} });
    }
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/wrapped_selection/whole_wrapped_line_stays_selected", () => {
        try {
            var opus = launch (WRAP_ON);
            opus.new_file ();
            opus.editor_write (LONG_LINE + "\n\nshort");

            opus.select_all ();
            let_a_frame_paint ();

            opus.assert_cursors ({ {0, LONG_LINE.length + 7} });
            opus.assert_editor_text (LONG_LINE + "\n\nshort");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_selection/selection_end_on_every_row_and_wrap_boundary", () => {
        try {
            var opus = launch (WRAP_ON);
            opus.new_file ();
            opus.editor_write (LONG_LINE);

            sweep_selection_end (opus, LONG_LINE.length);
            let_a_frame_paint ();

            opus.assert_cursors ({ {0, LONG_LINE.length} });
            opus.type ("!");
            opus.assert_editor_text ("!"); // the selection was real: typing replaced it

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_selection/selection_starting_mid_row_through_a_forced_break", () => {
        try {
            var opus = launch (WRAP_ON);
            opus.new_file ();
            opus.editor_write (LONG_WORD + "\n" + LONG_LINE);

            // From inside the long word's first row, through its forced
            // mid-word breaks and the newline, into the next line's rows.
            int[] anchors = { 10 };
            int[] positions = { LONG_WORD.length + 1 + 40 };
            opus.set_cursor_offsets (anchors, positions);
            let_a_frame_paint ();

            opus.assert_cursors ({ {10, LONG_WORD.length + 1 + 40} });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_selection/multi_cursor_selections_with_a_selected_empty_line", () => {
        try {
            var opus = launch (WRAP_ON);
            opus.new_file ();
            opus.editor_write (LONG_LINE + "\n\n" + LONG_LINE);

            // Cursor 1: the wrapped first line through its newline and
            // the empty line's own newline (the zero-width marker rows);
            // cursor 2: a slice of the second wrapped line.
            int[] anchors = { 0, LONG_LINE.length + 2 + 5 };
            int[] positions = { LONG_LINE.length + 2, LONG_LINE.length + 2 + 120 };
            opus.set_cursor_offsets (anchors, positions);
            let_a_frame_paint ();

            opus.assert_cursors ({ {0, LONG_LINE.length + 2}, {LONG_LINE.length + 2 + 5, LONG_LINE.length + 2 + 120} });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_selection/wrap_off_sweep_is_unaffected", () => {
        try {
            var opus = launch (null); // defaults: editor.wordWrap false
            opus.new_file ();
            opus.editor_write (LONG_LINE);

            sweep_selection_end (opus, LONG_LINE.length);
            let_a_frame_paint ();

            opus.assert_cursors ({ {0, LONG_LINE.length} });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_selection/overtype_caret_on_every_glyph_of_a_force_wrapped_word", () => {
        try {
            var opus = launch (WRAP_ON);
            opus.new_file ();
            opus.editor_write (LONG_WORD);
            opus.type_cmd ("insert");

            // Every offset, so the caret lands on each row's last glyph
            // (where the next character sits on the row below) as well
            // as on every row's first.
            for (int column = 0; column < LONG_WORD.length; column++) {
                opus.set_cursors ({ {0, column} });
            }
            let_a_frame_paint ();

            opus.set_cursors ({ {0, 0} });
            opus.type ("Y");
            opus.assert_editor_text ("Y" + LONG_WORD.substring (1)); // still overtyping, not inserting

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
