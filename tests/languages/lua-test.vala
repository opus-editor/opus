// The Lua package, ported from Helix: what its queries make the editor do.

private void test_a_block_opener_goes_one_level_in () {
    assert_cmpint (LanguageProbe.enter ("a.lua", "function foo()<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.lua", "if x then<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.lua", "for i = 1, 2 do<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.lua", "while x do<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.lua", "local t = {<|>"), CompareOperator.EQ, 1);
}

private void test_else_goes_back_out_and_opens_its_own_branch () {
    assert_cmpint (LanguageProbe.enter ("a.lua", "if x then\n  y\nelse<|>"), CompareOperator.EQ, 1);
}

private void test_a_finished_block_still_opens_a_line_inside_it () {
    assert_cmpint (LanguageProbe.enter ("a.lua", "function foo()<|>\nend"), CompareOperator.EQ, 1);
}

private void test_an_ordinary_line_stays_level () {
    assert_cmpint (LanguageProbe.enter ("a.lua", "local x = 1<|>"), CompareOperator.EQ, 0);
}

private void test_end_closes_the_block_it_is_typed_in () {
    int levels;

    bool closes = LanguageProbe.closes ("a.lua", "function foo()\n  x = 1\n  end<|>", out levels);

    assert_true (closes);
    assert_cmpint (levels, CompareOperator.EQ, -1);
}

private void test_functions_are_listed_by_name () {
    var symbols = LanguageProbe.symbols ("a.lua", "function foo() end\nlocal function bar() end\nfunction M.baz() end\n");

    assert_cmpstrv (symbols, { "foo: function", "bar: function", "baz: function" });
}

private void test_keywords_comments_strings_and_calls_have_their_colors () {
    string text = "local x = \"s\" -- hi\nprint(x)\n";

    assert_cmpstr (LanguageProbe.style_of ("a.lua", text, "local"), CompareOperator.EQ, "keyword");
    assert_cmpstr (LanguageProbe.style_of ("a.lua", text, "\"s\""), CompareOperator.EQ, "string");
    assert_cmpstr (LanguageProbe.style_of ("a.lua", text, "-- hi"), CompareOperator.EQ, "comment");
    assert_cmpstr (LanguageProbe.style_of ("a.lua", text, "print"), CompareOperator.EQ, "function");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/lua/a_block_opener_goes_one_level_in", test_a_block_opener_goes_one_level_in);
    Test.add_func ("/languages/lua/else_goes_back_out_and_opens_its_own_branch", test_else_goes_back_out_and_opens_its_own_branch);
    Test.add_func ("/languages/lua/a_finished_block_still_opens_a_line_inside_it", test_a_finished_block_still_opens_a_line_inside_it);
    Test.add_func ("/languages/lua/an_ordinary_line_stays_level", test_an_ordinary_line_stays_level);
    Test.add_func ("/languages/lua/end_closes_the_block_it_is_typed_in", test_end_closes_the_block_it_is_typed_in);
    Test.add_func ("/languages/lua/functions_are_listed_by_name", test_functions_are_listed_by_name);
    Test.add_func ("/languages/lua/keywords_comments_strings_and_calls_have_their_colors", test_keywords_comments_strings_and_calls_have_their_colors);
    Test.run ();
}
