/**
 * Selections, carets and the overtype block under `editor.word_wrap`:
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

private const string WRAP_ON = "{ \"editor.word_wrap\": true }";

private SystemTestSession launch (uint display, string? settings_json) throws Error {
    return new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), display, null, settings_json);
}

private SystemTestSession? wrapped = null;

/** One Opus for every wrap-on case, launched on first use — same reasoning as wrapped-movement-test's own: the ~1s Broadway takes to allocate the editor is paid once, not per case. Each case opens and closes its own tab. */
private SystemTestSession wrapped_session () throws Error {
    if (wrapped == null) {
        wrapped = launch (106, WRAP_ON);
    }
    return wrapped;
}

/** A fresh tab holding `text` in the shared wrap-on Opus. */
private SystemTestSession open_wrapped (string text) throws Error {
    var opus = wrapped_session ();
    opus.new_file ();
    opus.editor_write (text);
    return opus;
}

private void close_current_tab (SystemTestSession opus) throws Error {
    opus.close_tab (opus.active_tab ());
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
            var opus = open_wrapped (LONG_LINE + "\n\nshort");

            opus.select_all ();
            let_a_frame_paint ();

            opus.assert_cursors ({ {0, LONG_LINE.length + 7} });
            opus.assert_editor_text (LONG_LINE + "\n\nshort");

            close_current_tab (opus);
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_selection/selection_end_on_every_row_and_wrap_boundary", () => {
        try {
            var opus = open_wrapped (LONG_LINE);

            sweep_selection_end (opus, LONG_LINE.length);
            let_a_frame_paint ();

            opus.assert_cursors ({ {0, LONG_LINE.length} });
            opus.type ("!");
            opus.assert_editor_text ("!"); // the selection was real: typing replaced it

            close_current_tab (opus);
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_selection/selection_starting_mid_row_through_a_forced_break", () => {
        try {
            var opus = open_wrapped (LONG_WORD + "\n" + LONG_LINE);

            // From inside the long word's first row, through its forced
            // mid-word breaks and the newline, into the next line's rows.
            int[] anchors = { 10 };
            int[] positions = { LONG_WORD.length + 1 + 40 };
            opus.set_cursor_offsets (anchors, positions);
            let_a_frame_paint ();

            opus.assert_cursors ({ {10, LONG_WORD.length + 1 + 40} });

            close_current_tab (opus);
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_selection/multi_cursor_selections_with_a_selected_empty_line", () => {
        try {
            var opus = open_wrapped (LONG_LINE + "\n\n" + LONG_LINE);

            // Cursor 1: the wrapped first line through its newline and
            // the empty line's own newline (the zero-width marker rows);
            // cursor 2: a slice of the second wrapped line.
            int[] anchors = { 0, LONG_LINE.length + 2 + 5 };
            int[] positions = { LONG_LINE.length + 2, LONG_LINE.length + 2 + 120 };
            opus.set_cursor_offsets (anchors, positions);
            let_a_frame_paint ();

            opus.assert_cursors ({ {0, LONG_LINE.length + 2}, {LONG_LINE.length + 2 + 5, LONG_LINE.length + 2 + 120} });

            close_current_tab (opus);
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_selection/wrap_off_sweep_is_unaffected", () => {
        try {
            var opus = launch (110, null); // defaults: editor.word_wrap false — its own Opus
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
            var opus = open_wrapped (LONG_WORD);
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

            opus.type_cmd ("insert"); // back to insert mode for whoever shares this Opus next
            close_current_tab (opus);
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    int status = Test.run ();
    wrapped?.close ();
    return status;
}
