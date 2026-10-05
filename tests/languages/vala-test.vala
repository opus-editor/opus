// The Vala package: its indent query is written for Opus, Helix having
// none, so this is all that keeps it honest.

private void test_an_open_brace_goes_one_level_in () {
    assert_cmpint (LanguageProbe.enter ("a.vala", "public class Foo : Object {<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.vala", "void main () {<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.vala", "namespace Foo {<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.vala", "void main () {\n  if (x) {<|>"), CompareOperator.EQ, 1);
}

private void test_an_ordinary_statement_stays_level () {
    assert_cmpint (LanguageProbe.enter ("a.vala", "void main () {\n  int x = 1;<|>\n}"), CompareOperator.EQ, 0);
}

private void test_a_closing_brace_typed_first_on_its_line_comes_one_level_out () {
    int levels;
    bool closes = LanguageProbe.closes ("a.vala", "void main () {\n  int x = 1;\n  }<|>", out levels);

    assert_true (closes);
    assert_cmpint (levels, CompareOperator.EQ, -1);
}

private void test_text_inside_a_comment_opens_nothing_however_it_reads () {
    assert_cmpint (LanguageProbe.enter ("a.vala", "/*\n * void main () {<|>\n */\n"), CompareOperator.EQ, 0);
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/vala/an_open_brace_goes_one_level_in", test_an_open_brace_goes_one_level_in);
    Test.add_func ("/languages/vala/an_ordinary_statement_stays_level", test_an_ordinary_statement_stays_level);
    Test.add_func ("/languages/vala/a_closing_brace_typed_first_on_its_line_comes_one_level_out", test_a_closing_brace_typed_first_on_its_line_comes_one_level_out);
    Test.add_func ("/languages/vala/text_inside_a_comment_opens_nothing_however_it_reads", test_text_inside_a_comment_opens_nothing_however_it_reads);
    Test.run ();
}
