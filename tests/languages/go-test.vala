private void test_an_open_brace_goes_one_level_in () {
    assert_cmpint (LanguageProbe.enter ("a.go", "func main() {<|>"), CompareOperator.EQ, 1);
}

private void test_an_ordinary_statement_stays_level () {
    assert_cmpint (LanguageProbe.enter ("a.go", "x := 1<|>"), CompareOperator.EQ, 0);
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/go/an_open_brace_goes_one_level_in", test_an_open_brace_goes_one_level_in);
    Test.add_func ("/languages/go/an_ordinary_statement_stays_level", test_an_ordinary_statement_stays_level);
    Test.run ();
}
