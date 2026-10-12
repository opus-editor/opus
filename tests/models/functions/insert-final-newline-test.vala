// Functions.Native.InsertFinalNewline: a newline at the end, when the last line has content.

private string with_final_newline (string text) {
    try {
        return new Functions.Native.InsertFinalNewline ().run (Functions.Input.of_document (text))[0];
    } catch (Functions.FunctionError e) {
        error (e.message);
    }
}

private void test_a_last_line_with_content_gets_a_newline () {
    assert_cmpstr (with_final_newline ("a\nb"), CompareOperator.EQ, "a\nb\n");
}

private void test_text_already_ending_in_a_newline_is_unchanged () {
    assert_cmpstr (with_final_newline ("a\nb\n"), CompareOperator.EQ, "a\nb\n");
}

private void test_empty_text_is_unchanged () {
    assert_cmpstr (with_final_newline (""), CompareOperator.EQ, "");
}

private void test_a_last_line_of_blanks_gets_nothing () {
    assert_cmpstr (with_final_newline ("a\n  "), CompareOperator.EQ, "a\n  ");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/functions/insert-final-newline/a_last_line_with_content_gets_a_newline", test_a_last_line_with_content_gets_a_newline);
    Test.add_func ("/models/functions/insert-final-newline/text_already_ending_in_a_newline_is_unchanged", test_text_already_ending_in_a_newline_is_unchanged);
    Test.add_func ("/models/functions/insert-final-newline/empty_text_is_unchanged", test_empty_text_is_unchanged);
    Test.add_func ("/models/functions/insert-final-newline/a_last_line_of_blanks_gets_nothing", test_a_last_line_of_blanks_gets_nothing);
    Test.run ();
}
