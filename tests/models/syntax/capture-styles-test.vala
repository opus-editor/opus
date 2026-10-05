private void test_a_capture_that_is_itself_a_key_resolves_to_it () {
    var styles = new Syntax.CaptureStyles ({ "keyword", "string" });

    var key = styles.resolve ("keyword");

    assert_cmpstr (key, CompareOperator.EQ, "keyword");
}

private void test_a_capture_falls_back_to_a_dotted_prefix () {
    var styles = new Syntax.CaptureStyles ({ "keyword" });

    var key = styles.resolve ("keyword.control.return");

    assert_cmpstr (key, CompareOperator.EQ, "keyword");
}

private void test_the_most_specific_key_wins () {
    var styles = new Syntax.CaptureStyles ({ "keyword", "keyword.control" });

    var key = styles.resolve ("keyword.control.return");

    assert_cmpstr (key, CompareOperator.EQ, "keyword.control");
}

private void test_a_capture_with_no_key_resolves_to_null () {
    var styles = new Syntax.CaptureStyles ({ "keyword" });

    var key = styles.resolve ("string.special");

    assert_null (key);
}

private void test_a_key_only_matches_whole_segments () {
    var styles = new Syntax.CaptureStyles ({ "keyword" });

    var key = styles.resolve ("keywords");

    assert_null (key);
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/capture-styles/a_capture_that_is_itself_a_key_resolves_to_it", test_a_capture_that_is_itself_a_key_resolves_to_it);
    Test.add_func ("/models/syntax/capture-styles/a_capture_falls_back_to_a_dotted_prefix", test_a_capture_falls_back_to_a_dotted_prefix);
    Test.add_func ("/models/syntax/capture-styles/the_most_specific_key_wins", test_the_most_specific_key_wins);
    Test.add_func ("/models/syntax/capture-styles/a_capture_with_no_key_resolves_to_null", test_a_capture_with_no_key_resolves_to_null);
    Test.add_func ("/models/syntax/capture-styles/a_key_only_matches_whole_segments", test_a_key_only_matches_whole_segments);
    Test.run ();
}
