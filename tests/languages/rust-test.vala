private void test_an_open_brace_goes_one_level_in () {
    assert_cmpint (LanguageProbe.enter ("a.rs", "fn main() {<|>"), CompareOperator.EQ, 1);
}

private void test_an_ordinary_statement_stays_level () {
    assert_cmpint (LanguageProbe.enter ("a.rs", "let x = 1;<|>"), CompareOperator.EQ, 0);
}

private void test_a_single_quote_is_a_lifetime_not_a_string () {
    assert_cmpstr (LanguageProbe.type ("a.rs", "let x = <|>", '\''), CompareOperator.EQ, "let x = '<|>");
}

private void test_an_angle_bracket_does_not_close () {
    assert_cmpstr (LanguageProbe.type ("a.rs", "fn f<|>", '<'), CompareOperator.EQ, "fn f<<|>");
}

private void test_a_parenthesis_closes () {
    assert_cmpstr (LanguageProbe.type ("a.rs", "let x = <|>", '('), CompareOperator.EQ, "let x = (<|>)");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/rust/an_open_brace_goes_one_level_in", test_an_open_brace_goes_one_level_in);
    Test.add_func ("/languages/rust/an_ordinary_statement_stays_level", test_an_ordinary_statement_stays_level);
    Test.add_func ("/languages/rust/a_single_quote_is_a_lifetime_not_a_string", test_a_single_quote_is_a_lifetime_not_a_string);
    Test.add_func ("/languages/rust/an_angle_bracket_does_not_close", test_an_angle_bracket_does_not_close);
    Test.add_func ("/languages/rust/a_parenthesis_closes", test_a_parenthesis_closes);
    Test.run ();
}
