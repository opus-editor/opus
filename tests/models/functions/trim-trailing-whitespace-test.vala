// Functions.Native.TrimTrailingWhitespace: the blanks at every line's end, except before a cursor.

private string trimmed (string text, int[] cursor_positions = {}) {
    var input = Functions.Input.of_document (text);
    LuaSandbox.Caret[] cursors = {};
    foreach (var position in cursor_positions) {
        cursors += LuaSandbox.Caret () { anchor = position, position = position };
    }
    input.cursors = cursors;
    try {
        return new Functions.Native.TrimTrailingWhitespace ().run (input)[0];
    } catch (Functions.FunctionError e) {
        error (e.message);
    }
}

private void test_every_lines_trailing_blanks_go () {
    assert_cmpstr (trimmed ("a  \nb\t\n c \n"), CompareOperator.EQ, "a\nb\n c\n");
}

private void test_a_line_of_blanks_only_is_emptied () {
    assert_cmpstr (trimmed ("a\n   \nb"), CompareOperator.EQ, "a\n\nb");
}

private void test_text_with_nothing_to_trim_is_unchanged () {
    assert_cmpstr (trimmed ("a\nb\n"), CompareOperator.EQ, "a\nb\n");
}

private void test_the_blanks_before_a_cursor_stay () {
    //                      0123 4
    assert_cmpstr (trimmed ("a  \nb  ", { 2 }), CompareOperator.EQ, "a \nb");
}

private void test_a_cursor_at_the_end_of_its_line_keeps_the_line_whole () {
    assert_cmpstr (trimmed ("a  \nb  ", { 3 }), CompareOperator.EQ, "a  \nb");
}

private void test_a_cursor_spares_only_its_own_line () {
    assert_cmpstr (trimmed ("a  \nb  \n", { 7 }), CompareOperator.EQ, "a\nb  \n");
}

private void test_a_selection_segment_counts_cursors_from_its_own_start () {
    var text = "xx\na  \nb  ";
    var input = new Functions.Input () { kind = "selection", text = text };
    input.segments = { LuaSandbox.Segment () { text = "a  \nb  ", start = 3, end = 10 } };
    input.cursors = { LuaSandbox.Caret () { anchor = 5, position = 5 } };

    string[] output = {};
    try {
        output = new Functions.Native.TrimTrailingWhitespace ().run (input);
    } catch (Functions.FunctionError e) {
        error (e.message);
    }

    assert_cmpstr (output[0], CompareOperator.EQ, "a \nb");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/functions/trim-trailing-whitespace/every_lines_trailing_blanks_go", test_every_lines_trailing_blanks_go);
    Test.add_func ("/models/functions/trim-trailing-whitespace/a_line_of_blanks_only_is_emptied", test_a_line_of_blanks_only_is_emptied);
    Test.add_func ("/models/functions/trim-trailing-whitespace/text_with_nothing_to_trim_is_unchanged", test_text_with_nothing_to_trim_is_unchanged);
    Test.add_func ("/models/functions/trim-trailing-whitespace/the_blanks_before_a_cursor_stay", test_the_blanks_before_a_cursor_stay);
    Test.add_func ("/models/functions/trim-trailing-whitespace/a_cursor_at_the_end_of_its_line_keeps_the_line_whole", test_a_cursor_at_the_end_of_its_line_keeps_the_line_whole);
    Test.add_func ("/models/functions/trim-trailing-whitespace/a_cursor_spares_only_its_own_line", test_a_cursor_spares_only_its_own_line);
    Test.add_func ("/models/functions/trim-trailing-whitespace/a_selection_segment_counts_cursors_from_its_own_start", test_a_selection_segment_counts_cursors_from_its_own_start);
    Test.run ();
}
