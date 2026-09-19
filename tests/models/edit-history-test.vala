private TextEdit make_edit (int start, int end, string old_text, string new_text) {
    var edit = new TextEdit ();
    edit.start_offset = start;
    edit.end_offset = end;
    edit.old_text = old_text;
    edit.new_text = new_text;
    return edit;
}

/** Pushes a single-character insert at `offset`, as CursorController's own apply_edit() would for one keystroke — for tests that need to walk through a realistic sequence of individual typed characters. */
private void push_char (EditHistory history, int offset, string ch, EditKind kind) {
    history.push ({ make_edit (offset, offset, "", ch) }, { new Cursor (offset) }, { new Cursor (offset + 1) }, kind);
}

/**
 * Mechanically applies `edits` to `text`, bottom-to-top (descending
 * start_offset) — the same contract EditorView.apply_edits() gives the
 * real buffer — so these tests can verify a full apply/undo round trip
 * against a plain string instead of trusting offsets by inspection.
 * Byte offsets, not codepoint-aware — fine here since every fixture
 * string in this file is plain ASCII.
 */
private string apply_edits_to_text (string text, TextEdit[] edits) {
    var sorted = new TextEdit[edits.length];
    for (int i = 0; i < edits.length; i++) {
        sorted[i] = edits[i];
    }
    for (int i = 1; i < sorted.length; i++) {
        var key = sorted[i];
        int j = i - 1;
        while (j >= 0 && sorted[j].start_offset < key.start_offset) {
            sorted[j + 1] = sorted[j];
            j--;
        }
        sorted[j + 1] = key;
    }

    string result = text;
    foreach (var edit in sorted) {
        string before = result.substring (0, edit.start_offset);
        string after = result.substring (edit.end_offset);
        result = before + edit.new_text + after;
    }
    return result;
}

// Replays every push in `entry`, oldest first, as EditorController's own
// redo path would.
private string apply_entry_forward (string text, EditHistoryEntry entry) {
    string result = text;
    for (uint i = 0; i < entry.pushes.length; i++) {
        result = apply_edits_to_text (result, entry.pushes[i].edits);
    }
    return result;
}

// Replays every push in `entry` in reverse (newest first), as
// EditorController's own undo path would.
private string apply_entry_inverse (string text, EditHistoryEntry entry) {
    string result = text;
    for (int i = (int) entry.pushes.length - 1; i >= 0; i--) {
        result = apply_edits_to_text (result, entry.pushes[i].inverse_edits);
    }
    return result;
}

// Joins every push's own edits' new_text back together, in order — for
// tests that just want to see what one undo step actually typed.
private string joined_new_text (EditHistoryEntry entry) {
    var builder = new StringBuilder ();
    for (uint i = 0; i < entry.pushes.length; i++) {
        foreach (var edit in entry.pushes[i].edits) {
            builder.append (edit.new_text);
        }
    }
    return builder.str;
}

private void test_fresh_history_has_nothing_to_undo_or_redo () {
    var history = new EditHistory ();

    assert_false (history.can_undo);
    assert_false (history.can_redo);
    assert_null (history.undo ());
    assert_null (history.redo ());
}

private void test_push_then_undo_returns_the_entry_and_restores_before_state () {
    var history = new EditHistory ();

    history.push ({ make_edit (0, 0, "", "a") }, { new Cursor (0) }, { new Cursor (1) }, EditKind.TYPING_OTHER);
    assert_true (history.can_undo);
    assert_false (history.can_redo);

    var undone = history.undo ();
    assert_nonnull (undone);
    assert_cmpint (undone.pushes.length, CompareOperator.EQ, 1);
    assert_cmpint (undone.before_cursors[0].position_offset, CompareOperator.EQ, 0);
    assert_cmpint (undone.after_cursors[0].position_offset, CompareOperator.EQ, 1);
    assert_false (history.can_undo);
    assert_true (history.can_redo);
}

private void test_redo_restores_the_undone_entry () {
    var history = new EditHistory ();
    history.push ({ make_edit (0, 0, "", "a") }, { new Cursor (0) }, { new Cursor (1) }, EditKind.TYPING_OTHER);
    history.undo ();

    var redone = history.redo ();

    assert_nonnull (redone);
    assert_cmpint (redone.after_cursors[0].position_offset, CompareOperator.EQ, 1);
    assert_true (history.can_undo);
    assert_false (history.can_redo);
}

private void test_consecutive_typing_coalesces_into_one_undo_step () {
    var history = new EditHistory ();

    history.push ({ make_edit (0, 0, "", "h") }, { new Cursor (0) }, { new Cursor (1) }, EditKind.TYPING_OTHER);
    history.push ({ make_edit (1, 1, "", "i") }, { new Cursor (1) }, { new Cursor (2) }, EditKind.TYPING_OTHER);

    var undone = history.undo ();
    assert_cmpint (undone.pushes.length, CompareOperator.EQ, 2); // both keystrokes in one undo step
    assert_cmpint (undone.after_cursors[0].position_offset, CompareOperator.EQ, 2); // extended to the latest state
    assert_false (history.can_undo); // nothing left — they really were one entry
}

private void test_a_non_coalescing_kind_never_merges_with_the_open_entry () {
    var history = new EditHistory ();

    history.push ({ make_edit (0, 0, "", "a") }, { new Cursor (0) }, { new Cursor (1) }, EditKind.TYPING_OTHER);
    history.push ({ make_edit (5, 10, "hello", "") }, { new Cursor (5) }, { new Cursor (5) }, EditKind.OTHER);

    history.undo ();
    assert_true (history.can_undo); // the typing entry is still there, separate
    history.undo ();
    assert_false (history.can_undo);
}

// Regression test for a real bug: typing "asdasd", pausing, typing
// "asdasd" again, pausing, typing " asdasd" (final text "asdasd asdasd
// asdasd") undid the *entire* buffer in one Ctrl+Z in Opus, but three
// separate words in real VS Code — because the boundary a space forces
// lands *before* the space (closing the word it follows), not one
// keystroke later on a second space; see can_coalesce()'s own doc
// comment for the verified rule this encodes.
private void test_a_single_space_closes_off_the_word_before_it_and_reattaches_to_the_one_after () {
    var history = new EditHistory ();

    push_char (history, 0, "a", EditKind.TYPING_OTHER); // "a"
    push_char (history, 1, " ", EditKind.TYPING_FIRST_SPACE); // "a "
    push_char (history, 2, "b", EditKind.TYPING_OTHER); // "a b"

    var undone = history.undo ();
    assert_cmpint (undone.pushes.length, CompareOperator.EQ, 2); // " " and "b" come off together — the space stayed with "b", not with "a"
    assert_cmpstr (joined_new_text (undone), CompareOperator.EQ, " b");
    assert_true (history.can_undo); // "a" on its own is still there
    history.undo ();
    assert_false (history.can_undo);
}

private void test_a_run_of_multiple_spaces_stays_together_as_its_own_step () {
    var history = new EditHistory ();

    push_char (history, 0, "a", EditKind.TYPING_OTHER); // "a"
    push_char (history, 1, " ", EditKind.TYPING_FIRST_SPACE); // "a "
    push_char (history, 2, " ", EditKind.TYPING_CONSECUTIVE_SPACE); // "a  "
    push_char (history, 3, "b", EditKind.TYPING_OTHER); // "a  b"

    var undone = history.undo ();
    assert_cmpstr (joined_new_text (undone), CompareOperator.EQ, "b"); // "b" is its own step this time — it follows a *run* of spaces, not a single one
    assert_true (history.can_undo);

    undone = history.undo ();
    assert_cmpint (undone.pushes.length, CompareOperator.EQ, 2); // both spaces, together
    assert_true (history.can_undo); // "a" is still its own, separate step

    history.undo ();
    assert_false (history.can_undo);
}

// The exact reported reproduction: typing "asdasd ", then "asdasd", then
// " asdasd" (three separate bursts, final text "asdasd asdasd asdasd")
// must land as three separate undo steps, one per word — not one giant
// step that erases everything on the first Ctrl+Z.
private void test_three_words_typed_in_a_row_undo_one_word_at_a_time () {
    var history = new EditHistory ();
    string typed = "asdasd asdasd asdasd";
    bool previous_was_space = false;

    for (int i = 0; i < typed.length; i++) {
        string ch = typed.substring (i, 1);
        EditKind kind;
        if (ch == " ") {
            kind = previous_was_space ? EditKind.TYPING_CONSECUTIVE_SPACE : EditKind.TYPING_FIRST_SPACE;
        } else {
            kind = EditKind.TYPING_OTHER;
        }
        previous_was_space = (ch == " ");
        push_char (history, i, ch, kind);
    }

    var undone = history.undo ();
    assert_cmpstr (joined_new_text (undone), CompareOperator.EQ, " asdasd");
    assert_true (history.can_undo);

    undone = history.undo ();
    assert_cmpstr (joined_new_text (undone), CompareOperator.EQ, " asdasd");
    assert_true (history.can_undo);

    undone = history.undo ();
    assert_cmpstr (joined_new_text (undone), CompareOperator.EQ, "asdasd");
    assert_false (history.can_undo); // nothing left — exactly three undo steps for three words
}

// Regression test for a real bug: two simultaneous cursors ("aa|aa" /
// "bb|bb", offsets 2 and 7) typing "z" together landed edits at [2] and
// [7] in one batch — but [7] is only valid in the *pre-batch* text.
// Once [2]'s own "z" actually lands, the second cursor's "z" is really
// at offset 8, not 7. Naively inverting each edit on its own (the old
// behavior) undid the wrong character on line 2. TextEdit.invert_batch()
// exists specifically to rebase this correctly.
private void test_invert_batch_rebases_a_later_edit_by_an_earlier_ones_length_delta () {
    var edits = new TextEdit[] { make_edit (2, 2, "", "z"), make_edit (7, 7, "", "z") };

    var inverted = TextEdit.invert_batch (edits);

    assert_cmpint (inverted[0].start_offset, CompareOperator.EQ, 2);
    assert_cmpint (inverted[0].end_offset, CompareOperator.EQ, 3);
    assert_cmpstr (inverted[0].old_text, CompareOperator.EQ, "z");
    assert_cmpstr (inverted[0].new_text, CompareOperator.EQ, "");

    // The real position of the second "z", after the first one already
    // landed at offset 2, is 8 — not the original, pre-batch 7.
    assert_cmpint (inverted[1].start_offset, CompareOperator.EQ, 8);
    assert_cmpint (inverted[1].end_offset, CompareOperator.EQ, 9);
    assert_cmpstr (inverted[1].old_text, CompareOperator.EQ, "z");
}

// The exact reported reproduction, at the EditHistory level: two cursors
// ("aa|aa" / "bb|bb") type "z" twice in a row (coalescing into one undo
// entry, same as normal single-cursor typing) — one undo must restore
// the *original* text exactly, not leave a stray "z" behind or touch the
// wrong character. Each push is replayed on its own (apply_entry_inverse,
// newest first) rather than as one flattened batch — see
// EditHistory.push()'s own comment for why flattening breaks this exact
// scenario.
private void test_two_simultaneous_cursors_typing_two_characters_undo_back_to_the_original_text () {
    var history = new EditHistory ();
    string original = "aaaa\nbbbb\ncccc";

    var edits1 = new TextEdit[] { make_edit (2, 2, "", "z"), make_edit (7, 7, "", "z") };
    string after_first_z = apply_edits_to_text (original, edits1);
    assert_cmpstr (after_first_z, CompareOperator.EQ, "aazaa\nbbzbb\ncccc");
    history.push (edits1, { new Cursor (2), new Cursor (7) }, { new Cursor (3), new Cursor (9) }, EditKind.TYPING_OTHER);

    var edits2 = new TextEdit[] { make_edit (3, 3, "", "z"), make_edit (9, 9, "", "z") };
    string after_second_z = apply_edits_to_text (after_first_z, edits2);
    assert_cmpstr (after_second_z, CompareOperator.EQ, "aazzaa\nbbzzbb\ncccc");
    history.push (edits2, { new Cursor (3), new Cursor (9) }, { new Cursor (4), new Cursor (11) }, EditKind.TYPING_OTHER);

    assert_true (history.can_undo);
    var undone = history.undo ();
    assert_cmpint (undone.pushes.length, CompareOperator.EQ, 2); // both keystrokes coalesced into the one entry just undone
    assert_cmpstr (apply_entry_inverse (after_second_z, undone), CompareOperator.EQ, original);
    assert_false (history.can_undo);
}

// The same scenario, but confirming redo (forward replay, oldest push
// first) lands back on the fully-typed text too — not just undo.
private void test_two_simultaneous_cursors_redo_replays_pushes_oldest_first () {
    var history = new EditHistory ();
    string original = "aaaa\nbbbb\ncccc";

    var edits1 = new TextEdit[] { make_edit (2, 2, "", "z"), make_edit (7, 7, "", "z") };
    string after_first_z = apply_edits_to_text (original, edits1);
    history.push (edits1, { new Cursor (2), new Cursor (7) }, { new Cursor (3), new Cursor (9) }, EditKind.TYPING_OTHER);

    var edits2 = new TextEdit[] { make_edit (3, 3, "", "z"), make_edit (9, 9, "", "z") };
    string after_second_z = apply_edits_to_text (after_first_z, edits2);
    history.push (edits2, { new Cursor (3), new Cursor (9) }, { new Cursor (4), new Cursor (11) }, EditKind.TYPING_OTHER);

    var undone = history.undo ();
    string back_to_original = apply_entry_inverse (after_second_z, undone);
    assert_cmpstr (back_to_original, CompareOperator.EQ, original);

    var redone = history.redo ();
    assert_cmpstr (apply_entry_forward (back_to_original, redone), CompareOperator.EQ, after_second_z);
}

private void test_deleting_coalesces_only_with_the_same_direction () {
    var history = new EditHistory ();

    history.push ({ make_edit (4, 5, "o", "") }, { new Cursor (5) }, { new Cursor (4) }, EditKind.DELETING_LEFT);
    history.push ({ make_edit (3, 4, "l", "") }, { new Cursor (4) }, { new Cursor (3) }, EditKind.DELETING_LEFT);

    var undone = history.undo ();
    assert_cmpint (undone.pushes.length, CompareOperator.EQ, 2); // both backspaces coalesced
    assert_false (history.can_undo);

    history.push ({ make_edit (3, 4, "l", "") }, { new Cursor (3) }, { new Cursor (3) }, EditKind.DELETING_LEFT);
    history.push ({ make_edit (3, 4, "l", "") }, { new Cursor (3) }, { new Cursor (3) }, EditKind.DELETING_RIGHT);

    history.undo (); // only the DELETING_RIGHT one — switching direction forced a boundary
    assert_true (history.can_undo);
    history.undo ();
    assert_false (history.can_undo);
}

private void test_push_clears_the_redo_stack () {
    var history = new EditHistory ();
    history.push ({ make_edit (0, 0, "", "a") }, { new Cursor (0) }, { new Cursor (1) }, EditKind.TYPING_OTHER);
    history.undo ();
    assert_true (history.can_redo);

    history.push ({ make_edit (0, 0, "", "b") }, { new Cursor (0) }, { new Cursor (1) }, EditKind.TYPING_OTHER);

    assert_false (history.can_redo);
}

private void test_close_current_entry_prevents_further_coalescing () {
    var history = new EditHistory ();

    history.push ({ make_edit (0, 0, "", "a") }, { new Cursor (0) }, { new Cursor (1) }, EditKind.TYPING_OTHER);
    history.close_current_entry ();
    history.push ({ make_edit (1, 1, "", "b") }, { new Cursor (1) }, { new Cursor (2) }, EditKind.TYPING_OTHER);

    history.undo ();
    assert_true (history.can_undo); // the two typing pushes stayed as separate entries
    history.undo ();
    assert_false (history.can_undo);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/edit-history/invert_batch_rebases_a_later_edit_by_an_earlier_ones_length_delta", test_invert_batch_rebases_a_later_edit_by_an_earlier_ones_length_delta);
    Test.add_func ("/models/edit-history/two_simultaneous_cursors_typing_two_characters_undo_back_to_the_original_text", test_two_simultaneous_cursors_typing_two_characters_undo_back_to_the_original_text);
    Test.add_func ("/models/edit-history/two_simultaneous_cursors_redo_replays_pushes_oldest_first", test_two_simultaneous_cursors_redo_replays_pushes_oldest_first);
    Test.add_func ("/models/edit-history/fresh_history_has_nothing_to_undo_or_redo", test_fresh_history_has_nothing_to_undo_or_redo);
    Test.add_func ("/models/edit-history/push_then_undo_returns_the_entry_and_restores_before_state", test_push_then_undo_returns_the_entry_and_restores_before_state);
    Test.add_func ("/models/edit-history/redo_restores_the_undone_entry", test_redo_restores_the_undone_entry);
    Test.add_func ("/models/edit-history/consecutive_typing_coalesces_into_one_undo_step", test_consecutive_typing_coalesces_into_one_undo_step);
    Test.add_func ("/models/edit-history/a_non_coalescing_kind_never_merges_with_the_open_entry", test_a_non_coalescing_kind_never_merges_with_the_open_entry);
    Test.add_func ("/models/edit-history/a_single_space_closes_off_the_word_before_it_and_reattaches_to_the_one_after", test_a_single_space_closes_off_the_word_before_it_and_reattaches_to_the_one_after);
    Test.add_func ("/models/edit-history/a_run_of_multiple_spaces_stays_together_as_its_own_step", test_a_run_of_multiple_spaces_stays_together_as_its_own_step);
    Test.add_func ("/models/edit-history/three_words_typed_in_a_row_undo_one_word_at_a_time", test_three_words_typed_in_a_row_undo_one_word_at_a_time);
    Test.add_func ("/models/edit-history/deleting_coalesces_only_with_the_same_direction", test_deleting_coalesces_only_with_the_same_direction);
    Test.add_func ("/models/edit-history/push_clears_the_redo_stack", test_push_clears_the_redo_stack);
    Test.add_func ("/models/edit-history/close_current_entry_prevents_further_coalescing", test_close_current_entry_prevents_further_coalescing);
    return Test.run ();
}
