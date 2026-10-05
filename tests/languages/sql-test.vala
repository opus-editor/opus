private void test_a_language_without_an_indent_query_keeps_every_line_level () {
    assert_cmpint (LanguageProbe.enter ("a.sql", "SELECT (<|>"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.sql", "CREATE TABLE t (<|>"), CompareOperator.EQ, 0);
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/sql/a_language_without_an_indent_query_keeps_every_line_level", test_a_language_without_an_indent_query_keeps_every_line_level);
    Test.run ();
}
