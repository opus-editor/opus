private unichar[] chars_of (string text) {
    unichar[] result = {};
    int index = 0;
    unichar c;
    while (text.get_next_char (ref index, out c)) {
        result += c;
    }
    return result;
}

private Syntax.BracketPair parens () {
    return new Syntax.BracketPair ("(", ")", {}, true, true);
}

private TextEdit insertion (int offset, string text) {
    var edit = new TextEdit ();
    edit.start_offset = offset;
    edit.end_offset = offset;
    edit.old_text = "";
    edit.new_text = text;
    return edit;
}

private void test_a_remembered_pair_is_found_by_where_its_close_starts () {
    var pairs = new InsertedPairs ();

    pairs.remember (2, 3, parens ());

    assert_nonnull (pairs.closing_at (3));
    assert_cmpint (pairs.closing_at (3).open_offset, CompareOperator.EQ, 2);
}

private void test_an_offset_past_the_close_finds_nothing () {
    var pairs = new InsertedPairs ();
    pairs.remember (2, 3, parens ());

    assert_null (pairs.closing_at (4));
    assert_null (pairs.closing_at (2));
}

private void test_an_insertion_before_the_pair_moves_both_ends () {
    var pairs = new InsertedPairs ();
    pairs.remember (2, 3, parens ());

    pairs.shift ({ insertion (0, "ab") });

    var entry = pairs.closing_at (5);
    assert_nonnull (entry);
    assert_cmpint (entry.open_offset, CompareOperator.EQ, 4);
}

private void test_typing_inside_the_pair_moves_only_its_close () {
    var pairs = new InsertedPairs ();
    pairs.remember (2, 3, parens ());

    pairs.shift ({ insertion (3, "a") });

    var entry = pairs.closing_at (4);
    assert_nonnull (entry);
    assert_cmpint (entry.open_offset, CompareOperator.EQ, 2);
}

private void test_an_insertion_after_the_pair_moves_nothing () {
    var pairs = new InsertedPairs ();
    pairs.remember (2, 3, parens ());

    pairs.shift ({ insertion (4, "a") });

    assert_nonnull (pairs.closing_at (3));
}

private void test_a_pair_with_a_cursor_inside_survives () {
    var pairs = new InsertedPairs ();
    pairs.remember (2, 4, parens ());

    pairs.forget_stale (chars_of ("x (a)"), { new Cursor (4) });

    assert_cmpint (pairs.count, CompareOperator.EQ, 1);
}

private void test_a_pair_with_a_cursor_right_after_its_open_survives () {
    var pairs = new InsertedPairs ();
    pairs.remember (2, 4, parens ());

    pairs.forget_stale (chars_of ("x (a)"), { new Cursor (3) });

    assert_cmpint (pairs.count, CompareOperator.EQ, 1);
}

private void test_a_pair_no_cursor_sits_inside_is_forgotten () {
    var pairs = new InsertedPairs ();
    pairs.remember (2, 4, parens ());

    pairs.forget_stale (chars_of ("x (a)"), { new Cursor (5), new Cursor (2) });

    assert_cmpint (pairs.count, CompareOperator.EQ, 0);
}

private void test_a_pair_whose_text_changed_is_forgotten () {
    var pairs = new InsertedPairs ();
    pairs.remember (2, 4, parens ());

    pairs.forget_stale (chars_of ("x [a)"), { new Cursor (3) });

    assert_cmpint (pairs.count, CompareOperator.EQ, 0);
}

private void test_a_pair_that_came_to_span_a_line_break_is_forgotten () {
    var pairs = new InsertedPairs ();
    pairs.remember (2, 4, parens ());

    pairs.forget_stale (chars_of ("x (\n)"), { new Cursor (3) });

    assert_cmpint (pairs.count, CompareOperator.EQ, 0);
}

private void test_an_empty_pair_is_found_around_the_offset_between_its_ends () {
    var pairs = new InsertedPairs ();
    pairs.remember (2, 3, parens ());

    assert_nonnull (pairs.around (3));
}

private void test_a_pair_with_something_inside_is_not_around_any_offset () {
    var pairs = new InsertedPairs ();
    pairs.remember (2, 4, parens ());

    assert_null (pairs.around (3));
    assert_null (pairs.around (4));
}

private void test_clearing_forgets_everything () {
    var pairs = new InsertedPairs ();
    pairs.remember (2, 3, parens ());

    pairs.clear ();

    assert_cmpint (pairs.count, CompareOperator.EQ, 0);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/inserted-pairs/a_remembered_pair_is_found_by_where_its_close_starts", test_a_remembered_pair_is_found_by_where_its_close_starts);
    Test.add_func ("/models/inserted-pairs/an_offset_past_the_close_finds_nothing", test_an_offset_past_the_close_finds_nothing);
    Test.add_func ("/models/inserted-pairs/an_insertion_before_the_pair_moves_both_ends", test_an_insertion_before_the_pair_moves_both_ends);
    Test.add_func ("/models/inserted-pairs/typing_inside_the_pair_moves_only_its_close", test_typing_inside_the_pair_moves_only_its_close);
    Test.add_func ("/models/inserted-pairs/an_insertion_after_the_pair_moves_nothing", test_an_insertion_after_the_pair_moves_nothing);
    Test.add_func ("/models/inserted-pairs/a_pair_with_a_cursor_inside_survives", test_a_pair_with_a_cursor_inside_survives);
    Test.add_func ("/models/inserted-pairs/a_pair_with_a_cursor_right_after_its_open_survives", test_a_pair_with_a_cursor_right_after_its_open_survives);
    Test.add_func ("/models/inserted-pairs/a_pair_no_cursor_sits_inside_is_forgotten", test_a_pair_no_cursor_sits_inside_is_forgotten);
    Test.add_func ("/models/inserted-pairs/a_pair_whose_text_changed_is_forgotten", test_a_pair_whose_text_changed_is_forgotten);
    Test.add_func ("/models/inserted-pairs/a_pair_that_came_to_span_a_line_break_is_forgotten", test_a_pair_that_came_to_span_a_line_break_is_forgotten);
    Test.add_func ("/models/inserted-pairs/an_empty_pair_is_found_around_the_offset_between_its_ends", test_an_empty_pair_is_found_around_the_offset_between_its_ends);
    Test.add_func ("/models/inserted-pairs/a_pair_with_something_inside_is_not_around_any_offset", test_a_pair_with_something_inside_is_not_around_any_offset);
    Test.add_func ("/models/inserted-pairs/clearing_forgets_everything", test_clearing_forgets_everything);
    return Test.run ();
}
