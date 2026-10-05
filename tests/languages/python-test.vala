private void test_a_colon_goes_one_level_in () {
    assert_cmpint (LanguageProbe.enter ("a.py", "def f():<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.py", "if x:<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.py", "class Foo:<|>"), CompareOperator.EQ, 1);
}

private void test_an_ordinary_statement_stays_level () {
    assert_cmpint (LanguageProbe.enter ("a.py", "x = 1<|>"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.py", "def f():\n    x = 1<|>"), CompareOperator.EQ, 0);
}

private void test_the_line_after_a_statement_in_a_block_stays_in_the_block () {
    assert_cmpint (LanguageProbe.enter ("a.py", "def f():\n    if x:\n        y = 1<|>"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.py", "class Foo:\n    def f(self):\n        return 1<|>\n"), CompareOperator.EQ, 0);
}

private void test_text_inside_a_docstring_opens_nothing_however_it_reads () {
    assert_cmpint (LanguageProbe.enter ("a.py", "def f():\n    \"\"\"\n    if x:<|>\n    \"\"\"\n    pass\n"), CompareOperator.EQ, 0);
}

private void test_functions_and_classes_are_symbols_each_inside_the_one_holding_it () {
    var symbols = LanguageProbe.symbols ("a.py", "def greet():\n    pass\n\nclass Cart:\n    def total(self):\n        pass\n");

    assert_cmpstrv (symbols, { "greet: function", "Cart: class", "total: function · Cart" });
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/python/a_colon_goes_one_level_in", test_a_colon_goes_one_level_in);
    Test.add_func ("/languages/python/an_ordinary_statement_stays_level", test_an_ordinary_statement_stays_level);
    Test.add_func ("/languages/python/the_line_after_a_statement_in_a_block_stays_in_the_block", test_the_line_after_a_statement_in_a_block_stays_in_the_block);
    Test.add_func ("/languages/python/text_inside_a_docstring_opens_nothing_however_it_reads", test_text_inside_a_docstring_opens_nothing_however_it_reads);
    Test.add_func ("/languages/python/functions_and_classes_are_symbols_each_inside_the_one_holding_it", test_functions_and_classes_are_symbols_each_inside_the_one_holding_it);
    Test.run ();
}
