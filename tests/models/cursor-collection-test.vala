private void test_default_state_is_a_single_collapsed_cursor_at_start () {
    var cc = new CursorCollection ();

    assert_cmpint (cc.count, CompareOperator.EQ, 1);
    assert_cmpint (cc.primary.anchor_offset, CompareOperator.EQ, 0);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 0);
    assert_true (cc.primary.is_empty);
}

private void test_move_right_and_left () {
    var cc = new CursorCollection ();
    string text = "hello world";

    cc.move (CursorMoveOp.RIGHT, false, text);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 1);

    cc.move (CursorMoveOp.LEFT, false, text);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 0);
}

private void test_move_right_clamps_at_end_of_text () {
    var cc = new CursorCollection ();
    string text = "hi";

    cc.move (CursorMoveOp.RIGHT, false, text);
    cc.move (CursorMoveOp.RIGHT, false, text);
    cc.move (CursorMoveOp.RIGHT, false, text);

    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 2);
}

private void test_move_left_clamps_at_start_of_text () {
    var cc = new CursorCollection ();
    string text = "hi";

    cc.move (CursorMoveOp.LEFT, false, text);

    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 0);
}

private void test_extending_grows_the_selection_and_plain_move_collapses_it () {
    var cc = new CursorCollection ();
    string text = "hello world";

    cc.move (CursorMoveOp.RIGHT, true, text);
    cc.move (CursorMoveOp.RIGHT, true, text);
    cc.move (CursorMoveOp.RIGHT, true, text);
    assert_cmpint (cc.primary.anchor_offset, CompareOperator.EQ, 0);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 3);
    assert_false (cc.primary.is_empty);

    // a plain (non-extending) Right on a selection collapses to its end,
    // it doesn't move one further character past it
    cc.move (CursorMoveOp.RIGHT, false, text);
    assert_true (cc.primary.is_empty);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 3);
}

private void test_plain_left_on_a_selection_collapses_to_its_start () {
    var cc = new CursorCollection ();
    string text = "hello world";

    cc.move (CursorMoveOp.RIGHT, false, text); // 0 -> 1
    cc.move (CursorMoveOp.RIGHT, true, text); // 1 -> [1,2)

    cc.move (CursorMoveOp.LEFT, false, text);
    assert_true (cc.primary.is_empty);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 1);
}

private void test_home_and_end_move_within_the_current_line () {
    var cc = new CursorCollection ();
    string text = "first line\nsecond line";
    var rows = new ParagraphRows (text);

    cc.move (CursorMoveOp.DOCUMENT_END, false, text);
    cc.move_by_row (RowMoveOp.HOME, false, text, rows, 4);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 11); // start of "second line"

    cc.move_by_row (RowMoveOp.END, false, text, rows, 4);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, text.char_count ());
}

private void test_up_down_remembers_the_horizontal_column_across_shorter_lines () {
    var cc = new CursorCollection ();
    string text = "ab\na\nabcd";
    var rows = new ParagraphRows (text);

    cc.move (CursorMoveOp.RIGHT, false, text);
    cc.move (CursorMoveOp.RIGHT, false, text); // column 2, end of "ab"

    cc.move_by_row (RowMoveOp.DOWN, false, text, rows, 4); // "a" is too short — clamps to column 1
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 4);

    cc.move_by_row (RowMoveOp.DOWN, false, text, rows, 4); // "abcd" is long enough — back to column 2
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 7);
}

/**
 * Every `width` characters of a paragraph start a new display row — a
 * stand-in for the View's real word wrap (CodeEditorSourceView's own
 * IDisplayRows), so row-based movement is testable with no display. A
 * non-last row's `end` is the position before the next row's first
 * character, per IDisplayRows' own contract.
 */
private class FixedWidthRows : Object, IDisplayRows {
    private ParagraphRows paragraphs;
    private int width;

    public FixedWidthRows (string text, int width) {
        paragraphs = new ParagraphRows (text);
        this.width = width;
    }

    public void row_bounds (int offset, out int start, out int end) {
        int paragraph_start;
        int paragraph_end;
        paragraphs.row_bounds (offset, out paragraph_start, out paragraph_end);
        int row_index = (offset - paragraph_start) / width;
        bounds_of_row (paragraph_start, paragraph_end, row_index, out start, out end);
    }

    public bool row_above (int offset, out int start, out int end) {
        int paragraph_start;
        int paragraph_end;
        paragraphs.row_bounds (offset, out paragraph_start, out paragraph_end);
        int row_index = (offset - paragraph_start) / width;
        if (row_index > 0) {
            bounds_of_row (paragraph_start, paragraph_end, row_index - 1, out start, out end);
            return true;
        }
        if (!paragraphs.row_above (offset, out paragraph_start, out paragraph_end)) {
            start = 0;
            end = 0;
            return false;
        }
        bounds_of_row (paragraph_start, paragraph_end, row_count (paragraph_start, paragraph_end) - 1, out start, out end);
        return true;
    }

    public bool row_below (int offset, out int start, out int end) {
        int paragraph_start;
        int paragraph_end;
        paragraphs.row_bounds (offset, out paragraph_start, out paragraph_end);
        int row_index = (offset - paragraph_start) / width;
        if (row_index < row_count (paragraph_start, paragraph_end) - 1) {
            bounds_of_row (paragraph_start, paragraph_end, row_index + 1, out start, out end);
            return true;
        }
        if (!paragraphs.row_below (offset, out paragraph_start, out paragraph_end)) {
            start = 0;
            end = 0;
            return false;
        }
        bounds_of_row (paragraph_start, paragraph_end, 0, out start, out end);
        return true;
    }

    private int row_count (int paragraph_start, int paragraph_end) {
        return int.max (1, (paragraph_end - paragraph_start + width - 1) / width);
    }

    private void bounds_of_row (int paragraph_start, int paragraph_end, int row_index, out int start, out int end) {
        start = paragraph_start + row_index * width;
        bool last_row = row_index == row_count (paragraph_start, paragraph_end) - 1;
        end = last_row ? paragraph_end : start + width - 1;
    }
}

// The user's own repro: three paragraphs, each wrapping into two rows,
// Down ×5 from right after the first word visits every one of the six
// rows and ends at the very end of the text — where Opus used to make
// three paragraph-sized jumps and then stall.
//
//   P1 rows [0,9] [10,14]   P2 rows [15,24] [25,29]   P3 rows [30,39] [40,44]
private void test_down_visits_every_wrapped_row_in_turn () {
    var cc = new CursorCollection ();
    string text = "aaaa aaaa aaaa\nbbbb bbbb bbbb\ncccc cccc cccc";
    var rows = new FixedWidthRows (text, 10);
    cc.set_cursors ({ new Cursor (4) });

    int[] visited = {};
    for (int i = 0; i < 5; i++) {
        cc.move_by_row (RowMoveOp.DOWN, false, text, rows, 4);
        visited += cc.primary.position_offset;
    }

    assert_cmpint (visited[0], CompareOperator.EQ, 14); // P1's second row — column 4 is its end
    assert_cmpint (visited[1], CompareOperator.EQ, 19); // P2's first row, column 4 again
    assert_cmpint (visited[2], CompareOperator.EQ, 29);
    assert_cmpint (visited[3], CompareOperator.EQ, 34);
    assert_cmpint (visited[4], CompareOperator.EQ, 44); // the end of the text, after exactly five presses
}

private void test_up_retraces_the_wrapped_rows_back_to_the_start () {
    var cc = new CursorCollection ();
    string text = "aaaa aaaa aaaa\nbbbb bbbb bbbb\ncccc cccc cccc";
    var rows = new FixedWidthRows (text, 10);
    cc.set_cursors ({ new Cursor (4) });
    for (int i = 0; i < 5; i++) {
        cc.move_by_row (RowMoveOp.DOWN, false, text, rows, 4);
    }

    for (int i = 0; i < 5; i++) {
        cc.move_by_row (RowMoveOp.UP, false, text, rows, 4);
    }

    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 4);
}

private void test_goal_column_survives_a_shorter_wrapped_row () {
    var cc = new CursorCollection ();
    string text = "abcdefghij"; // rows [0,3] [4,7] [8,10]
    var rows = new FixedWidthRows (text, 4);
    cc.set_cursors ({ new Cursor (7) }); // column 3 of the second row

    cc.move_by_row (RowMoveOp.DOWN, false, text, rows, 4);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 10); // the last row has only two columns

    cc.move_by_row (RowMoveOp.UP, false, text, rows, 4);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 7); // back at column 3, not 2
}

private void test_home_forgets_the_goal_column () {
    var cc = new CursorCollection ();
    string text = "abcdefghij";
    var rows = new FixedWidthRows (text, 4);
    cc.set_cursors ({ new Cursor (7) });
    cc.move_by_row (RowMoveOp.DOWN, false, text, rows, 4); // clamped to 10, goal column 3 remembered

    cc.move_by_row (RowMoveOp.HOME, false, text, rows, 4);
    cc.move_by_row (RowMoveOp.UP, false, text, rows, 4);

    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 4); // column 0 of the row above — Home reset the goal
}

private void test_up_on_the_first_row_goes_to_the_buffer_start_and_down_on_the_last_to_its_end () {
    var cc = new CursorCollection ();
    string text = "abcdef"; // rows [0,2] [3,6]
    var rows = new FixedWidthRows (text, 3);
    cc.set_cursors ({ new Cursor (4) });

    cc.move_by_row (RowMoveOp.UP, false, text, rows, 4);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 1);
    cc.move_by_row (RowMoveOp.UP, false, text, rows, 4);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 0);

    cc.move_by_row (RowMoveOp.DOWN, false, text, rows, 4);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 4); // column 1 again: the goal column survived the edge
    cc.move_by_row (RowMoveOp.DOWN, false, text, rows, 4);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 6);
}

private void test_down_onto_a_trailing_empty_line () {
    var cc = new CursorCollection ();
    string text = "abc\n";
    cc.set_cursors ({ new Cursor (1) });

    cc.move_by_row (RowMoveOp.DOWN, false, text, new ParagraphRows (text), 4);

    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 4);
}

private void test_home_and_end_stay_within_the_wrapped_row () {
    var cc = new CursorCollection ();
    string text = "abcdefghij"; // rows [0,3] [4,7] [8,10]
    var rows = new FixedWidthRows (text, 4);
    cc.set_cursors ({ new Cursor (6) });

    cc.move_by_row (RowMoveOp.HOME, false, text, rows, 4);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 4); // the row's start, not the paragraph's

    cc.move_by_row (RowMoveOp.END, false, text, rows, 4);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 7); // the row's end, not the paragraph's
}

private void test_end_on_the_last_row_reaches_the_paragraph_end () {
    var cc = new CursorCollection ();
    string text = "abcdefghij\nk";
    var rows = new FixedWidthRows (text, 4);
    cc.set_cursors ({ new Cursor (9) });

    cc.move_by_row (RowMoveOp.END, false, text, rows, 4);

    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 10); // the newline's position
}

private void test_shift_down_extends_across_wrapped_rows () {
    var cc = new CursorCollection ();
    string text = "abcdefghij";
    var rows = new FixedWidthRows (text, 4);
    cc.set_cursors ({ new Cursor (2) });

    cc.move_by_row (RowMoveOp.DOWN, true, text, rows, 4);

    assert_cmpint (cc.primary.anchor_offset, CompareOperator.EQ, 2);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 6);
}

private void test_vertical_moves_count_a_tab_as_a_full_tab_stop () {
    var cc = new CursorCollection ();
    string text = "\tab\n123456789";
    cc.set_cursors ({ new Cursor (3) }); // after "b": visible column 4 + 2 = 6

    cc.move_by_row (RowMoveOp.DOWN, false, text, new ParagraphRows (text), 4);

    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 10); // column 6 of the next line, not character 3
}

private void test_down_lands_on_the_nearest_column_when_a_tab_straddles_the_goal () {
    var cc = new CursorCollection ();
    string text = "abc\n\tx";
    cc.set_cursors ({ new Cursor (3) }); // visible column 3; the tab below spans columns 0-4

    cc.move_by_row (RowMoveOp.DOWN, false, text, new ParagraphRows (text), 4);

    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 5); // after the tab (column 4, one away) rather than before it (column 0, three away)
}

private void test_word_jump () {
    var cc = new CursorCollection ();
    string text = "hello world";

    cc.move (CursorMoveOp.WORD_RIGHT, false, text);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 5);

    cc.move (CursorMoveOp.WORD_RIGHT, false, text);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 11);

    cc.move (CursorMoveOp.WORD_LEFT, false, text);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 6);
}

private void test_normalize_merges_touching_collapsed_cursors () {
    var cc = new CursorCollection ();
    var a = new Cursor (3);
    var b = new Cursor (3);

    cc.set_cursors ({ a, b });

    assert_cmpint (cc.count, CompareOperator.EQ, 1);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 3);
}

private void test_normalize_merges_overlapping_selections_into_their_union () {
    var cc = new CursorCollection ();
    var a = new Cursor (0);
    a.position_offset = 5;
    var b = new Cursor (3);
    b.position_offset = 8;

    cc.set_cursors ({ a, b });

    assert_cmpint (cc.count, CompareOperator.EQ, 1);
    assert_cmpint (cc.primary.selection_start, CompareOperator.EQ, 0);
    assert_cmpint (cc.primary.selection_end, CompareOperator.EQ, 8);
}

private void test_normalize_keeps_merely_touching_non_empty_selections_separate () {
    var cc = new CursorCollection ();
    var a = new Cursor (0);
    a.position_offset = 5;
    var b = new Cursor (5);
    b.position_offset = 8;

    cc.set_cursors ({ a, b });

    assert_cmpint (cc.count, CompareOperator.EQ, 2);
}

private void test_normalize_merge_prefers_the_last_added_cursors_direction () {
    var cc = new CursorCollection ();
    var a = new Cursor (0); // [0,5), forward
    a.position_offset = 5;
    var b = new Cursor (8); // [3,8), backward — this is the last-added one
    b.position_offset = 3;

    cc.set_cursors ({ a, b }, b);

    assert_cmpint (cc.count, CompareOperator.EQ, 1);
    assert_cmpint (cc.primary.anchor_offset, CompareOperator.EQ, 8);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 0);
}

private void test_add_cursor_below_preserves_the_horizontal_column () {
    var cc = new CursorCollection ();
    string text = "abc\ndefg\nhi";

    cc.move (CursorMoveOp.RIGHT, false, text); // column 1 on line 0

    cc.add_cursor_below (text, 4);

    assert_cmpint (cc.count, CompareOperator.EQ, 2);
    assert_cmpint (cc.at (1).position_offset, CompareOperator.EQ, 5); // column 1 on line 1 ("defg" starts at 4)
}

// Shift+Alt+Down adds the cursor on the paragraph below even where
// the View wraps — VS Code's own insertCursorBelow default
// (`useLogicalLine = true`); add_cursor_below never takes rows at all.
private void test_add_cursor_below_lands_on_the_next_paragraph_not_a_wrapped_row () {
    var cc = new CursorCollection ();
    string text = "aaaa aaaa aaaa\nbbbb bbbb bbbb";
    cc.set_cursors ({ new Cursor (4) });

    cc.add_cursor_below (text, 4);

    assert_cmpint (cc.at (1).position_offset, CompareOperator.EQ, 19); // column 4 of "bbbb …", not of a second row of "aaaa …"
}

private void test_extend_last_added_cursor_grows_it_into_a_selection () {
    var cc = new CursorCollection ();
    string text = "aaaa bbbb cccc";

    cc.add_cursor_at_click (2); // second cursor, collapsed at offset 2
    cc.extend_last_added_cursor (7);

    assert_cmpint (cc.count, CompareOperator.EQ, 2);
    assert_cmpint (cc.at (1).anchor_offset, CompareOperator.EQ, 2);
    assert_cmpint (cc.at (1).position_offset, CompareOperator.EQ, 7);
}

// Reproduces a scenario checked by hand: an Alt-drag's own selection
// overlapping an already-selected cursor merges into their union, the
// same way any other overlap does (Ctrl+D, box-select, ...) —
// deliberately not special-cased to instead discard the older
// selection, to keep the app's own overlap behavior consistent with
// itself rather than picking a different rule just for Alt-drag.
private void test_extend_last_added_cursor_overlapping_another_cursor_merges_into_their_union () {
    var cc = new CursorCollection ();
    string text = "aaaa\nbbbb\ncccc";

    var bbbb = new Cursor (5);
    bbbb.position_offset = 9; // "[bbbb]" selected, offsets 5-9
    cc.set_cursors ({ bbbb });

    cc.add_cursor_at_click (2); // "aa|aa\nbbbb\ncccc"
    cc.extend_last_added_cursor (7); // drags to (1, 2) -> offset 7, overlapping bbbb's own [5, 9)

    assert_cmpint (cc.count, CompareOperator.EQ, 1);
    assert_cmpint (cc.primary.anchor_offset, CompareOperator.EQ, 2);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 9);
}

private void test_expand_last_added_cursor_to_word_selects_the_word_touching_it () {
    var cc = new CursorCollection ();
    string text = "cat dog bird";

    cc.add_cursor_at_click (5); // inside "dog"
    cc.expand_last_added_cursor_to_word (text);

    assert_cmpint (cc.count, CompareOperator.EQ, 2);
    assert_cmpint (cc.at (1).anchor_offset, CompareOperator.EQ, 4);
    assert_cmpint (cc.at (1).position_offset, CompareOperator.EQ, 7);
}

// The caret lands right after the line's own last character, not past
// its trailing newline — matches a plain triple-click's own existing,
// native behavior (checked by hand: the caret stays on the same line,
// not the one below), which line_end() itself already gives for free.
private void test_expand_last_added_cursor_to_line_selects_the_whole_line_without_its_trailing_newline () {
    var cc = new CursorCollection ();
    string text = "aaaa\nbbbb\ncccc";

    cc.add_cursor_at_click (6); // inside "bbbb"
    cc.expand_last_added_cursor_to_line (text);

    assert_cmpint (cc.count, CompareOperator.EQ, 2);
    assert_cmpint (cc.at (1).anchor_offset, CompareOperator.EQ, 5);
    assert_cmpint (cc.at (1).position_offset, CompareOperator.EQ, 9);
}

private void test_add_cursor_at_next_match_expands_word_then_finds_the_next_occurrence () {
    var cc = new CursorCollection ();
    string text = "cat dog cat bird cat";

    cc.add_cursor_at_next_match (text); // first press: select the word under the caret
    assert_cmpint (cc.count, CompareOperator.EQ, 1);
    assert_cmpint (cc.primary.selection_start, CompareOperator.EQ, 0);
    assert_cmpint (cc.primary.selection_end, CompareOperator.EQ, 3);

    cc.add_cursor_at_next_match (text); // second press: find the next "cat"
    assert_cmpint (cc.count, CompareOperator.EQ, 2);
    assert_cmpint (cc.at (1).selection_start, CompareOperator.EQ, 8);
    assert_cmpint (cc.at (1).selection_end, CompareOperator.EQ, 11);
}

private void test_select_all_occurrences_selects_every_match_at_once () {
    var cc = new CursorCollection ();
    string text = "cat dog cat bird cat";
    var primary = new Cursor (0);
    primary.position_offset = 3;
    cc.set_cursors ({ primary });

    cc.select_all_occurrences (text);

    assert_cmpint (cc.count, CompareOperator.EQ, 3);
    assert_cmpint (cc.at (0).selection_start, CompareOperator.EQ, 0);
    assert_cmpint (cc.at (1).selection_start, CompareOperator.EQ, 8);
    assert_cmpint (cc.at (2).selection_start, CompareOperator.EQ, 17);
}

private void test_box_select_creates_one_cursor_per_line_at_the_same_column_range () {
    var cc = new CursorCollection ();
    string text = "abcdef\nabcdef\nabcdef";

    cc.box_select (1, 17, text); // line 0 col 1 -> line 2 col 3

    assert_cmpint (cc.count, CompareOperator.EQ, 3);
    assert_cmpint (cc.at (0).selection_start, CompareOperator.EQ, 1);
    assert_cmpint (cc.at (0).selection_end, CompareOperator.EQ, 3);
    assert_cmpint (cc.at (1).selection_start, CompareOperator.EQ, 8);
    assert_cmpint (cc.at (1).selection_end, CompareOperator.EQ, 10);
    assert_cmpint (cc.at (2).selection_start, CompareOperator.EQ, 15);
    assert_cmpint (cc.at (2).selection_end, CompareOperator.EQ, 17);
}

private void test_add_and_remove_cursor_at_click () {
    var cc = new CursorCollection ();

    cc.add_cursor_at_click (5);
    assert_cmpint (cc.count, CompareOperator.EQ, 2);
    assert_cmpint (cc.at (1).position_offset, CompareOperator.EQ, 5);

    cc.remove_cursor_at (1);
    assert_cmpint (cc.count, CompareOperator.EQ, 1);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 0);
}

private void test_remove_cursor_at_never_removes_the_last_cursor () {
    var cc = new CursorCollection ();

    cc.remove_cursor_at (0);

    assert_cmpint (cc.count, CompareOperator.EQ, 1);
}

private void test_compute_and_apply_single_cursor_insert () {
    var cc = new CursorCollection ();
    string text = "hello";
    cc.move (CursorMoveOp.RIGHT, false, text);

    Cursor[] to_remove;
    var edits = cc.compute_edits (EditIntent.INSERT, "X", text, out to_remove);

    assert_cmpint (edits.length, CompareOperator.EQ, 1);
    assert_cmpint (to_remove.length, CompareOperator.EQ, 0);
    assert_cmpint (edits[0].edit.start_offset, CompareOperator.EQ, 1);
    assert_cmpint (edits[0].edit.end_offset, CompareOperator.EQ, 1);
    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, "X");

    cc.apply_edit_results (edits, to_remove);

    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 2);
    assert_true (cc.primary.is_empty);
}

private void test_delete_left_at_document_start_produces_no_edit () {
    var cc = new CursorCollection ();
    string text = "hello";

    Cursor[] to_remove;
    var edits = cc.compute_edits (EditIntent.DELETE_LEFT, "", text, out to_remove);

    assert_cmpint (edits.length, CompareOperator.EQ, 0);
    assert_cmpint (to_remove.length, CompareOperator.EQ, 0);

    cc.apply_edit_results (edits, to_remove);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 0);
}

private void test_multi_cursor_simultaneous_insert_repositions_every_cursor () {
    var cc = new CursorCollection ();
    string text = "aaa";
    var c0 = new Cursor (0);
    var c1 = new Cursor (1);
    var c2 = new Cursor (2);
    cc.set_cursors ({ c0, c1, c2 });

    Cursor[] to_remove;
    var edits = cc.compute_edits (EditIntent.INSERT, "X", text, out to_remove);
    assert_cmpint (edits.length, CompareOperator.EQ, 3);

    cc.apply_edit_results (edits, to_remove);

    assert_cmpint (cc.count, CompareOperator.EQ, 3);
    // "aaa" -> "XaXaXa": each cursor collapses right after its own "X",
    // shifted by however many earlier insertions already landed before it
    assert_cmpint (cc.at (0).position_offset, CompareOperator.EQ, 1);
    assert_cmpint (cc.at (1).position_offset, CompareOperator.EQ, 3);
    assert_cmpint (cc.at (2).position_offset, CompareOperator.EQ, 5);
}

private void test_multi_cursor_simultaneous_delete_left () {
    var cc = new CursorCollection ();
    string text = "aXaXaX";
    var c0 = new Cursor (2);
    var c1 = new Cursor (4);
    var c2 = new Cursor (6);
    cc.set_cursors ({ c0, c1, c2 });

    Cursor[] to_remove;
    var edits = cc.compute_edits (EditIntent.DELETE_LEFT, "", text, out to_remove);
    assert_cmpint (edits.length, CompareOperator.EQ, 3);

    cc.apply_edit_results (edits, to_remove);

    assert_cmpint (cc.count, CompareOperator.EQ, 3);
    // "aXaXaX" -> "aaaa": each deleted "X" shifts every cursor after it
    // one position to the left
    assert_cmpint (cc.at (0).position_offset, CompareOperator.EQ, 1);
    assert_cmpint (cc.at (1).position_offset, CompareOperator.EQ, 2);
    assert_cmpint (cc.at (2).position_offset, CompareOperator.EQ, 3);
}

private void test_compute_move_lines_edits_moves_a_single_collapsed_cursor_down () {
    var cc = new CursorCollection ();
    string text = "aaa\nbbb\nccc";
    cc.set_cursors ({ new Cursor (1) }); // 2nd char of "aaa"

    Cursor[] resulting;
    var edits = cc.compute_move_lines_edits (true, text, out resulting);

    assert_cmpint (edits.length, CompareOperator.EQ, 2);
    assert_cmpint (edits[0].start_offset, CompareOperator.EQ, 0);
    assert_cmpstr (edits[0].new_text, CompareOperator.EQ, "bbb\n");
    assert_cmpint (edits[1].start_offset, CompareOperator.EQ, 3);
    assert_cmpint (edits[1].end_offset, CompareOperator.EQ, 7);
    assert_cmpstr (edits[1].new_text, CompareOperator.EQ, "");
    // "aaa\nbbb\nccc" -> "bbb\naaa\nccc": the caret stays on its own
    // 2nd-character column, just on the line's new position.
    assert_cmpint (resulting[0].anchor_offset, CompareOperator.EQ, 5);
    assert_cmpint (resulting[0].position_offset, CompareOperator.EQ, 5);
}

private void test_compute_move_lines_edits_moves_a_single_collapsed_cursor_up () {
    var cc = new CursorCollection ();
    string text = "aaa\nbbb\nccc";
    cc.set_cursors ({ new Cursor (5) }); // 2nd char of "bbb"

    Cursor[] resulting;
    var edits = cc.compute_move_lines_edits (false, text, out resulting);

    assert_cmpint (edits.length, CompareOperator.EQ, 2);
    // "aaa\nbbb\nccc" -> "bbb\naaa\nccc": "bbb" is now the first line.
    assert_cmpint (resulting[0].anchor_offset, CompareOperator.EQ, 1);
    assert_cmpint (resulting[0].position_offset, CompareOperator.EQ, 1);
}

private void test_compute_move_lines_edits_preserves_a_multi_line_selections_shape () {
    var cc = new CursorCollection ();
    string text = "one\ntwo\nthree\nfour"; // one(0-2) two(4-6) three(8-12) four(14-17)
    var cursor = new Cursor (4); // anchor: start of "two"
    cursor.position_offset = 14; // position: start of "four" (selects "two\nthree\n")
    cc.set_cursors ({ cursor });

    Cursor[] resulting;
    var edits = cc.compute_move_lines_edits (true, text, out resulting);

    assert_cmpint (edits.length, CompareOperator.EQ, 2);
    // "one\ntwo\nthree\nfour" -> "one\nfour\ntwo\nthree": the selection
    // keeps spanning "two\nthree", now after "four" — its end lands on
    // the buffer's own new end (three has no trailing newline of its
    // own), not one character past it, which is the regression this
    // test exists for (a naive "shift the raw offset" computation lands
    // out of bounds here — see this method's own doc comment for why).
    assert_cmpint (resulting[0].anchor_offset, CompareOperator.EQ, 9);
    assert_cmpint (resulting[0].position_offset, CompareOperator.EQ, 18);
}

private void test_compute_move_lines_edits_preserves_a_reversed_selections_direction () {
    var cc = new CursorCollection ();
    string text = "one\ntwo\nthree\nfour";
    var cursor = new Cursor (14); // anchor: start of "four"
    cursor.position_offset = 4; // position: start of "two" — selected upward
    cc.set_cursors ({ cursor });

    Cursor[] resulting;
    var edits = cc.compute_move_lines_edits (true, text, out resulting);

    assert_cmpint (edits.length, CompareOperator.EQ, 2);
    // Same move as the forward-selection test above, but anchor/position
    // stay swapped — the selection is still "held" from the same end.
    assert_cmpint (resulting[0].anchor_offset, CompareOperator.EQ, 18);
    assert_cmpint (resulting[0].position_offset, CompareOperator.EQ, 9);
}

private void test_compute_move_lines_edits_at_the_bottom_edge_is_a_no_op () {
    var cc = new CursorCollection ();
    string text = "aaa\nbbb";
    cc.set_cursors ({ new Cursor (5) }); // inside "bbb", the last line

    Cursor[] resulting;
    var edits = cc.compute_move_lines_edits (true, text, out resulting);

    assert_cmpint (edits.length, CompareOperator.EQ, 0);
    assert_cmpint (resulting[0].position_offset, CompareOperator.EQ, 5);
}

private void test_compute_move_lines_edits_at_the_top_edge_is_a_no_op () {
    var cc = new CursorCollection ();
    string text = "aaa\nbbb";
    cc.set_cursors ({ new Cursor (1) }); // inside "aaa", the first line

    Cursor[] resulting;
    var edits = cc.compute_move_lines_edits (false, text, out resulting);

    assert_cmpint (edits.length, CompareOperator.EQ, 0);
    assert_cmpint (resulting[0].position_offset, CompareOperator.EQ, 1);
}

private void test_compute_move_lines_edits_two_cursors_on_adjacent_lines_is_a_full_no_op () {
    var cc = new CursorCollection ();
    string text = "aaa\nbbb\nccc";
    var c0 = new Cursor (1); // "aaa"
    var c1 = new Cursor (5); // "bbb" — adjacent to c0's own line
    cc.set_cursors ({ c0, c1 });

    Cursor[] resulting;
    var edits = cc.compute_move_lines_edits (true, text, out resulting);

    assert_cmpint (edits.length, CompareOperator.EQ, 0);
    assert_cmpint (resulting.length, CompareOperator.EQ, 2);
    assert_cmpint (resulting[0].position_offset, CompareOperator.EQ, 1);
    assert_cmpint (resulting[1].position_offset, CompareOperator.EQ, 5);
}

private void test_compute_enter_edits_carries_forward_the_current_lines_indentation () {
    var cc = new CursorCollection ();
    string text = "  abc";
    cc.set_cursors ({ new Cursor (5) }); // end of the line, after "c"

    Cursor[] to_remove;
    var edits = cc.compute_enter_edits (true, 2, text, out to_remove);

    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, "\n  ");
}

private void test_compute_enter_edits_truncates_indentation_when_cursor_is_inside_the_leading_whitespace () {
    var cc = new CursorCollection ();
    string text = "    abc"; // 4 leading spaces
    cc.set_cursors ({ new Cursor (2) }); // halfway through the leading whitespace

    Cursor[] to_remove;
    var edits = cc.compute_enter_edits (true, 2, text, out to_remove);

    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, "\n  "); // only what's to the cursor's own left, not the whole 4
}

private void test_compute_enter_edits_normalizes_to_tabs_when_insert_spaces_is_false () {
    var cc = new CursorCollection ();
    string text = "    abc"; // 4 real spaces, but insert_spaces below is false
    cc.set_cursors ({ new Cursor (4) }); // end of the leading whitespace

    Cursor[] to_remove;
    var edits = cc.compute_enter_edits (false, 2, text, out to_remove);

    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, "\n\t\t"); // same visible width (4), re-expressed as tabs
}

private void test_compute_enter_edits_with_a_selection_replaces_it () {
    var cc = new CursorCollection ();
    string text = "  hello world";
    var cursor = new Cursor (2);
    cursor.position_offset = 7; // selects "hello"
    cc.set_cursors ({ cursor });

    Cursor[] to_remove;
    var edits = cc.compute_enter_edits (true, 2, text, out to_remove);

    assert_cmpint (edits[0].edit.start_offset, CompareOperator.EQ, 2);
    assert_cmpint (edits[0].edit.end_offset, CompareOperator.EQ, 7);
    assert_cmpstr (edits[0].edit.old_text, CompareOperator.EQ, "hello");
    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, "\n  ");
}

private void test_compute_enter_edits_gives_each_cursor_its_own_independently_computed_indentation () {
    var cc = new CursorCollection ();
    string text = "  a\n    b"; // line 0: 2-space indent; line 1: 4-space indent
    var c0 = new Cursor (3); // end of line 0
    var c1 = new Cursor (9); // end of line 1
    cc.set_cursors ({ c0, c1 });

    Cursor[] to_remove;
    var edits = cc.compute_enter_edits (true, 2, text, out to_remove);

    assert_cmpint (edits.length, CompareOperator.EQ, 2);
    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, "\n  ");
    assert_cmpstr (edits[1].edit.new_text, CompareOperator.EQ, "\n    ");
}

private void test_compute_tab_edits_inserting_spaces_from_column_zero_fills_a_whole_indent_size () {
    var cc = new CursorCollection ();
    string text = "abc";
    cc.set_cursors ({ new Cursor (0) }); // start of the line

    Cursor[] to_remove;
    var edits = cc.compute_tab_edits (true, 2, text, out to_remove);

    assert_cmpint (edits.length, CompareOperator.EQ, 1);
    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, "  ");
}

private void test_compute_tab_edits_inserting_spaces_from_a_misaligned_column_only_reaches_the_next_stop () {
    var cc = new CursorCollection ();
    string text = "abc";
    cc.set_cursors ({ new Cursor (3) }); // column 3, indent_size 4 — one short of the next stop

    Cursor[] to_remove;
    var edits = cc.compute_tab_edits (true, 4, text, out to_remove);

    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, " ");
}

private void test_compute_tab_edits_without_insert_spaces_always_inserts_one_literal_tab () {
    var cc = new CursorCollection ();
    string text = "abc";
    cc.set_cursors ({ new Cursor (0) });

    Cursor[] to_remove;
    var edits = cc.compute_tab_edits (false, 4, text, out to_remove);

    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, "\t");
}

private void test_compute_tab_edits_gives_each_cursor_its_own_independently_computed_text () {
    var cc = new CursorCollection ();
    string text = "a\nab"; // line 0: "a" (1 char); line 1: "ab" (2 chars)
    var c0 = new Cursor (0); // start of line 0
    var c1 = new Cursor (4); // end of line 1, column 2
    cc.set_cursors ({ c0, c1 });

    Cursor[] to_remove;
    var edits = cc.compute_tab_edits (true, 3, text, out to_remove);

    assert_cmpint (edits.length, CompareOperator.EQ, 2);
    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, "   "); // column 0 -> needs 3
    assert_cmpstr (edits[1].edit.new_text, CompareOperator.EQ, " "); // column 2 -> needs 1
}

private void test_compute_backspace_edits_inside_leading_whitespace_deletes_a_whole_indent_size_at_once () {
    var cc = new CursorCollection ();
    string text = "    "; // 4 spaces
    cc.set_cursors ({ new Cursor (4) });

    Cursor[] to_remove;
    var edits = cc.compute_backspace_edits (2, text, out to_remove);

    assert_cmpint (edits[0].edit.start_offset, CompareOperator.EQ, 2);
    assert_cmpint (edits[0].edit.end_offset, CompareOperator.EQ, 4);
    assert_cmpstr (edits[0].edit.old_text, CompareOperator.EQ, "  ");
}

private void test_compute_backspace_edits_from_a_misaligned_column_only_deletes_back_to_the_previous_stop () {
    var cc = new CursorCollection ();
    string text = "   "; // 3 spaces, indent_size 2 — one past a stop
    cc.set_cursors ({ new Cursor (3) });

    Cursor[] to_remove;
    var edits = cc.compute_backspace_edits (2, text, out to_remove);

    assert_cmpint (edits[0].edit.start_offset, CompareOperator.EQ, 2);
    assert_cmpint (edits[0].edit.end_offset, CompareOperator.EQ, 3);
}

private void test_compute_backspace_edits_outside_leading_whitespace_still_deletes_one_character () {
    var cc = new CursorCollection ();
    string text = "abcd";
    cc.set_cursors ({ new Cursor (2) }); // after real (non-whitespace) characters

    Cursor[] to_remove;
    var edits = cc.compute_backspace_edits (4, text, out to_remove);

    assert_cmpint (edits[0].edit.start_offset, CompareOperator.EQ, 1);
    assert_cmpint (edits[0].edit.end_offset, CompareOperator.EQ, 2);
}

private void test_compute_backspace_edits_with_a_selection_deletes_the_selection () {
    var cc = new CursorCollection ();
    string text = "abcd";
    var cursor = new Cursor (1);
    cursor.position_offset = 3;
    cc.set_cursors ({ cursor });

    Cursor[] to_remove;
    var edits = cc.compute_backspace_edits (4, text, out to_remove);

    assert_cmpint (edits[0].edit.start_offset, CompareOperator.EQ, 1);
    assert_cmpint (edits[0].edit.end_offset, CompareOperator.EQ, 3);
    assert_cmpstr (edits[0].edit.old_text, CompareOperator.EQ, "bc");
}

private void test_compute_backspace_edits_at_document_start_produces_no_edit () {
    var cc = new CursorCollection ();
    string text = "abcd";
    cc.set_cursors ({ new Cursor (0) });

    Cursor[] to_remove;
    var edits = cc.compute_backspace_edits (4, text, out to_remove);

    assert_cmpint (edits.length, CompareOperator.EQ, 0);
}

private void test_compute_backspace_edits_on_an_empty_line_deletes_the_newline_above_instead_of_nothing () {
    // Regression: an empty line has line_start == cursor offset, so
    // within_leading_whitespace's own (empty) range is vacuously true —
    // without an explicit guard this used to compute a zero-width
    // start == end == offset delete instead of merging with the line
    // above, silently doing nothing.
    var cc = new CursorCollection ();
    string text = "abcd\n"; // line 0: "abcd"; line 1: empty
    cc.set_cursors ({ new Cursor (5) }); // start of the empty line 1

    Cursor[] to_remove;
    var edits = cc.compute_backspace_edits (2, text, out to_remove);

    assert_cmpint (edits.length, CompareOperator.EQ, 1);
    assert_cmpint (edits[0].edit.start_offset, CompareOperator.EQ, 4);
    assert_cmpint (edits[0].edit.end_offset, CompareOperator.EQ, 5);
    assert_cmpstr (edits[0].edit.old_text, CompareOperator.EQ, "\n");
}

private void test_compute_backspace_edits_mixed_multi_cursor_each_computed_independently () {
    var cc = new CursorCollection ();
    string text = "    ab"; // 4 spaces then "ab"
    var c0 = new Cursor (4); // right after the leading whitespace
    var c1 = new Cursor (6); // end of "ab" — not leading whitespace
    cc.set_cursors ({ c0, c1 });

    Cursor[] to_remove;
    var edits = cc.compute_backspace_edits (2, text, out to_remove);

    assert_cmpint (edits.length, CompareOperator.EQ, 2);
    assert_cmpstr (edits[0].edit.old_text, CompareOperator.EQ, "  "); // c0: back to the previous stop
    assert_cmpstr (edits[1].edit.old_text, CompareOperator.EQ, "b"); // c1: plain one-character delete
}

// Reproduces a scenario checked by hand against real VS Code: two
// collapsed cursors at the same column on two different lines, extended
// downward (each keeps its own column, they end up touching but not
// merged), then extended right once more — which finally makes them
// overlap and merge into a single selection.
//
//   aa|aa      Shift+Down       aa[aa      Shift+Right      aa[aa
//   bb|bb      ------------>    bb]|[bb    ------------>    bbbb
//   cccc                        cc]|cc                      ccc]c
private void test_two_cursors_extended_down_then_right_merge_once_they_overlap () {
    var cc = new CursorCollection ();
    string text = "aaaa\nbbbb\ncccc";

    var top = new Cursor (2); // "aa|aa"
    var bottom = new Cursor (7); // "bb|bb" (line 1, column 2)
    cc.set_cursors ({ top, bottom });

    cc.move_by_row (RowMoveOp.DOWN, true, text, new ParagraphRows (text), 4);

    // still two cursors: they touch exactly at column 2 of the middle
    // line ("bb]|[bb") but a touch between two non-empty selections
    // isn't a merge — only a real overlap is
    assert_cmpint (cc.count, CompareOperator.EQ, 2);
    assert_cmpint (cc.at (0).anchor_offset, CompareOperator.EQ, 2);
    assert_cmpint (cc.at (0).selection_end, CompareOperator.EQ, 7);
    assert_cmpint (cc.at (1).anchor_offset, CompareOperator.EQ, 7);
    assert_cmpint (cc.at (1).selection_end, CompareOperator.EQ, 12);

    cc.move (CursorMoveOp.RIGHT, true, text);

    // both selections grew by one character and now genuinely overlap
    // (7 falls strictly inside [2,8)) — normalize() merges them into one
    assert_cmpint (cc.count, CompareOperator.EQ, 1);
    assert_cmpint (cc.primary.anchor_offset, CompareOperator.EQ, 2);
    assert_cmpint (cc.primary.position_offset, CompareOperator.EQ, 13);
}

private void test_selected_texts_returns_each_cursors_own_selection_empty_string_for_a_collapsed_one () {
    var cc = new CursorCollection ();
    string text = "aaa\nbbb\nccc";
    var c0 = new Cursor (0);
    c0.position_offset = 3; // "aaa"
    var c1 = new Cursor (4); // collapsed, on line 1
    var c2 = new Cursor (8);
    c2.position_offset = 11; // "ccc"
    cc.set_cursors ({ c0, c1, c2 });

    string[] texts = cc.selected_texts (text);

    assert_cmpint (texts.length, CompareOperator.EQ, 3);
    assert_cmpstr (texts[0], CompareOperator.EQ, "aaa");
    assert_cmpstr (texts[1], CompareOperator.EQ, "");
    assert_cmpstr (texts[2], CompareOperator.EQ, "ccc");
}

private void test_compute_distributed_paste_edits_assigns_one_text_per_cursor () {
    var cc = new CursorCollection ();
    string text = "aaa\nbbb\nccc";
    var c0 = new Cursor (0);
    c0.position_offset = 3; // "aaa"
    var c1 = new Cursor (4);
    c1.position_offset = 7; // "bbb"
    var c2 = new Cursor (8);
    c2.position_offset = 11; // "ccc"
    cc.set_cursors ({ c0, c1, c2 });

    Cursor[] to_remove;
    var edits = cc.compute_distributed_paste_edits ({ "111", "222", "333" }, false, text, out to_remove);
    assert_cmpint (edits.length, CompareOperator.EQ, 3);
    assert_cmpint (to_remove.length, CompareOperator.EQ, 0);

    cc.apply_edit_results (edits, to_remove);

    assert_cmpint (cc.count, CompareOperator.EQ, 3);
    assert_cmpint (cc.at (0).position_offset, CompareOperator.EQ, 3); // "111" replaces "aaa", same length
    assert_cmpint (cc.at (1).position_offset, CompareOperator.EQ, 7);
    assert_cmpint (cc.at (2).position_offset, CompareOperator.EQ, 11);
}

private void test_overtype_collapsed_cursor_mid_line_replaces_the_next_characters () {
    var cc = new CursorCollection ();
    string text = "abcdefgh";
    cc.move (CursorMoveOp.RIGHT, false, text); // position_offset = 1

    Cursor[] to_remove;
    var edits = cc.compute_edits (EditIntent.OVERTYPE, "XY", text, out to_remove);

    assert_cmpint (edits.length, CompareOperator.EQ, 1);
    assert_cmpint (edits[0].edit.start_offset, CompareOperator.EQ, 1);
    assert_cmpint (edits[0].edit.end_offset, CompareOperator.EQ, 3); // "bc" eaten
    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, "XY");
}

private void test_overtype_collapsed_cursor_before_a_newline_degrades_to_insert () {
    var cc = new CursorCollection ();
    string text = "abc\ndef";
    cc.move (CursorMoveOp.RIGHT, false, text);
    cc.move (CursorMoveOp.RIGHT, false, text);
    cc.move (CursorMoveOp.RIGHT, false, text); // position_offset = 3, right before "\n"

    Cursor[] to_remove;
    var edits = cc.compute_edits (EditIntent.OVERTYPE, "XY", text, out to_remove);

    assert_cmpint (edits[0].edit.start_offset, CompareOperator.EQ, 3);
    assert_cmpint (edits[0].edit.end_offset, CompareOperator.EQ, 3); // never crosses the line break
    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, "XY");
}

private void test_overtype_collapsed_cursor_at_buffer_end_degrades_to_insert () {
    var cc = new CursorCollection ();
    string text = "abc";
    cc.move (CursorMoveOp.DOCUMENT_END, false, text);

    Cursor[] to_remove;
    var edits = cc.compute_edits (EditIntent.OVERTYPE, "XY", text, out to_remove);

    assert_cmpint (edits[0].edit.start_offset, CompareOperator.EQ, 3);
    assert_cmpint (edits[0].edit.end_offset, CompareOperator.EQ, 3);
}

private void test_overtype_selection_with_multi_character_replacement_eats_one_extra_character_past_its_end () {
    var cc = new CursorCollection ();
    string text = "abcdefgh";
    var cursor = new Cursor (1);
    cursor.position_offset = 3; // selects "bc" ([1,3))
    cc.set_cursors ({ cursor });

    Cursor[] to_remove;
    var edits = cc.compute_edits (EditIntent.OVERTYPE, "XY", text, out to_remove);

    assert_cmpint (edits[0].edit.start_offset, CompareOperator.EQ, 1);
    assert_cmpint (edits[0].edit.end_offset, CompareOperator.EQ, 4); // "bcd": the selection plus one extra character
    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, "XY");
}

private void test_overtype_selection_with_a_single_character_replacement_eats_nothing_extra () {
    var cc = new CursorCollection ();
    string text = "abcdefgh";
    var cursor = new Cursor (1);
    cursor.position_offset = 3;
    cc.set_cursors ({ cursor });

    Cursor[] to_remove;
    var edits = cc.compute_edits (EditIntent.OVERTYPE, "X", text, out to_remove);

    assert_cmpint (edits[0].edit.start_offset, CompareOperator.EQ, 1);
    assert_cmpint (edits[0].edit.end_offset, CompareOperator.EQ, 3); // exactly the selection, nothing extra
}

private void test_overtype_distributed_paste_clamps_at_the_next_cursors_own_start () {
    var cc = new CursorCollection ();
    string text = "abcdefghij";
    var c0 = new Cursor (2);
    var c1 = new Cursor (6);
    cc.set_cursors ({ c0, c1 });

    Cursor[] to_remove;
    // c0's own piece is long enough (7 chars) to want to reach offset 9,
    // well past c1's own position at 6 — must clamp there instead.
    var edits = cc.compute_distributed_paste_edits ({ "WXYZ123", "Q" }, true, text, out to_remove);

    assert_cmpint (edits[0].edit.start_offset, CompareOperator.EQ, 2);
    assert_cmpint (edits[0].edit.end_offset, CompareOperator.EQ, 6); // clamped at c1's own start, not 9
    assert_cmpstr (edits[0].edit.new_text, CompareOperator.EQ, "WXYZ123"); // the full pasted text still lands — only how much gets eaten is capped
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/cursor-collection/default_state_is_a_single_collapsed_cursor_at_start", test_default_state_is_a_single_collapsed_cursor_at_start);
    Test.add_func ("/models/cursor-collection/move_right_and_left", test_move_right_and_left);
    Test.add_func ("/models/cursor-collection/move_right_clamps_at_end_of_text", test_move_right_clamps_at_end_of_text);
    Test.add_func ("/models/cursor-collection/move_left_clamps_at_start_of_text", test_move_left_clamps_at_start_of_text);
    Test.add_func ("/models/cursor-collection/extending_grows_the_selection_and_plain_move_collapses_it", test_extending_grows_the_selection_and_plain_move_collapses_it);
    Test.add_func ("/models/cursor-collection/plain_left_on_a_selection_collapses_to_its_start", test_plain_left_on_a_selection_collapses_to_its_start);
    Test.add_func ("/models/cursor-collection/home_and_end_move_within_the_current_line", test_home_and_end_move_within_the_current_line);
    Test.add_func ("/models/cursor-collection/up_down_remembers_the_horizontal_column_across_shorter_lines", test_up_down_remembers_the_horizontal_column_across_shorter_lines);
    Test.add_func ("/models/cursor-collection/down_visits_every_wrapped_row_in_turn", test_down_visits_every_wrapped_row_in_turn);
    Test.add_func ("/models/cursor-collection/up_retraces_the_wrapped_rows_back_to_the_start", test_up_retraces_the_wrapped_rows_back_to_the_start);
    Test.add_func ("/models/cursor-collection/goal_column_survives_a_shorter_wrapped_row", test_goal_column_survives_a_shorter_wrapped_row);
    Test.add_func ("/models/cursor-collection/home_forgets_the_goal_column", test_home_forgets_the_goal_column);
    Test.add_func ("/models/cursor-collection/up_on_the_first_row_goes_to_the_buffer_start_and_down_on_the_last_to_its_end", test_up_on_the_first_row_goes_to_the_buffer_start_and_down_on_the_last_to_its_end);
    Test.add_func ("/models/cursor-collection/down_onto_a_trailing_empty_line", test_down_onto_a_trailing_empty_line);
    Test.add_func ("/models/cursor-collection/home_and_end_stay_within_the_wrapped_row", test_home_and_end_stay_within_the_wrapped_row);
    Test.add_func ("/models/cursor-collection/end_on_the_last_row_reaches_the_paragraph_end", test_end_on_the_last_row_reaches_the_paragraph_end);
    Test.add_func ("/models/cursor-collection/shift_down_extends_across_wrapped_rows", test_shift_down_extends_across_wrapped_rows);
    Test.add_func ("/models/cursor-collection/vertical_moves_count_a_tab_as_a_full_tab_stop", test_vertical_moves_count_a_tab_as_a_full_tab_stop);
    Test.add_func ("/models/cursor-collection/down_lands_on_the_nearest_column_when_a_tab_straddles_the_goal", test_down_lands_on_the_nearest_column_when_a_tab_straddles_the_goal);
    Test.add_func ("/models/cursor-collection/add_cursor_below_lands_on_the_next_paragraph_not_a_wrapped_row", test_add_cursor_below_lands_on_the_next_paragraph_not_a_wrapped_row);
    Test.add_func ("/models/cursor-collection/word_jump", test_word_jump);
    Test.add_func ("/models/cursor-collection/normalize_merges_touching_collapsed_cursors", test_normalize_merges_touching_collapsed_cursors);
    Test.add_func ("/models/cursor-collection/normalize_merges_overlapping_selections_into_their_union", test_normalize_merges_overlapping_selections_into_their_union);
    Test.add_func ("/models/cursor-collection/normalize_keeps_merely_touching_non_empty_selections_separate", test_normalize_keeps_merely_touching_non_empty_selections_separate);
    Test.add_func ("/models/cursor-collection/normalize_merge_prefers_the_last_added_cursors_direction", test_normalize_merge_prefers_the_last_added_cursors_direction);
    Test.add_func ("/models/cursor-collection/add_cursor_below_preserves_the_horizontal_column", test_add_cursor_below_preserves_the_horizontal_column);
    Test.add_func ("/models/cursor-collection/extend_last_added_cursor_grows_it_into_a_selection", test_extend_last_added_cursor_grows_it_into_a_selection);
    Test.add_func ("/models/cursor-collection/extend_last_added_cursor_overlapping_another_cursor_merges_into_their_union", test_extend_last_added_cursor_overlapping_another_cursor_merges_into_their_union);
    Test.add_func ("/models/cursor-collection/expand_last_added_cursor_to_word_selects_the_word_touching_it", test_expand_last_added_cursor_to_word_selects_the_word_touching_it);
    Test.add_func ("/models/cursor-collection/expand_last_added_cursor_to_line_selects_the_whole_line_without_its_trailing_newline", test_expand_last_added_cursor_to_line_selects_the_whole_line_without_its_trailing_newline);
    Test.add_func ("/models/cursor-collection/add_cursor_at_next_match_expands_word_then_finds_the_next_occurrence", test_add_cursor_at_next_match_expands_word_then_finds_the_next_occurrence);
    Test.add_func ("/models/cursor-collection/select_all_occurrences_selects_every_match_at_once", test_select_all_occurrences_selects_every_match_at_once);
    Test.add_func ("/models/cursor-collection/box_select_creates_one_cursor_per_line_at_the_same_column_range", test_box_select_creates_one_cursor_per_line_at_the_same_column_range);
    Test.add_func ("/models/cursor-collection/add_and_remove_cursor_at_click", test_add_and_remove_cursor_at_click);
    Test.add_func ("/models/cursor-collection/remove_cursor_at_never_removes_the_last_cursor", test_remove_cursor_at_never_removes_the_last_cursor);
    Test.add_func ("/models/cursor-collection/compute_and_apply_single_cursor_insert", test_compute_and_apply_single_cursor_insert);
    Test.add_func ("/models/cursor-collection/delete_left_at_document_start_produces_no_edit", test_delete_left_at_document_start_produces_no_edit);
    Test.add_func ("/models/cursor-collection/multi_cursor_simultaneous_insert_repositions_every_cursor", test_multi_cursor_simultaneous_insert_repositions_every_cursor);
    Test.add_func ("/models/cursor-collection/multi_cursor_simultaneous_delete_left", test_multi_cursor_simultaneous_delete_left);
    Test.add_func ("/models/cursor-collection/compute_move_lines_edits_moves_a_single_collapsed_cursor_down", test_compute_move_lines_edits_moves_a_single_collapsed_cursor_down);
    Test.add_func ("/models/cursor-collection/compute_move_lines_edits_moves_a_single_collapsed_cursor_up", test_compute_move_lines_edits_moves_a_single_collapsed_cursor_up);
    Test.add_func ("/models/cursor-collection/compute_move_lines_edits_preserves_a_multi_line_selections_shape", test_compute_move_lines_edits_preserves_a_multi_line_selections_shape);
    Test.add_func ("/models/cursor-collection/compute_move_lines_edits_preserves_a_reversed_selections_direction", test_compute_move_lines_edits_preserves_a_reversed_selections_direction);
    Test.add_func ("/models/cursor-collection/compute_move_lines_edits_at_the_bottom_edge_is_a_no_op", test_compute_move_lines_edits_at_the_bottom_edge_is_a_no_op);
    Test.add_func ("/models/cursor-collection/compute_move_lines_edits_at_the_top_edge_is_a_no_op", test_compute_move_lines_edits_at_the_top_edge_is_a_no_op);
    Test.add_func ("/models/cursor-collection/compute_move_lines_edits_two_cursors_on_adjacent_lines_is_a_full_no_op", test_compute_move_lines_edits_two_cursors_on_adjacent_lines_is_a_full_no_op);
    Test.add_func ("/models/cursor-collection/compute_enter_edits_carries_forward_the_current_lines_indentation", test_compute_enter_edits_carries_forward_the_current_lines_indentation);
    Test.add_func ("/models/cursor-collection/compute_enter_edits_truncates_indentation_when_cursor_is_inside_the_leading_whitespace", test_compute_enter_edits_truncates_indentation_when_cursor_is_inside_the_leading_whitespace);
    Test.add_func ("/models/cursor-collection/compute_enter_edits_normalizes_to_tabs_when_insert_spaces_is_false", test_compute_enter_edits_normalizes_to_tabs_when_insert_spaces_is_false);
    Test.add_func ("/models/cursor-collection/compute_enter_edits_with_a_selection_replaces_it", test_compute_enter_edits_with_a_selection_replaces_it);
    Test.add_func ("/models/cursor-collection/compute_enter_edits_gives_each_cursor_its_own_independently_computed_indentation", test_compute_enter_edits_gives_each_cursor_its_own_independently_computed_indentation);
    Test.add_func ("/models/cursor-collection/compute_tab_edits_inserting_spaces_from_column_zero_fills_a_whole_indent_size", test_compute_tab_edits_inserting_spaces_from_column_zero_fills_a_whole_indent_size);
    Test.add_func ("/models/cursor-collection/compute_tab_edits_inserting_spaces_from_a_misaligned_column_only_reaches_the_next_stop", test_compute_tab_edits_inserting_spaces_from_a_misaligned_column_only_reaches_the_next_stop);
    Test.add_func ("/models/cursor-collection/compute_tab_edits_without_insert_spaces_always_inserts_one_literal_tab", test_compute_tab_edits_without_insert_spaces_always_inserts_one_literal_tab);
    Test.add_func ("/models/cursor-collection/compute_tab_edits_gives_each_cursor_its_own_independently_computed_text", test_compute_tab_edits_gives_each_cursor_its_own_independently_computed_text);
    Test.add_func ("/models/cursor-collection/compute_backspace_edits_inside_leading_whitespace_deletes_a_whole_indent_size_at_once", test_compute_backspace_edits_inside_leading_whitespace_deletes_a_whole_indent_size_at_once);
    Test.add_func ("/models/cursor-collection/compute_backspace_edits_from_a_misaligned_column_only_deletes_back_to_the_previous_stop", test_compute_backspace_edits_from_a_misaligned_column_only_deletes_back_to_the_previous_stop);
    Test.add_func ("/models/cursor-collection/compute_backspace_edits_outside_leading_whitespace_still_deletes_one_character", test_compute_backspace_edits_outside_leading_whitespace_still_deletes_one_character);
    Test.add_func ("/models/cursor-collection/compute_backspace_edits_with_a_selection_deletes_the_selection", test_compute_backspace_edits_with_a_selection_deletes_the_selection);
    Test.add_func ("/models/cursor-collection/compute_backspace_edits_at_document_start_produces_no_edit", test_compute_backspace_edits_at_document_start_produces_no_edit);
    Test.add_func ("/models/cursor-collection/compute_backspace_edits_on_an_empty_line_deletes_the_newline_above_instead_of_nothing", test_compute_backspace_edits_on_an_empty_line_deletes_the_newline_above_instead_of_nothing);
    Test.add_func ("/models/cursor-collection/compute_backspace_edits_mixed_multi_cursor_each_computed_independently", test_compute_backspace_edits_mixed_multi_cursor_each_computed_independently);
    Test.add_func ("/models/cursor-collection/two_cursors_extended_down_then_right_merge_once_they_overlap", test_two_cursors_extended_down_then_right_merge_once_they_overlap);
    Test.add_func ("/models/cursor-collection/selected_texts_returns_each_cursors_own_selection_empty_string_for_a_collapsed_one", test_selected_texts_returns_each_cursors_own_selection_empty_string_for_a_collapsed_one);
    Test.add_func ("/models/cursor-collection/compute_distributed_paste_edits_assigns_one_text_per_cursor", test_compute_distributed_paste_edits_assigns_one_text_per_cursor);
    Test.add_func ("/models/cursor-collection/overtype_collapsed_cursor_mid_line_replaces_the_next_characters", test_overtype_collapsed_cursor_mid_line_replaces_the_next_characters);
    Test.add_func ("/models/cursor-collection/overtype_collapsed_cursor_before_a_newline_degrades_to_insert", test_overtype_collapsed_cursor_before_a_newline_degrades_to_insert);
    Test.add_func ("/models/cursor-collection/overtype_collapsed_cursor_at_buffer_end_degrades_to_insert", test_overtype_collapsed_cursor_at_buffer_end_degrades_to_insert);
    Test.add_func ("/models/cursor-collection/overtype_selection_with_multi_character_replacement_eats_one_extra_character_past_its_end", test_overtype_selection_with_multi_character_replacement_eats_one_extra_character_past_its_end);
    Test.add_func ("/models/cursor-collection/overtype_selection_with_a_single_character_replacement_eats_nothing_extra", test_overtype_selection_with_a_single_character_replacement_eats_nothing_extra);
    Test.add_func ("/models/cursor-collection/overtype_distributed_paste_clamps_at_the_next_cursors_own_start", test_overtype_distributed_paste_clamps_at_the_next_cursors_own_start);
    return Test.run ();
}
