// The Ruby package: its indent and highlight queries are maintained in
// Opus (see their first lines), so these are what keeps them honest.

private void test_a_block_opener_goes_one_level_in () {
    assert_cmpint (LanguageProbe.enter ("a.rb", "def foo<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "def foo(arg)<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "def self.foo<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "class Foo<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "class Foo < Bar<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "module Foo<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "if foo<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "unless foo<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "while foo<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "items.each do |item|<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "items.each do<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "begin<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "case foo<|>"), CompareOperator.EQ, 1);
}

private void test_an_open_parenthesis_goes_one_level_in () {
    assert_cmpint (LanguageProbe.enter ("a.rb", "foo(<|>"), CompareOperator.EQ, 1);
}

private void test_an_opener_goes_in_while_the_blocks_around_it_are_still_open () {
    assert_cmpint (LanguageProbe.enter ("a.rb", "class Foo\n  def foo<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "def foo\n  if bar<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "class Foo\n  def foo\n    if bar<|>"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "class Foo\n  def foo\n    items.each do |item|<|>"), CompareOperator.EQ, 1);
}

private void test_an_opener_goes_in_with_finished_code_all_around_it () {
    assert_cmpint (LanguageProbe.enter ("a.rb", "class Foo\n  def bar\n    1\n  end\n\n  def foo(arg)<|>\nend\n"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "class Foo\n  def bar\n    1\n  end\n\n  def foo<|>\nend\n"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "class Foo\n  def foo(arg)<|>\n\n  def bar\n    1\n  end\nend\n"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "def foo(arg)<|>\n"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "def foo(arg)<|>\n\ndef bar\n  1\nend\n"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "require \"x\"\n\ndef foo(arg)<|>\n\nputs 1\n"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "def foo\n  if bar<|>\n  baz\nend\n"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "def foo\n  items.each do |item|<|>\nend\n"), CompareOperator.EQ, 1);
}

private void test_an_ordinary_line_stays_level () {
    assert_cmpint (LanguageProbe.enter ("a.rb", "foo<|>"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.rb", "foo = 1<|>"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.rb", "puts \"x\"<|>"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.rb", "def foo\n  bar<|>"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.rb", "def foo\n  if bar\n    baz<|>"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.rb", "class Foo\n  attr_reader :bar<|>"), CompareOperator.EQ, 0);
}

private void test_an_ordinary_line_stays_level_with_finished_code_all_around_it () {
    assert_cmpint (LanguageProbe.enter ("a.rb", "class Foo\n  def bar\n    baz<|>\n  end\nend\n"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.rb", "class Foo\n  attr_reader :a<|>\n\n  def bar\n  end\nend\n"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.rb", "def foo\n  x = 1<|>\n  y = 2\nend\n"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.rb", "def foo(arg)\n  puts arg<|>\nend"), CompareOperator.EQ, 0);
}

private void test_the_line_after_a_block_closer_stays_level () {
    assert_cmpint (LanguageProbe.enter ("a.rb", "def foo\n  bar\nend<|>"), CompareOperator.EQ, 0);
}

private void test_a_plain_line_below_an_unfinished_method_does_not_go_in () {
    assert_cmpint (LanguageProbe.enter ("a.rb", "def foo(arg)\n\nbar<|>"), CompareOperator.LE, 0);
}

private void test_a_block_closer_typed_first_on_its_line_comes_one_level_out () {
    int levels;
    bool closes = LanguageProbe.closes ("a.rb", "def foo\n  bar\n  end<|>", out levels);

    assert_true (closes);
    assert_cmpint (levels, CompareOperator.EQ, -1);
}

private void test_an_inner_closer_comes_out_while_the_outer_block_is_still_open () {
    int levels;
    bool closes = LanguageProbe.closes ("a.rb", "def foo\n  if x\n    y\n    end<|>", out levels);

    assert_true (closes);
    assert_cmpint (levels, CompareOperator.EQ, -1);
}

private void test_a_closer_spelled_later_on_a_line_closes_nothing () {
    int levels;
    bool closes = LanguageProbe.closes ("a.rb", "def foo\n  puts \"the end<|>\"", out levels);

    assert_false (closes);
}

private void test_a_closer_with_more_typed_after_it_is_left_alone () {
    int levels;
    bool closes = LanguageProbe.closes ("a.rb", "def foo\n  bar\n  end.freeze<|>", out levels);

    assert_false (closes);
}

private void test_text_inside_a_heredoc_or_a_comment_opens_nothing_however_it_reads () {
    assert_cmpint (LanguageProbe.enter ("a.rb", "x = <<~TEXT\n  def foo<|>\n  bar\nTEXT\n"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.rb", "x = <<~TEXT\n  call(<|>\n  bar\nTEXT\n"), CompareOperator.EQ, 0);
    assert_cmpint (LanguageProbe.enter ("a.rb", "=begin\ndef foo<|>\n=end\n"), CompareOperator.EQ, 0);
}

private void test_code_right_after_a_string_or_a_comment_is_code_again () {
    assert_cmpint (LanguageProbe.enter ("a.rb", "x = \"a\"\ndef foo<|>\n"), CompareOperator.EQ, 1);
    assert_cmpint (LanguageProbe.enter ("a.rb", "# a note\ndef foo<|>\n"), CompareOperator.EQ, 1);
}

private void test_a_method_name_keeps_its_color_while_the_method_is_being_typed () {
    assert_cmpstr (LanguageProbe.style_of ("a.rb", "def foo", "foo"), CompareOperator.EQ, "function");
    assert_cmpstr (LanguageProbe.style_of ("a.rb", "def foo\n  ", "foo"), CompareOperator.EQ, "function");
    assert_cmpstr (LanguageProbe.style_of ("a.rb", "def foo\n  s", "foo"), CompareOperator.EQ, "function");
    assert_cmpstr (LanguageProbe.style_of ("a.rb", "def foo\n  still_typing", "foo"), CompareOperator.EQ, "function");
    assert_cmpstr (LanguageProbe.style_of ("a.rb", "def foo(arg)\n  still_typing", "foo"), CompareOperator.EQ, "function");
    assert_cmpstr (LanguageProbe.style_of ("a.rb", "def foo(arg)\n\nbar", "foo"), CompareOperator.EQ, "function");
    assert_cmpstr (LanguageProbe.style_of ("a.rb", "def self.foo\n  s", "foo"), CompareOperator.EQ, "function");
    assert_cmpstr (LanguageProbe.style_of ("a.rb", "class Foo\n  def foo\n    s", "foo"), CompareOperator.EQ, "function");
    assert_cmpstr (LanguageProbe.style_of ("a.rb", "def foo\n  still_typing\nend", "foo"), CompareOperator.EQ, "function");
}

private void test_only_the_name_after_def_is_taken_for_a_method_name () {
    assert_cmpstr (LanguageProbe.style_of ("a.rb", "def foo\n  still_typing", "still_typing"), CompareOperator.EQ, "variable");
    assert_cmpstr (LanguageProbe.style_of ("a.rb", "def foo(arg)\n\nbar", "bar"), CompareOperator.EQ, "variable");
}

private void test_classes_modules_and_methods_are_symbols_each_inside_the_one_holding_it () {
    var symbols = LanguageProbe.symbols ("a.rb", "module Shop\n  class Cart\n    def total\n    end\n\n    def self.empty\n    end\n  end\nend\n");

    assert_cmpstrv (symbols, { "Shop: module", "Cart: class · Shop", "total: method · Cart", "empty: method · Cart" });
}

private void test_a_method_outside_any_class_belongs_to_nothing () {
    var symbols = LanguageProbe.symbols ("a.rb", "def greet\nend\n");

    assert_cmpstrv (symbols, { "greet: method" });
}

private void test_a_call_is_not_a_symbol () {
    var symbols = LanguageProbe.symbols ("a.rb", "def greet\n  puts name\nend\n\ngreet\n");

    assert_cmpstrv (symbols, { "greet: method" });
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/ruby/a_block_opener_goes_one_level_in", test_a_block_opener_goes_one_level_in);
    Test.add_func ("/languages/ruby/an_open_parenthesis_goes_one_level_in", test_an_open_parenthesis_goes_one_level_in);
    Test.add_func ("/languages/ruby/an_opener_goes_in_while_the_blocks_around_it_are_still_open", test_an_opener_goes_in_while_the_blocks_around_it_are_still_open);
    Test.add_func ("/languages/ruby/an_opener_goes_in_with_finished_code_all_around_it", test_an_opener_goes_in_with_finished_code_all_around_it);
    Test.add_func ("/languages/ruby/an_ordinary_line_stays_level", test_an_ordinary_line_stays_level);
    Test.add_func ("/languages/ruby/an_ordinary_line_stays_level_with_finished_code_all_around_it", test_an_ordinary_line_stays_level_with_finished_code_all_around_it);
    Test.add_func ("/languages/ruby/the_line_after_a_block_closer_stays_level", test_the_line_after_a_block_closer_stays_level);
    Test.add_func ("/languages/ruby/a_plain_line_below_an_unfinished_method_does_not_go_in", test_a_plain_line_below_an_unfinished_method_does_not_go_in);
    Test.add_func ("/languages/ruby/a_block_closer_typed_first_on_its_line_comes_one_level_out", test_a_block_closer_typed_first_on_its_line_comes_one_level_out);
    Test.add_func ("/languages/ruby/an_inner_closer_comes_out_while_the_outer_block_is_still_open", test_an_inner_closer_comes_out_while_the_outer_block_is_still_open);
    Test.add_func ("/languages/ruby/a_closer_spelled_later_on_a_line_closes_nothing", test_a_closer_spelled_later_on_a_line_closes_nothing);
    Test.add_func ("/languages/ruby/a_closer_with_more_typed_after_it_is_left_alone", test_a_closer_with_more_typed_after_it_is_left_alone);
    Test.add_func ("/languages/ruby/text_inside_a_heredoc_or_a_comment_opens_nothing_however_it_reads", test_text_inside_a_heredoc_or_a_comment_opens_nothing_however_it_reads);
    Test.add_func ("/languages/ruby/code_right_after_a_string_or_a_comment_is_code_again", test_code_right_after_a_string_or_a_comment_is_code_again);
    Test.add_func ("/languages/ruby/a_method_name_keeps_its_color_while_the_method_is_being_typed", test_a_method_name_keeps_its_color_while_the_method_is_being_typed);
    Test.add_func ("/languages/ruby/only_the_name_after_def_is_taken_for_a_method_name", test_only_the_name_after_def_is_taken_for_a_method_name);
    Test.add_func ("/languages/ruby/classes_modules_and_methods_are_symbols_each_inside_the_one_holding_it", test_classes_modules_and_methods_are_symbols_each_inside_the_one_holding_it);
    Test.add_func ("/languages/ruby/a_method_outside_any_class_belongs_to_nothing", test_a_method_outside_any_class_belongs_to_nothing);
    Test.add_func ("/languages/ruby/a_call_is_not_a_symbol", test_a_call_is_not_a_symbol);
    Test.run ();
}
