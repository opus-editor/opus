private void test_regex_off_is_always_literal_even_with_dollar_and_backslash () {
    var pattern = ReplacePattern.parse ("$1 \\U literal", false);

    assert_false (pattern.has_replacement_patterns);
    assert_cmpstr (pattern.build ({ "whole match" }), CompareOperator.EQ, "$1 \\U literal");
}

private void test_regex_on_with_no_escapes_is_still_literal () {
    var pattern = ReplacePattern.parse ("plain text", true);

    assert_false (pattern.has_replacement_patterns);
    assert_cmpstr (pattern.build ({ "whole match" }), CompareOperator.EQ, "plain text");
}

private void test_dollar_n_substitutes_a_capture_group () {
    var pattern = ReplacePattern.parse ("$1-$2", true);

    assert_true (pattern.has_replacement_patterns);
    assert_cmpstr (pattern.build ({ "hello-world", "hello", "world" }), CompareOperator.EQ, "hello-world");
}

private void test_dollar_ampersand_and_dollar_zero_substitute_the_whole_match () {
    var ampersand = ReplacePattern.parse ("[$&]", true);
    var zero = ReplacePattern.parse ("[$0]", true);

    assert_cmpstr (ampersand.build ({ "hello" }), CompareOperator.EQ, "[hello]");
    assert_cmpstr (zero.build ({ "hello" }), CompareOperator.EQ, "[hello]");
}

private void test_double_dollar_is_a_literal_dollar () {
    var pattern = ReplacePattern.parse ("costs $$5", true);

    assert_cmpstr (pattern.build ({ "whole match" }), CompareOperator.EQ, "costs $5");
}

private void test_two_digit_group_reference () {
    var groups = new string[11];
    for (int i = 0; i < groups.length; i++) {
        groups[i] = "g%d".printf (i);
    }
    var pattern = ReplacePattern.parse ("$10", true);

    assert_cmpstr (pattern.build (groups), CompareOperator.EQ, "g10");
}

private void test_out_of_range_group_reference_is_empty () {
    var pattern = ReplacePattern.parse ("[$5]", true);

    assert_cmpstr (pattern.build ({ "whole match", "a" }), CompareOperator.EQ, "[]");
}

private void test_backslash_escapes_newline_tab_and_backslash () {
    var pattern = ReplacePattern.parse ("a\\nb\\tc\\\\d", true);

    assert_cmpstr (pattern.build ({ "whole match" }), CompareOperator.EQ, "a\nb\tc\\d");
}

private void test_lowercase_u_uppercases_only_the_first_character () {
    var pattern = ReplacePattern.parse ("\\u$1", true);

    assert_cmpstr (pattern.build ({ "hello", "hello" }), CompareOperator.EQ, "Hello");
}

private void test_uppercase_u_uppercases_the_whole_group () {
    var pattern = ReplacePattern.parse ("\\U$1", true);

    assert_cmpstr (pattern.build ({ "hello", "hello" }), CompareOperator.EQ, "HELLO");
}

private void test_lowercase_l_lowercases_the_whole_group () {
    var pattern = ReplacePattern.parse ("\\L$1", true);

    assert_cmpstr (pattern.build ({ "HELLO", "HELLO" }), CompareOperator.EQ, "hello");
}

// \U$1-$2: the case op only ever attaches to the *one* $n reference
// immediately after it — $2 gets none, so it comes through unchanged.
private void test_case_op_only_applies_to_the_immediately_following_group_reference () {
    var pattern = ReplacePattern.parse ("\\U$1-$2", true);

    assert_cmpstr (pattern.build ({ "hello-world", "hello", "world" }), CompareOperator.EQ, "HELLO-world");
}

// \l\U$1 on "Hello": \l lowercases just the first char and consumes
// itself, \U then uppercases everything after it since it never
// consumes — "hELLO", not "hello" or "HELLO".
private void test_stacked_case_ops_apply_in_order () {
    var pattern = ReplacePattern.parse ("\\l\\U$1", true);

    assert_cmpstr (pattern.build ({ "Hello", "Hello" }), CompareOperator.EQ, "hELLO");
}

private void test_static_text_around_group_references_is_preserved () {
    var pattern = ReplacePattern.parse ("[$1]-[$2]", true);

    assert_cmpstr (pattern.build ({ "a-b", "a", "b" }), CompareOperator.EQ, "[a]-[b]");
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/replace-pattern/regex_off_is_always_literal_even_with_dollar_and_backslash", test_regex_off_is_always_literal_even_with_dollar_and_backslash);
    Test.add_func ("/models/replace-pattern/regex_on_with_no_escapes_is_still_literal", test_regex_on_with_no_escapes_is_still_literal);
    Test.add_func ("/models/replace-pattern/dollar_n_substitutes_a_capture_group", test_dollar_n_substitutes_a_capture_group);
    Test.add_func ("/models/replace-pattern/dollar_ampersand_and_dollar_zero_substitute_the_whole_match", test_dollar_ampersand_and_dollar_zero_substitute_the_whole_match);
    Test.add_func ("/models/replace-pattern/double_dollar_is_a_literal_dollar", test_double_dollar_is_a_literal_dollar);
    Test.add_func ("/models/replace-pattern/two_digit_group_reference", test_two_digit_group_reference);
    Test.add_func ("/models/replace-pattern/out_of_range_group_reference_is_empty", test_out_of_range_group_reference_is_empty);
    Test.add_func ("/models/replace-pattern/backslash_escapes_newline_tab_and_backslash", test_backslash_escapes_newline_tab_and_backslash);
    Test.add_func ("/models/replace-pattern/lowercase_u_uppercases_only_the_first_character", test_lowercase_u_uppercases_only_the_first_character);
    Test.add_func ("/models/replace-pattern/uppercase_u_uppercases_the_whole_group", test_uppercase_u_uppercases_the_whole_group);
    Test.add_func ("/models/replace-pattern/lowercase_l_lowercases_the_whole_group", test_lowercase_l_lowercases_the_whole_group);
    Test.add_func ("/models/replace-pattern/case_op_only_applies_to_the_immediately_following_group_reference", test_case_op_only_applies_to_the_immediately_following_group_reference);
    Test.add_func ("/models/replace-pattern/stacked_case_ops_apply_in_order", test_stacked_case_ops_apply_in_order);
    Test.add_func ("/models/replace-pattern/static_text_around_group_references_is_preserved", test_static_text_around_group_references_is_preserved);
    return Test.run ();
}
