/**
 * Up/Down/Home/End under `editor.word_wrap`: each moves by *display row*
 * (CodeEditorSourceView's own IDisplayRows over GTK's display lines,
 * through CursorCollection.move_by_row()), so a wrapped line's own
 * continuation rows are reachable from the keyboard — where they used
 * to be skipped as the model stepped by paragraph.
 *
 * Where exactly a line wraps depends on the window's width, which this
 * harness doesn't control, so every assertion is width-independent:
 * "landed inside the same paragraph" rather than "landed at offset N".
 * The exact per-row arithmetic is covered by the cursor-collection model
 * tests with a fixed-width row stand-in; what this adds is the real GTK
 * row adapter on real wrapped text, and wrap-off parity with the same
 * keys.
 */

private const string PARAGRAPH =
    "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu "
  + "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu";

private const string WRAP_ON = "{ \"editor.word_wrap\": true }";

private SystemTestSession launch (uint display, string? settings_json) throws Error {
    return new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), display, null, settings_json);
}

private SystemTestSession? wrapped = null;

/**
 * One Opus for every wrap-on case, launched on first use. What each
 * case needs — an editor that has really wrapped — is what
 * wait_until_wrapped() pays ~1s for per launch (see its doc comment);
 * once the one CodeEditor widget is allocated, every later tab wraps at
 * once. Each case still opens its own fresh tab and closes it.
 */
private SystemTestSession wrapped_session () throws Error {
    if (wrapped == null) {
        wrapped = launch (107, WRAP_ON);
    }
    return wrapped;
}

private int primary_position (SystemTestSession opus) throws Error {
    int[] anchors;
    int[] positions;
    opus.active_cursors (out anchors, out positions);
    return positions[0];
}

private string three_paragraphs () {
    return PARAGRAPH + "\n" + PARAGRAPH + "\n" + PARAGRAPH;
}

/**
 * Blocks until the editor really wraps PARAGRAPH — until End from its
 * start lands before its end. Headless Broadway hands the text view its
 * real width only some frames after a tab opens (measured by hand:
 * ~1s with no browser attached), and until then GtkTextView's layout
 * has no width to wrap at, so a key pressed too early moves by
 * paragraph exactly as with wrap off. A real display allocates within
 * the next frame; this is the harness's own latency, not the editor's.
 */
private void wait_until_wrapped (SystemTestSession opus) throws Error {
    int64 deadline = get_monotonic_time () + 5 * 1000 * 1000;
    while (get_monotonic_time () < deadline) {
        opus.set_cursors ({ {0, 0} });
        opus.type_cmd ("end");
        if (primary_position (opus) < PARAGRAPH.length) {
            return;
        }
        Thread.usleep (50 * 1000);
    }
    error ("the editor never wrapped PARAGRAPH within 5s");
}

/** A fresh tab holding `text`, wrapped and ready — the common opening of every wrap-on case. */
private SystemTestSession open_wrapped (string text) throws Error {
    var opus = wrapped_session ();
    opus.new_file ();
    opus.editor_write (text);
    wait_until_wrapped (opus);
    return opus;
}

private void close_current_tab (SystemTestSession opus) throws Error {
    opus.close_tab (opus.active_tab ());
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/wrapped_movement/down_from_the_first_row_stays_inside_the_wrapped_paragraph", () => {
        try {
            var opus = open_wrapped (three_paragraphs ());
            opus.set_cursors ({ {0, 4} });

            opus.type_cmd ("down");

            int landed = primary_position (opus);
            assert_cmpint (landed, CompareOperator.GT, 4);
            assert_cmpint (landed, CompareOperator.LE, PARAGRAPH.length); // a continuation row of paragraph 1 — not paragraph 2

            close_current_tab (opus);
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_movement/down_visits_more_rows_than_there_are_paragraphs_and_reaches_the_end", () => {
        try {
            var opus = open_wrapped (three_paragraphs ());
            opus.set_cursors ({ {0, 4} });

            var distinct = new GenericArray<int> ();
            for (int i = 0; i < 12; i++) {
                opus.type_cmd ("down");
                int position = primary_position (opus);
                if (distinct.length == 0 || distinct[distinct.length - 1] != position) {
                    distinct.add (position);
                }
            }

            assert_cmpint ((int) distinct.length, CompareOperator.GT, 3); // paragraph-sized jumps would give exactly 3
            assert_cmpint (distinct[distinct.length - 1], CompareOperator.EQ, three_paragraphs ().length);

            close_current_tab (opus);
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_movement/up_from_the_end_retraces_to_the_start", () => {
        try {
            var opus = open_wrapped (three_paragraphs ());
            opus.set_cursors ({ {2, PARAGRAPH.length} });

            for (int i = 0; i < 12; i++) {
                opus.type_cmd ("up");
            }

            opus.assert_cursors ({ {0, 0} });

            close_current_tab (opus);
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_movement/end_and_home_stop_at_the_rows_own_edges", () => {
        try {
            var opus = open_wrapped (PARAGRAPH);
            opus.set_cursors ({ {0, 0} });

            opus.type_cmd ("end");
            int row_end = primary_position (opus);
            assert_cmpint (row_end, CompareOperator.GT, 0);
            assert_cmpint (row_end, CompareOperator.LT, PARAGRAPH.length); // the first row's end, not the paragraph's

            opus.set_cursors ({ {0, PARAGRAPH.length - 1} });
            opus.type_cmd ("home");
            int row_start = primary_position (opus);
            assert_cmpint (row_start, CompareOperator.GT, 0); // the last row's start, not the paragraph's

            opus.type_cmd ("end");
            opus.assert_cursors ({ {PARAGRAPH.length, PARAGRAPH.length} }); // on the last row, End is the paragraph end

            close_current_tab (opus);
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_movement/shift_down_extends_onto_the_next_row", () => {
        try {
            var opus = open_wrapped (three_paragraphs ());
            opus.set_cursors ({ {0, 0} });

            opus.type_cmd ("shift+down");

            int[] anchors;
            int[] positions;
            opus.active_cursors (out anchors, out positions);
            assert_cmpint (anchors[0], CompareOperator.EQ, 0);
            assert_cmpint (positions[0], CompareOperator.GT, 0);
            assert_cmpint (positions[0], CompareOperator.LE, PARAGRAPH.length);

            close_current_tab (opus);
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/wrapped_movement/with_wrap_off_down_still_moves_by_paragraph", () => {
        try {
            var opus = launch (109, null); // defaults: editor.word_wrap false — its own Opus, nothing to wait for
            opus.new_file ();
            opus.editor_write (three_paragraphs ());
            opus.set_cursors ({ {0, 4} });

            opus.type_cmd ("down");

            opus.assert_cursors ({ {PARAGRAPH.length + 1 + 4, PARAGRAPH.length + 1 + 4} }); // column 4 of paragraph 2, exactly as before

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    int status = Test.run ();
    wrapped?.close ();
    return status;
}
