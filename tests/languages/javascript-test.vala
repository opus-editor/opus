private void test_an_open_brace_goes_one_level_in () {
    assert_cmpint (LanguageProbe.enter ("a.js", "function f() {<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.js", "if (x) {<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.js", "const f = () => {<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.js", "const o = {<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.js", "foo(\"a\", {<|>"), CompareOperator.EQ, 1);
}

private void test_an_ordinary_statement_stays_level () {
    assert_cmpint (LanguageProbe.enter ("a.js", "foo();<|>"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.js", "const a = 1;<|>"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.js", "function f() {\n  x;<|>\n}"), CompareOperator.EQ, 0);
}

private void test_a_closing_brace_typed_first_on_its_line_comes_one_level_out () {
    int levels;
    bool closes = LanguageProbe.closes ("a.js", "function f() {\n  x;\n  }<|>", out levels);

    assert_true (closes);
    assert_cmpint (levels, CompareOperator.EQ, -1);
}

private void test_text_inside_a_comment_or_a_template_string_opens_nothing_however_it_reads () {
    assert_cmpint (LanguageProbe.enter ("a.js", "/*\n * if (x) {<|>\n */\nfoo();\n"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.js", "const s = `\n  function f() {<|>\n`;\n"), CompareOperator.EQ, 0);
}

private void test_code_right_after_a_comment_is_code_again () {
    assert_cmpint (LanguageProbe.enter ("a.js", "/* a note */\nif (x) {<|>\n"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.js", "if (x) { // a note<|>\n"), CompareOperator.EQ, 1);
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/javascript/an_open_brace_goes_one_level_in", test_an_open_brace_goes_one_level_in);
    Test.add_func ("/languages/javascript/an_ordinary_statement_stays_level", test_an_ordinary_statement_stays_level);
    Test.add_func ("/languages/javascript/a_closing_brace_typed_first_on_its_line_comes_one_level_out", test_a_closing_brace_typed_first_on_its_line_comes_one_level_out);
    Test.add_func ("/languages/javascript/text_inside_a_comment_or_a_template_string_opens_nothing_however_it_reads", test_text_inside_a_comment_or_a_template_string_opens_nothing_however_it_reads);
    Test.add_func ("/languages/javascript/code_right_after_a_comment_is_code_again", test_code_right_after_a_comment_is_code_again);
    Test.run ();
}
