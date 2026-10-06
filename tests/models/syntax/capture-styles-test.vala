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

private void test_a_languages_own_style_is_used_for_that_language () {
    var styles = new Syntax.CaptureStyles ({ "constant", Syntax.CaptureStyles.language_key ("css", "constant") });

    var key = styles.resolve ("constant", "css");

    assert_cmpstr (key, CompareOperator.EQ, Syntax.CaptureStyles.language_key ("css", "constant"));
}

private void test_another_language_keeps_the_general_style () {
    var styles = new Syntax.CaptureStyles ({ "constant", Syntax.CaptureStyles.language_key ("css", "constant") });

    var key = styles.resolve ("constant", "ruby");

    assert_cmpstr (key, CompareOperator.EQ, "constant");
}

private void test_a_capture_falls_back_to_a_dotted_prefix_among_a_languages_own_styles () {
    var styles = new Syntax.CaptureStyles ({ Syntax.CaptureStyles.language_key ("css", "constant") });

    var key = styles.resolve ("constant.numeric.integer", "css");

    assert_cmpstr (key, CompareOperator.EQ, Syntax.CaptureStyles.language_key ("css", "constant"));
}

private void test_the_most_specific_of_a_languages_own_styles_wins () {
    var styles = new Syntax.CaptureStyles ({ Syntax.CaptureStyles.language_key ("css", "constant"), Syntax.CaptureStyles.language_key ("css", "constant.numeric") });

    var key = styles.resolve ("constant.numeric.integer", "css");

    assert_cmpstr (key, CompareOperator.EQ, Syntax.CaptureStyles.language_key ("css", "constant.numeric"));
}

private void test_a_languages_own_style_outranks_a_more_specific_general_one () {
    var styles = new Syntax.CaptureStyles ({ "constant.numeric", Syntax.CaptureStyles.language_key ("css", "constant") });

    var key = styles.resolve ("constant.numeric", "css");

    assert_cmpstr (key, CompareOperator.EQ, Syntax.CaptureStyles.language_key ("css", "constant"));
}

private void test_a_capture_its_language_does_not_style_gets_the_general_style () {
    var styles = new Syntax.CaptureStyles ({ "keyword", Syntax.CaptureStyles.language_key ("css", "constant") });

    var key = styles.resolve ("keyword.control", "css");

    assert_cmpstr (key, CompareOperator.EQ, "keyword");
}

private void test_a_capture_styled_nowhere_resolves_to_null_in_a_language_too () {
    var styles = new Syntax.CaptureStyles ({ Syntax.CaptureStyles.language_key ("css", "constant") });

    var key = styles.resolve ("keyword", "css");

    assert_null (key);
}

private void test_a_language_with_dots_in_its_name_has_its_own_styles () {
    var styles = new Syntax.CaptureStyles ({ "markup", Syntax.CaptureStyles.language_key ("markdown.inline", "markup") });

    var key = styles.resolve ("markup.bold", "markdown.inline");

    assert_cmpstr (key, CompareOperator.EQ, Syntax.CaptureStyles.language_key ("markdown.inline", "markup"));
}

private void test_without_a_language_only_general_styles_are_used () {
    var styles = new Syntax.CaptureStyles ({ "constant", Syntax.CaptureStyles.language_key ("css", "constant") });

    var key = styles.resolve ("constant");

    assert_cmpstr (key, CompareOperator.EQ, "constant");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/capture-styles/a_capture_that_is_itself_a_key_resolves_to_it", test_a_capture_that_is_itself_a_key_resolves_to_it);
    Test.add_func ("/models/syntax/capture-styles/a_capture_falls_back_to_a_dotted_prefix", test_a_capture_falls_back_to_a_dotted_prefix);
    Test.add_func ("/models/syntax/capture-styles/the_most_specific_key_wins", test_the_most_specific_key_wins);
    Test.add_func ("/models/syntax/capture-styles/a_capture_with_no_key_resolves_to_null", test_a_capture_with_no_key_resolves_to_null);
    Test.add_func ("/models/syntax/capture-styles/a_key_only_matches_whole_segments", test_a_key_only_matches_whole_segments);
    Test.add_func ("/models/syntax/capture-styles/a_languages_own_style_is_used_for_that_language", test_a_languages_own_style_is_used_for_that_language);
    Test.add_func ("/models/syntax/capture-styles/another_language_keeps_the_general_style", test_another_language_keeps_the_general_style);
    Test.add_func ("/models/syntax/capture-styles/a_capture_falls_back_to_a_dotted_prefix_among_a_languages_own_styles", test_a_capture_falls_back_to_a_dotted_prefix_among_a_languages_own_styles);
    Test.add_func ("/models/syntax/capture-styles/the_most_specific_of_a_languages_own_styles_wins", test_the_most_specific_of_a_languages_own_styles_wins);
    Test.add_func ("/models/syntax/capture-styles/a_languages_own_style_outranks_a_more_specific_general_one", test_a_languages_own_style_outranks_a_more_specific_general_one);
    Test.add_func ("/models/syntax/capture-styles/a_capture_its_language_does_not_style_gets_the_general_style", test_a_capture_its_language_does_not_style_gets_the_general_style);
    Test.add_func ("/models/syntax/capture-styles/a_capture_styled_nowhere_resolves_to_null_in_a_language_too", test_a_capture_styled_nowhere_resolves_to_null_in_a_language_too);
    Test.add_func ("/models/syntax/capture-styles/a_language_with_dots_in_its_name_has_its_own_styles", test_a_language_with_dots_in_its_name_has_its_own_styles);
    Test.add_func ("/models/syntax/capture-styles/without_a_language_only_general_styles_are_used", test_without_a_language_only_general_styles_are_used);
    Test.run ();
}
