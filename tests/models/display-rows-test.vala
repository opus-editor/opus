private void test_row_bounds_is_the_paragraph_around_the_offset () {
    var rows = new ParagraphRows ("ab\ncde\nf");

    int start;
    int end;
    rows.row_bounds (4, out start, out end); // inside "cde"

    assert_cmpint (start, CompareOperator.EQ, 3);
    assert_cmpint (end, CompareOperator.EQ, 6); // the newline's own position
}

private void test_row_bounds_of_an_empty_line_is_a_single_position () {
    var rows = new ParagraphRows ("ab\n\ncd");

    int start;
    int end;
    rows.row_bounds (3, out start, out end);

    assert_cmpint (start, CompareOperator.EQ, 3);
    assert_cmpint (end, CompareOperator.EQ, 3);
}

private void test_row_bounds_on_the_last_line_ends_at_the_buffer_end () {
    var rows = new ParagraphRows ("ab\ncd");

    int start;
    int end;
    rows.row_bounds (4, out start, out end);

    assert_cmpint (start, CompareOperator.EQ, 3);
    assert_cmpint (end, CompareOperator.EQ, 5);
}

private void test_row_above_is_the_previous_paragraph () {
    var rows = new ParagraphRows ("ab\ncde\nf");

    int start;
    int end;
    bool found = rows.row_above (8, out start, out end); // "f"

    assert_true (found);
    assert_cmpint (start, CompareOperator.EQ, 3);
    assert_cmpint (end, CompareOperator.EQ, 6);
}

private void test_row_above_the_first_line_does_not_exist () {
    var rows = new ParagraphRows ("ab\ncd");

    int start;
    int end;
    bool found = rows.row_above (1, out start, out end);

    assert_false (found);
}

private void test_row_below_is_the_next_paragraph () {
    var rows = new ParagraphRows ("ab\ncde\nf");

    int start;
    int end;
    bool found = rows.row_below (1, out start, out end);

    assert_true (found);
    assert_cmpint (start, CompareOperator.EQ, 3);
    assert_cmpint (end, CompareOperator.EQ, 6);
}

private void test_row_below_the_last_line_does_not_exist () {
    var rows = new ParagraphRows ("ab\ncd");

    int start;
    int end;
    bool found = rows.row_below (4, out start, out end);

    assert_false (found);
}

private void test_text_ending_in_a_newline_has_an_empty_last_row () {
    var rows = new ParagraphRows ("ab\n");

    int start;
    int end;
    bool found = rows.row_below (1, out start, out end);

    assert_true (found);
    assert_cmpint (start, CompareOperator.EQ, 3);
    assert_cmpint (end, CompareOperator.EQ, 3);
}

private void test_empty_text_is_one_empty_row () {
    var rows = new ParagraphRows ("");

    int start;
    int end;
    rows.row_bounds (0, out start, out end);

    assert_cmpint (start, CompareOperator.EQ, 0);
    assert_cmpint (end, CompareOperator.EQ, 0);
    assert_false (rows.row_above (0, out start, out end));
    assert_false (rows.row_below (0, out start, out end));
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/display-rows/row_bounds_is_the_paragraph_around_the_offset", test_row_bounds_is_the_paragraph_around_the_offset);
    Test.add_func ("/models/display-rows/row_bounds_of_an_empty_line_is_a_single_position", test_row_bounds_of_an_empty_line_is_a_single_position);
    Test.add_func ("/models/display-rows/row_bounds_on_the_last_line_ends_at_the_buffer_end", test_row_bounds_on_the_last_line_ends_at_the_buffer_end);
    Test.add_func ("/models/display-rows/row_above_is_the_previous_paragraph", test_row_above_is_the_previous_paragraph);
    Test.add_func ("/models/display-rows/row_above_the_first_line_does_not_exist", test_row_above_the_first_line_does_not_exist);
    Test.add_func ("/models/display-rows/row_below_is_the_next_paragraph", test_row_below_is_the_next_paragraph);
    Test.add_func ("/models/display-rows/row_below_the_last_line_does_not_exist", test_row_below_the_last_line_does_not_exist);
    Test.add_func ("/models/display-rows/text_ending_in_a_newline_has_an_empty_last_row", test_text_ending_in_a_newline_has_an_empty_last_row);
    Test.add_func ("/models/display-rows/empty_text_is_one_empty_row", test_empty_text_is_one_empty_row);
    return Test.run ();
}
