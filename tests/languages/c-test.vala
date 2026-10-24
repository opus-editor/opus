private void test_an_open_brace_goes_one_level_in () {
    assert_cmpint (LanguageProbe.enter ("a.c", "int main(void) {<|>"), CompareOperator.EQ, 1);
}

private void test_an_ordinary_statement_stays_level () {
    assert_cmpint (LanguageProbe.enter ("a.c", "int x = 1;<|>"), CompareOperator.EQ, 0);
}

private void test_a_block_comment_closes_on_its_star () {
    assert_cmpstr (LanguageProbe.type ("a.c", "int x = 1; /<|>", '*'), CompareOperator.EQ, "int x = 1; /*<|> */");
}

private void test_a_quote_at_the_end_of_a_line_comment_is_plain () {
    assert_cmpstr (LanguageProbe.type ("a.c", "// say <|>", '\''), CompareOperator.EQ, "// say '<|>");
}

private void test_a_quote_in_code_closes () {
    assert_cmpstr (LanguageProbe.type ("a.c", "char *s = <|>;", '"'), CompareOperator.EQ, "char *s = \"<|>\";");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/c/an_open_brace_goes_one_level_in", test_an_open_brace_goes_one_level_in);
    Test.add_func ("/languages/c/an_ordinary_statement_stays_level", test_an_ordinary_statement_stays_level);
    Test.add_func ("/languages/c/a_block_comment_closes_on_its_star", test_a_block_comment_closes_on_its_star);
    Test.add_func ("/languages/c/a_quote_at_the_end_of_a_line_comment_is_plain", test_a_quote_at_the_end_of_a_line_comment_is_plain);
    Test.add_func ("/languages/c/a_quote_in_code_closes", test_a_quote_in_code_closes);
    Test.run ();
}
