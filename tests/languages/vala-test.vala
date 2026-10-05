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

private void test_types_are_symbols_each_inside_the_namespace_holding_it () {
    var symbols = LanguageProbe.symbols ("a.vala", "namespace Shop {\n  public class Cart : Object {\n  }\n  public interface Priced : Object {\n  }\n  public struct Money {\n    int cents;\n  }\n  public enum Size {\n    SMALL,\n    LARGE\n  }\n}\n");

    assert_cmpstrv (symbols, { "Shop: module", "Cart: class · Shop", "Priced: interface · Shop", "Money: struct · Shop", "Size: enum · Shop" });
}

private void test_the_members_of_a_class_are_symbols_inside_it () {
    var symbols = LanguageProbe.symbols ("a.vala", "public class Cart : Object {\n  public const int LIMIT = 10;\n  public int count { get; set; }\n  public signal void emptied ();\n  public Cart () {\n  }\n  public Cart.with_limit (int limit) {\n  }\n  public int total () {\n    return 0;\n  }\n}\n");

    assert_cmpstrv (symbols, { "Cart: class", "LIMIT: constant · Cart", "count: property · Cart", "emptied: signal · Cart", "Cart: constructor · Cart", "Cart.with_limit: constructor · Cart", "total: method · Cart" });
}

private void test_a_method_outside_any_class_belongs_to_nothing () {
    var symbols = LanguageProbe.symbols ("a.vala", "void main (string[] args) {\n}\n");

    assert_cmpstrv (symbols, { "main: method" });
}

private void test_a_delegate_is_a_symbol () {
    var symbols = LanguageProbe.symbols ("a.vala", "public delegate bool Accepts (string text);\n");

    assert_cmpstrv (symbols, { "Accepts: delegate" });
}

private void test_a_field_and_a_local_variable_are_not_symbols () {
    var symbols = LanguageProbe.symbols ("a.vala", "public class Cart : Object {\n  private int count;\n  public void clear () {\n    int before = count;\n  }\n}\n");

    assert_cmpstrv (symbols, { "Cart: class", "clear: method · Cart" });
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/vala/an_open_brace_goes_one_level_in", test_an_open_brace_goes_one_level_in);
    Test.add_func ("/languages/vala/an_ordinary_statement_stays_level", test_an_ordinary_statement_stays_level);
    Test.add_func ("/languages/vala/a_closing_brace_typed_first_on_its_line_comes_one_level_out", test_a_closing_brace_typed_first_on_its_line_comes_one_level_out);
    Test.add_func ("/languages/vala/text_inside_a_comment_opens_nothing_however_it_reads", test_text_inside_a_comment_opens_nothing_however_it_reads);
    Test.add_func ("/languages/vala/types_are_symbols_each_inside_the_namespace_holding_it", test_types_are_symbols_each_inside_the_namespace_holding_it);
    Test.add_func ("/languages/vala/the_members_of_a_class_are_symbols_inside_it", test_the_members_of_a_class_are_symbols_inside_it);
    Test.add_func ("/languages/vala/a_method_outside_any_class_belongs_to_nothing", test_a_method_outside_any_class_belongs_to_nothing);
    Test.add_func ("/languages/vala/a_delegate_is_a_symbol", test_a_delegate_is_a_symbol);
    Test.add_func ("/languages/vala/a_field_and_a_local_variable_are_not_symbols", test_a_field_and_a_local_variable_are_not_symbols);
    Test.run ();
}
