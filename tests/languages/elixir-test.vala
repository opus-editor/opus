// The Elixir package, ported from Helix: what its queries make the editor do.

private void test_a_block_opener_goes_one_level_in () {
    assert_cmpint (LanguageProbe.enter ("a.ex", "defmodule Foo do<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.ex", "def foo do<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.ex", "x = [<|>"), CompareOperator.EQ, 1);
}

private void test_an_ordinary_line_stays_level () {
    assert_cmpint (LanguageProbe.enter ("a.ex", "x = 1<|>"), CompareOperator.EQ, 0);
}

private void test_end_closes_the_block_it_is_typed_in () {
    int levels;

    bool closes = LanguageProbe.closes ("a.ex", "def foo do\n  1\n  end<|>", out levels);

    assert_true (closes);
    assert_cmpint (levels, CompareOperator.EQ, -1);
}

private void test_modules_and_functions_are_listed_with_their_nesting () {
    var symbols = LanguageProbe.symbols ("a.ex", "defmodule Foo do\n  def bar, do: 1\n\n  defp baz(x) do\n    x\n  end\nend\n");

    assert_cmpstrv (symbols, { "Foo: module", "bar: function · Foo", "baz: function · Foo" });
}

private void test_keywords_comments_strings_and_atoms_have_their_colors () {
    string text = "defmodule Foo do\n  # c\n  def s, do: {:ok, \"s\"}\nend\n";

    assert_cmpstr (LanguageProbe.style_of ("a.ex", text, "defmodule"), CompareOperator.EQ, "keyword");
    assert_cmpstr (LanguageProbe.style_of ("a.ex", text, "# c"), CompareOperator.EQ, "comment");
    assert_cmpstr (LanguageProbe.style_of ("a.ex", text, "\"s\""), CompareOperator.EQ, "string");
    assert_cmpstr (LanguageProbe.style_of ("a.ex", text, ":ok"), CompareOperator.EQ, "string");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/elixir/a_block_opener_goes_one_level_in", test_a_block_opener_goes_one_level_in);
    Test.add_func ("/languages/elixir/an_ordinary_line_stays_level", test_an_ordinary_line_stays_level);
    Test.add_func ("/languages/elixir/end_closes_the_block_it_is_typed_in", test_end_closes_the_block_it_is_typed_in);
    Test.add_func ("/languages/elixir/modules_and_functions_are_listed_with_their_nesting", test_modules_and_functions_are_listed_with_their_nesting);
    Test.add_func ("/languages/elixir/keywords_comments_strings_and_atoms_have_their_colors", test_keywords_comments_strings_and_atoms_have_their_colors);
    Test.run ();
}
