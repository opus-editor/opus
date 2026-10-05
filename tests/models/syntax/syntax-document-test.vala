// Runs against the bundled JSON grammar — OPUS_GRAMMARS_DIR is set by
// tests/meson.build.

/** A JSON language whose highlights query is `highlights_query`, painted by a theme defining `style_keys`. */
private Syntax.LoadedLanguage json_with (string highlights_query, string[] style_keys) {
    string languages = Path.build_filename (Environment.get_tmp_dir (), "opus-syntax-document-test-%u".printf (Random.next_int ()));
    string queries = Path.build_filename (languages, "json", "queries");
    DirUtils.create_with_parents (queries, 0700);
    try {
        FileUtils.set_contents (Path.build_filename (languages, "json", "language.json"), """{ "name": "json", "grammar": { "repository": "r", "rev": "abc" } }""");
        FileUtils.set_contents (Path.build_filename (queries, "highlights.scm"), highlights_query);
        var registry = new Syntax.LanguageRegistry ({ languages });
        return Syntax.LoadedLanguage.load (
            registry.by_name ("json"),
            new Syntax.GrammarLoader ({ Environment.get_variable ("OPUS_GRAMMARS_DIR") }),
            new Syntax.QuerySource (registry),
            new Syntax.CaptureStyles (style_keys)
        );
    } catch (Error e) {
        error ("%s", e.message);
    }
}

/** Each span as "row:column-row:column style". */
private string[] described (Syntax.HighlightSpan[] spans) {
    string[] lines = {};
    foreach (var span in spans) {
        lines += "%u:%u-%u:%u %s".printf (span.start_row, span.start_column, span.end_row, span.end_column, span.style);
    }
    return lines;
}

/**
 * A JSON document that embeds CSS wherever `json_injections` says, with
 * JSON strings painted "string" and CSS property names and values
 * painted "property" and "value".
 */
private Syntax.SyntaxDocument json_embedding_css (string json_injections) {
    string directory = Path.build_filename (Environment.get_tmp_dir (), "opus-syntax-document-test-%u".printf (Random.next_int ()));
    try {
        DirUtils.create_with_parents (Path.build_filename (directory, "json", "queries"), 0700);
        FileUtils.set_contents (Path.build_filename (directory, "json", "language.json"), """{ "name": "json", "file-types": ["json"], "grammar": { "repository": "r", "rev": "abc" } }""");
        FileUtils.set_contents (Path.build_filename (directory, "json", "queries", "highlights.scm"), "(string) @string");
        FileUtils.set_contents (Path.build_filename (directory, "json", "queries", "injections.scm"), json_injections);
        DirUtils.create_with_parents (Path.build_filename (directory, "css", "queries"), 0700);
        FileUtils.set_contents (Path.build_filename (directory, "css", "language.json"), """{ "name": "css", "injection-regex": "^(css|style)$", "grammar": { "repository": "r", "rev": "abc" } }""");
        FileUtils.set_contents (Path.build_filename (directory, "css", "queries", "highlights.scm"), "(property_name) @property\n(plain_value) @value");
    } catch (FileError e) {
        error ("%s", e.message);
    }
    var languages = new Syntax.Languages ({ directory }, { Environment.get_variable ("OPUS_GRAMMARS_DIR") }, { "string", "property", "value" });
    return new Syntax.SyntaxDocument (languages.detect ("document.json"), languages);
}

/**
 * A JSON language with a locals query, where an object is a scope, a
 * pair's key defines a local and every string is a reference — so a
 * string value spelled like a key of its object is a reference to it.
 * By default a string is painted "keyword" unless it is such a
 * reference, which makes the resolved ones the strings left unpainted.
 */
private Syntax.SyntaxDocument json_with_locals (string locals_query, string highlights_query = "((string) @keyword (#is-not? local))") {
    string languages = Path.build_filename (Environment.get_tmp_dir (), "opus-syntax-document-test-%u".printf (Random.next_int ()));
    string queries = Path.build_filename (languages, "json", "queries");
    DirUtils.create_with_parents (queries, 0700);
    try {
        FileUtils.set_contents (Path.build_filename (languages, "json", "language.json"), """{ "name": "json", "grammar": { "repository": "r", "rev": "abc" } }""");
        FileUtils.set_contents (Path.build_filename (queries, "highlights.scm"), highlights_query);
        FileUtils.set_contents (Path.build_filename (queries, "locals.scm"), locals_query);
        var registry = new Syntax.LanguageRegistry ({ languages });
        return new Syntax.SyntaxDocument (Syntax.LoadedLanguage.load (
            registry.by_name ("json"),
            new Syntax.GrammarLoader ({ Environment.get_variable ("OPUS_GRAMMARS_DIR") }),
            new Syntax.QuerySource (registry),
            new Syntax.CaptureStyles ({ "string", "constant", "keyword" })
        ));
    } catch (Error e) {
        error ("%s", e.message);
    }
}

private const string KEYS_DEFINE_LOCALS = "(object) @local.scope\n(pair key: (string) @local.definition.constant)\n(string) @local.reference";

private void test_a_reference_to_a_local_is_told_apart_from_other_names () {
    var document = json_with_locals (KEYS_DEFINE_LOCALS);
    //                  0123456789012345
    document.set_text ("{\"a\": [\"a\", \"b\"]}");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:12-0:15 keyword" });
}

private void test_a_reference_is_not_repainted_as_its_definition () {
    var document = json_with_locals (KEYS_DEFINE_LOCALS, "(string) @string");
    document.set_text ("{\"a\": [\"a\"]}");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:1-0:4 string", "0:7-0:10 string" });
}

private void test_a_definition_is_not_visible_outside_its_scope () {
    var document = json_with_locals (KEYS_DEFINE_LOCALS);
    //                  01234567890123
    document.set_text ("[{\"a\": 1}, \"a\"]");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:11-0:14 keyword" });
}

private void test_an_inner_scope_sees_the_definitions_around_it () {
    var document = json_with_locals (KEYS_DEFINE_LOCALS);
    document.set_text ("{\"a\": {\"b\": \"a\"}}");

    var spans = document.highlights (0, 0);

    assert_cmpuint (spans.length, CompareOperator.EQ, 0);
}

private void test_a_scope_that_does_not_inherit_hides_the_definitions_around_it () {
    var document = json_with_locals ("((object) @local.scope (#set! local.scope-inherits false))\n(pair key: (string) @local.definition.constant)\n(string) @local.reference");
    //                  012345678901234
    document.set_text ("{\"a\": {\"b\": \"a\"}}");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:12-0:15 keyword" });
}

private void test_a_later_capture_on_the_node_cancels_the_reference () {
    var document = json_with_locals (KEYS_DEFINE_LOCALS + "\n(array (string) @_not_a_reference)");
    document.set_text ("{\"a\": [\"a\"]}");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:7-0:10 keyword" });
}

private void test_a_reference_ahead_of_its_definition_is_not_resolved () {
    var document = json_with_locals (KEYS_DEFINE_LOCALS);
    //                  0123456789
    document.set_text ("{\"b\": \"a\", \"a\": 1}");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:6-0:9 keyword" });
}

private void test_a_pattern_for_locals_only_applies_to_resolved_references () {
    var document = json_with_locals (KEYS_DEFINE_LOCALS, "((string) @keyword (#is? local))");
    document.set_text ("{\"a\": [\"a\", \"b\"]}");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:1-0:4 keyword", "0:7-0:10 keyword" });
}

private void test_locals_follow_an_edit () {
    var document = json_with_locals (KEYS_DEFINE_LOCALS);
    document.set_text ("{\"a\": [\"b\"]}");

    document.set_text ("{\"b\": [\"b\"]}");

    assert_cmpuint (document.highlights (0, 0).length, CompareOperator.EQ, 0);
}

private Syntax.Languages? bundled_languages = null;

/** A document in the bundled language that claims `file_name`, holding `text` — OPUS_LANGUAGES_DIR is set by tests/meson.build. */
private Syntax.SyntaxDocument bundled (string file_name, string text) {
    // One for the whole binary: reading forty packages again for every
    // call made this file's tests take a quarter of a minute.
    if (bundled_languages == null) {
        bundled_languages = new Syntax.Languages ({ Environment.get_variable ("OPUS_LANGUAGES_DIR") }, { Environment.get_variable ("OPUS_GRAMMARS_DIR") }, { "function", "variable", "keyword" });
    }
    var languages = bundled_languages;
    var document = new Syntax.SyntaxDocument (languages.detect (file_name), languages);
    document.set_text (text);
    return document;
}

private void test_a_line_broken_after_a_block_opener_goes_one_level_in () {
    var document = bundled ("a.rb", "def foo(arg)");

    int change = document.new_line_indent_change (12);

    assert_cmpint (change, CompareOperator.EQ, 1);
}

/** How many levels Enter at the very end of `text` adds, in the bundled language claiming `file_name`. */
private int change_at_the_end (string file_name, string text) {
    return bundled (file_name, text).new_line_indent_change (text.char_count ());
}

private void test_ruby_block_openers_each_go_one_level_in () {
    assert_cmpint (change_at_the_end ("a.rb", "def foo"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "def foo(arg)"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "def self.foo"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "class Foo"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "class Foo < Bar"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "module Foo"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "if foo"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "unless foo"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "while foo"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "items.each do |item|"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "items.each do"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "begin"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "case foo"), CompareOperator.EQ, 1);
}

private void test_ruby_block_openers_go_in_inside_a_class_too () {
    assert_cmpint (change_at_the_end ("a.rb", "class Foo\n  def foo"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "class Foo\n  def foo\n    if bar"), CompareOperator.EQ, 1);
}

/** How many levels Enter adds where `<|>` stands in `text`, the way it would be found in a real file: with code before and after it. */
private int change_at_the_bar (string file_name, string text) {
    int bar = text.index_of ("<|>");
    var without_bar = text.substring (0, bar) + text.substring (bar + 3);
    return bundled (file_name, without_bar).new_line_indent_change (text.substring (0, bar).char_count ());
}

private void test_ruby_openers_go_in_with_code_all_around_them () {
    assert_cmpint (change_at_the_bar ("a.rb", "class Foo\n  def bar\n    1\n  end\n\n  def foo(arg)<|>\nend\n"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_bar ("a.rb", "class Foo\n  def bar\n    1\n  end\n\n  def foo<|>\nend\n"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_bar ("a.rb", "class Foo\n  def foo(arg)<|>\n\n  def bar\n    1\n  end\nend\n"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_bar ("a.rb", "def foo(arg)<|>\n"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_bar ("a.rb", "def foo(arg)<|>\n\ndef bar\n  1\nend\n"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_bar ("a.rb", "require \"x\"\n\ndef foo(arg)<|>\n\nputs 1\n"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_bar ("a.rb", "def foo\n  if bar<|>\n  baz\nend\n"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_bar ("a.rb", "def foo\n  items.each do |item|<|>\nend\n"), CompareOperator.EQ, 1);
}

private void test_ruby_ordinary_lines_stay_level_with_code_all_around_them () {
    assert_cmpint (change_at_the_bar ("a.rb", "class Foo\n  def bar\n    baz<|>\n  end\nend\n"), CompareOperator.EQ, 0);
    assert_cmpint (change_at_the_bar ("a.rb", "class Foo\n  attr_reader :a<|>\n\n  def bar\n  end\nend\n"), CompareOperator.EQ, 0);
    assert_cmpint (change_at_the_bar ("a.rb", "def foo\n  x = 1<|>\n  y = 2\nend\n"), CompareOperator.EQ, 0);
}

private void test_ruby_nested_openers_go_in_while_the_outer_block_is_still_open () {
    assert_cmpint (change_at_the_end ("a.rb", "def foo\n  if bar"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "class Foo\n  def foo\n    items.each do |item|"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rb", "def foo\n  if bar\n    baz"), CompareOperator.EQ, 0);
}

private void test_an_inner_closer_comes_out_while_the_outer_block_is_still_open () {
    //                                 01234567 890123 456789 01234567
    var document = bundled ("a.rb", "def foo\n  if x\n    y\n    end");

    int levels;
    bool closes = document.outdent_change (28, 17, out levels);

    assert_true (closes);
    assert_cmpint (levels, CompareOperator.EQ, -1);
}

private void test_ruby_ordinary_lines_stay_level () {
    assert_cmpint (change_at_the_end ("a.rb", "foo"), CompareOperator.EQ, 0);
    assert_cmpint (change_at_the_end ("a.rb", "foo = 1"), CompareOperator.EQ, 0);
    assert_cmpint (change_at_the_end ("a.rb", "puts \"x\""), CompareOperator.EQ, 0);
    assert_cmpint (change_at_the_end ("a.rb", "def foo\n  bar"), CompareOperator.EQ, 0);
    assert_cmpint (change_at_the_end ("a.rb", "class Foo\n  attr_reader :bar"), CompareOperator.EQ, 0);
}

private void test_openers_in_other_languages_go_one_level_in () {
    assert_cmpint (change_at_the_end ("a.js", "function f() {"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.js", "if (x) {"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.js", "const f = () => {"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.js", "const o = {"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.py", "def f():"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.py", "if x:"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.py", "class Foo:"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.go", "func main() {"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.rs", "fn main() {"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.c", "int main(void) {"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.php", "<?php\nfunction f() {"), CompareOperator.EQ, 1);
    assert_cmpint (change_at_the_end ("a.vala", "void main () {"), CompareOperator.EQ, 1);
}

private void test_ordinary_lines_in_other_languages_stay_level () {
    assert_cmpint (change_at_the_end ("a.js", "foo();"), CompareOperator.EQ, 0);
    assert_cmpint (change_at_the_end ("a.js", "const a = 1;"), CompareOperator.EQ, 0);
    assert_cmpint (change_at_the_end ("a.py", "x = 1"), CompareOperator.EQ, 0);
    assert_cmpint (change_at_the_end ("a.go", "x := 1"), CompareOperator.EQ, 0);
    assert_cmpint (change_at_the_end ("a.rs", "let x = 1;"), CompareOperator.EQ, 0);
    assert_cmpint (change_at_the_end ("a.c", "int x = 1;"), CompareOperator.EQ, 0);
}

private void test_a_line_broken_after_an_ordinary_statement_stays_level () {
    var document = bundled ("a.rb", "def foo(arg)\n  puts arg\nend");

    int change = document.new_line_indent_change (23);

    assert_cmpint (change, CompareOperator.EQ, 0);
}

private void test_each_position_is_answered_by_its_own_context () {
    //                                 0123456789012 3 4567
    var document = bundled ("a.rb", "def foo(arg)\n\nbar");

    int after_the_method_header = document.new_line_indent_change (12);
    int after_the_plain_line = document.new_line_indent_change (17);

    assert_cmpint (after_the_method_header, CompareOperator.EQ, 1);
    assert_cmpint (after_the_plain_line, CompareOperator.LE, 0);
}

private void test_a_line_broken_inside_open_parentheses_goes_one_level_in () {
    var document = bundled ("a.rb", "foo(");

    int change = document.new_line_indent_change (4);

    assert_cmpint (change, CompareOperator.EQ, 1);
}

private void test_a_line_broken_after_a_block_closer_stays_level () {
    var document = bundled ("a.rb", "def foo\n  bar\nend");

    int change = document.new_line_indent_change (17);

    assert_cmpint (change, CompareOperator.EQ, 0);
}

private void test_a_line_broken_in_its_leading_whitespace_is_left_alone () {
    var document = bundled ("a.rb", "def foo\n  bar\nend");

    int change = document.new_line_indent_change (9);

    assert_cmpint (change, CompareOperator.EQ, 0);
}

private void test_a_brace_opens_a_level_in_javascript () {
    var document = bundled ("a.js", "function f() {");

    int change = document.new_line_indent_change (14);

    assert_cmpint (change, CompareOperator.EQ, 1);
}

private void test_a_colon_opens_a_level_in_python () {
    var document = bundled ("a.py", "def f():");

    int change = document.new_line_indent_change (8);

    assert_cmpint (change, CompareOperator.EQ, 1);
}

private void test_a_language_without_an_indents_query_has_nothing_to_say () {
    var document = bundled ("a.sql", "SELECT (");

    int change = document.new_line_indent_change (8);

    assert_cmpint (change, CompareOperator.EQ, 0);
}

private void test_a_block_closer_typed_first_on_its_line_comes_one_level_out () {
    //                                 01234567 890123 456789
    var document = bundled ("a.rb", "def foo\n  bar\n  end");

    int levels;
    bool closes = document.outdent_change (19, 10, out levels);

    assert_true (closes);
    assert_cmpint (levels, CompareOperator.EQ, -1);
}

private void test_a_closing_brace_comes_one_level_out_in_javascript () {
    //                                 01234567890123 45678 9012
    var document = bundled ("a.js", "function f() {\n  x;\n  }");

    int levels;
    bool closes = document.outdent_change (23, 17, out levels);

    assert_true (closes);
    assert_cmpint (levels, CompareOperator.EQ, -1);
}

private void test_the_same_word_later_on_a_line_closes_nothing () {
    //                                 01234567 8901234567890123
    var document = bundled ("a.rb", "def foo\n  puts \"the end\"");

    int levels;
    bool closes = document.outdent_change (23, 8, out levels);

    assert_false (closes);
}

private void test_a_closer_with_more_typed_after_it_is_left_alone () {
    var document = bundled ("a.rb", "def foo\n  bar\n  end.freeze");

    int levels;
    bool closes = document.outdent_change (26, 10, out levels);

    assert_false (closes);
}

private void test_a_class_opens_a_level_in_vala () {
    var document = bundled ("a.vala", "public class Foo : Object {");

    int change = document.new_line_indent_change (27);

    assert_cmpint (change, CompareOperator.EQ, 1);
}

private void test_a_statement_inside_a_vala_method_stays_level () {
    //                                   0123456789012345 67890123456789
    var document = bundled ("a.vala", "void main () {\n  int x = 1;\n}");

    int change = document.new_line_indent_change (27);

    assert_cmpint (change, CompareOperator.EQ, 0);
}

private void test_a_closing_brace_comes_one_level_out_in_vala () {
    //                                   01234567890123 4567890123456 789
    var document = bundled ("a.vala", "void main () {\n  int x = 1;\n  }");

    int levels;
    bool closes = document.outdent_change (31, 15, out levels);

    assert_true (closes);
    assert_cmpint (levels, CompareOperator.EQ, -1);
}

/** JSON large enough that a parse of it is asked whether to go on many times over: one number per row. */
private string large_json (int rows) {
    var text = new StringBuilder ("[\n");
    for (int i = 0; i < rows; i++) {
        text.append ("1,\n");
    }
    text.append ("2]");
    return text.str;
}

private void test_a_parse_within_its_budget_finishes () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number", { "number" }));

    bool finished = document.set_text ("[1]", 10 * 1000 * 1000);

    assert_true (finished);
    assert_cmpstrv (described (document.highlights (0, 0)), { "0:1-0:2 number" });
}

private void test_a_parse_out_of_budget_stops_unfinished () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number", { "number" }));

    bool finished = document.set_text (large_json (50000), 0);

    assert_false (finished);
}

private void test_an_unfinished_parse_keeps_answering_from_the_previous_trees () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number", { "number" }));
    document.set_text ("[\n1,\n7]");

    document.set_text (large_json (50000), 0);

    assert_cmpstrv (described (document.highlights (1, 1)), { "1:0-1:1 number" });
}

private void test_resuming_finishes_the_parse () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number", { "number" }));
    document.set_text (large_json (50000), 0);

    // Slices long enough to get somewhere, short enough to need many.
    bool finished = false;
    int slices = 0;
    while (!finished && slices < 100000) {
        finished = document.resume (500);
        slices++;
    }

    assert_true (finished);
    assert_cmpint (slices, CompareOperator.GT, 1);
    assert_cmpstrv (described (document.highlights (50001, 50001)), { "50001:0-50001:1 number" });
}

private void test_new_text_replaces_an_unfinished_parse () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number\n(true) @keyword", { "number", "keyword" }));
    document.set_text (large_json (50000), 0);

    bool finished = document.set_text ("[true]");

    assert_true (finished);
    assert_cmpstrv (described (document.highlights (0, 0)), { "0:1-0:5 keyword" });
}

private void test_an_injected_language_is_painted_over_its_host () {
    var document = json_embedding_css ("((string_content) @injection.content (#set! injection.language \"css\"))");
    document.set_text ("[\"a{color:red}\"]");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:1-0:4 string", "0:4-0:9 property", "0:9-0:10 string", "0:10-0:13 value", "0:13-0:15 string" });
}

private void test_the_injected_language_can_be_named_by_the_text_itself () {
    var document = json_embedding_css ("(pair key: (string (string_content) @injection.language) value: (string (string_content) @injection.content))");
    document.set_text ("{\"style\": \"a{color:red}\"}");

    var spans = document.highlights (0, 0);

    assert_true ("0:13-0:18 property" in described (spans));
}

private void test_an_injection_naming_no_known_language_leaves_the_host_alone () {
    var document = json_embedding_css ("((string_content) @injection.content (#set! injection.language \"klingon\"))");
    document.set_text ("[\"a{color:red}\"]");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:1-0:15 string" });
}

private void test_a_document_without_a_language_resolver_is_not_injected () {
    var with_resolver = json_embedding_css ("((string_content) @injection.content (#set! injection.language \"css\"))");
    with_resolver.set_text ("[\"a{color:red}\"]");
    var host_only = new Syntax.SyntaxDocument (json_with ("(string) @string", { "string" }));
    host_only.set_text ("[\"a{color:red}\"]");

    var spans = host_only.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:1-0:15 string" });
}

private void test_each_match_is_its_own_document_unless_combined () {
    var document = json_embedding_css ("((string_content) @injection.content (#set! injection.language \"css\"))");
    document.set_text ("[\"a{color:\", \"red}\"]");

    var spans = document.highlights (0, 0);

    assert_false ("0:14-0:17 value" in described (spans));
}

private void test_combined_matches_are_parsed_as_one_document () {
    var document = json_embedding_css ("((string_content) @injection.content (#set! injection.language \"css\") (#set! injection.combined))");
    document.set_text ("[\"a{color:\", \"red}\"]");

    var spans = document.highlights (0, 0);

    assert_true ("0:4-0:9 property" in described (spans));
    assert_true ("0:14-0:17 value" in described (spans));
}

private void test_the_children_of_the_content_node_are_left_out () {
    var document = json_embedding_css ("((string) @injection.content (#set! injection.language \"css\"))");
    document.set_text ("[\"a{color:red}\"]");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:1-0:15 string" });
}

private void test_include_children_injects_the_whole_content_node () {
    var document = json_embedding_css ("((array) @injection.content (#set! injection.language \"css\") (#set! injection.include-children))");
    document.set_text ("[a{color:red}]");

    var spans = document.highlights (0, 0);

    assert_true ("0:3-0:8 property" in described (spans));
}

private void test_editing_inside_an_injection_repaints_it () {
    var document = json_embedding_css ("((string_content) @injection.content (#set! injection.language \"css\"))");
    document.set_text ("[\"a{color:red}\"]");

    document.set_text ("[\"a{margin:red}\"]");

    assert_true ("0:4-0:10 property" in described (document.highlights (0, 0)));
    assert_true ("0:11-0:14 value" in described (document.highlights (0, 0)));
}

private void test_editing_before_an_injection_moves_it () {
    var document = json_embedding_css ("((string_content) @injection.content (#set! injection.language \"css\"))");
    document.set_text ("[\"a{color:red}\"]");

    document.set_text ("[1,\n\"a{color:red}\"]");

    assert_cmpstrv (described (document.highlights (1, 1)), { "1:0-1:3 string", "1:3-1:8 property", "1:8-1:9 string", "1:9-1:12 value", "1:12-1:14 string" });
}

private void test_removing_the_injected_text_removes_its_highlights () {
    var document = json_embedding_css ("((string_content) @injection.content (#set! injection.language \"css\"))");
    document.set_text ("[\"a{color:red}\"]");

    document.set_text ("[1]");

    assert_cmpuint (document.highlights (0, 0).length, CompareOperator.EQ, 0);
}

private void test_a_document_without_text_has_no_highlights () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number", { "number" }));

    var spans = document.highlights (0, 10);

    assert_cmpuint (spans.length, CompareOperator.EQ, 0);
}

private void test_each_captured_node_becomes_a_span () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number\n(string) @string", { "number", "string" }));
    document.set_text ("[1, \"a\"]");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:1-0:2 number", "0:4-0:7 string" });
}

private void test_a_capture_is_painted_with_the_style_key_it_resolves_to () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @constant.numeric.integer", { "constant" }));
    document.set_text ("[1]");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:1-0:2 constant" });
}

private void test_a_capture_no_style_key_covers_is_not_painted () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number\n(string) @string", { "string" }));
    document.set_text ("[1, \"a\"]");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:4-0:7 string" });
}

private void test_an_inner_capture_wins_over_the_one_around_it () {
    var document = new Syntax.SyntaxDocument (json_with ("(pair key: (string) @string)\n(pair) @type", { "string", "type" }));
    document.set_text ("{\"a\": 1}");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:1-0:4 string", "0:4-0:7 type" });
}

private void test_the_later_pattern_wins_the_same_node () {
    var document = new Syntax.SyntaxDocument (json_with ("(string) @string\n(pair key: (string) @keyword)", { "string", "keyword" }));
    document.set_text ("{\"a\": \"b\"}");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:1-0:4 keyword", "0:6-0:9 string" });
}

private void test_a_match_its_predicates_reject_is_not_painted () {
    var document = new Syntax.SyntaxDocument (json_with ("((number) @number (#eq? @number \"2\"))", { "number" }));
    document.set_text ("[1, 2]");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:4-0:5 number" });
}

private void test_only_the_requested_rows_are_returned () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number", { "number" }));
    document.set_text ("[\n1,\n2,\n3\n]");

    var spans = document.highlights (2, 3);

    assert_cmpstrv (described (spans), { "2:0-2:1 number", "3:0-3:1 number" });
}

private void test_a_span_reaching_past_the_requested_rows_is_clipped () {
    var document = new Syntax.SyntaxDocument (json_with ("(array) @type", { "type" }));
    document.set_text ("[\n1,\n2\n]");

    var spans = document.highlights (1, 1);

    assert_cmpstrv (described (spans), { "1:0-2:0 type" });
}

private void test_text_with_syntax_errors_is_still_highlighted () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number", { "number" }));
    document.set_text ("[1, , {");

    var spans = document.highlights (0, 0);

    assert_cmpstrv (described (spans), { "0:1-0:2 number" });
}

private void test_text_added_at_the_end_is_highlighted () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number", { "number" }));
    document.set_text ("[1]");

    document.set_text ("[1, 2]");

    assert_cmpstrv (described (document.highlights (0, 0)), { "0:1-0:2 number", "0:4-0:5 number" });
}

private void test_text_inserted_in_the_middle_shifts_what_follows () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number", { "number" }));
    document.set_text ("[1, 2]");

    document.set_text ("[1, true, 2]");

    assert_cmpstrv (described (document.highlights (0, 0)), { "0:1-0:2 number", "0:10-0:11 number" });
}

private void test_text_removed_from_a_repeated_run_is_tracked () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number", { "number" }));
    document.set_text ("[11, 2]");

    document.set_text ("[1, 2]");

    assert_cmpstrv (described (document.highlights (0, 0)), { "0:1-0:2 number", "0:4-0:5 number" });
}

private void test_an_inserted_line_moves_later_rows_down () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number", { "number" }));
    document.set_text ("[\n1\n]");

    document.set_text ("[\n\n\n1\n]");

    assert_cmpstrv (described (document.highlights (0, 4)), { "3:0-3:1 number" });
}

private void test_swapping_one_multibyte_character_for_another_keeps_columns_in_bytes () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number", { "number" }));
    document.set_text ("[\"é\", 1]");

    document.set_text ("[\"è\", 1]");

    assert_cmpstrv (described (document.highlights (0, 0)), { "0:7-0:8 number" });
}

private void test_replacing_the_whole_text_starts_over () {
    var document = new Syntax.SyntaxDocument (json_with ("(number) @number\n(true) @keyword", { "number", "keyword" }));
    document.set_text ("[1, 2]");

    document.set_text ("true");

    assert_cmpstrv (described (document.highlights (0, 0)), { "0:0-0:4 keyword" });
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/syntax-document/a_document_without_text_has_no_highlights", test_a_document_without_text_has_no_highlights);
    Test.add_func ("/models/syntax/syntax-document/each_captured_node_becomes_a_span", test_each_captured_node_becomes_a_span);
    Test.add_func ("/models/syntax/syntax-document/a_capture_is_painted_with_the_style_key_it_resolves_to", test_a_capture_is_painted_with_the_style_key_it_resolves_to);
    Test.add_func ("/models/syntax/syntax-document/a_capture_no_style_key_covers_is_not_painted", test_a_capture_no_style_key_covers_is_not_painted);
    Test.add_func ("/models/syntax/syntax-document/an_inner_capture_wins_over_the_one_around_it", test_an_inner_capture_wins_over_the_one_around_it);
    Test.add_func ("/models/syntax/syntax-document/the_later_pattern_wins_the_same_node", test_the_later_pattern_wins_the_same_node);
    Test.add_func ("/models/syntax/syntax-document/a_match_its_predicates_reject_is_not_painted", test_a_match_its_predicates_reject_is_not_painted);
    Test.add_func ("/models/syntax/syntax-document/only_the_requested_rows_are_returned", test_only_the_requested_rows_are_returned);
    Test.add_func ("/models/syntax/syntax-document/a_span_reaching_past_the_requested_rows_is_clipped", test_a_span_reaching_past_the_requested_rows_is_clipped);
    Test.add_func ("/models/syntax/syntax-document/text_with_syntax_errors_is_still_highlighted", test_text_with_syntax_errors_is_still_highlighted);
    Test.add_func ("/models/syntax/syntax-document/text_added_at_the_end_is_highlighted", test_text_added_at_the_end_is_highlighted);
    Test.add_func ("/models/syntax/syntax-document/text_inserted_in_the_middle_shifts_what_follows", test_text_inserted_in_the_middle_shifts_what_follows);
    Test.add_func ("/models/syntax/syntax-document/text_removed_from_a_repeated_run_is_tracked", test_text_removed_from_a_repeated_run_is_tracked);
    Test.add_func ("/models/syntax/syntax-document/an_inserted_line_moves_later_rows_down", test_an_inserted_line_moves_later_rows_down);
    Test.add_func ("/models/syntax/syntax-document/swapping_one_multibyte_character_for_another_keeps_columns_in_bytes", test_swapping_one_multibyte_character_for_another_keeps_columns_in_bytes);
    Test.add_func ("/models/syntax/syntax-document/replacing_the_whole_text_starts_over", test_replacing_the_whole_text_starts_over);
    Test.add_func ("/models/syntax/syntax-document/an_injected_language_is_painted_over_its_host", test_an_injected_language_is_painted_over_its_host);
    Test.add_func ("/models/syntax/syntax-document/the_injected_language_can_be_named_by_the_text_itself", test_the_injected_language_can_be_named_by_the_text_itself);
    Test.add_func ("/models/syntax/syntax-document/an_injection_naming_no_known_language_leaves_the_host_alone", test_an_injection_naming_no_known_language_leaves_the_host_alone);
    Test.add_func ("/models/syntax/syntax-document/a_document_without_a_language_resolver_is_not_injected", test_a_document_without_a_language_resolver_is_not_injected);
    Test.add_func ("/models/syntax/syntax-document/each_match_is_its_own_document_unless_combined", test_each_match_is_its_own_document_unless_combined);
    Test.add_func ("/models/syntax/syntax-document/combined_matches_are_parsed_as_one_document", test_combined_matches_are_parsed_as_one_document);
    Test.add_func ("/models/syntax/syntax-document/the_children_of_the_content_node_are_left_out", test_the_children_of_the_content_node_are_left_out);
    Test.add_func ("/models/syntax/syntax-document/include_children_injects_the_whole_content_node", test_include_children_injects_the_whole_content_node);
    Test.add_func ("/models/syntax/syntax-document/editing_inside_an_injection_repaints_it", test_editing_inside_an_injection_repaints_it);
    Test.add_func ("/models/syntax/syntax-document/editing_before_an_injection_moves_it", test_editing_before_an_injection_moves_it);
    Test.add_func ("/models/syntax/syntax-document/removing_the_injected_text_removes_its_highlights", test_removing_the_injected_text_removes_its_highlights);
    Test.add_func ("/models/syntax/syntax-document/a_parse_within_its_budget_finishes", test_a_parse_within_its_budget_finishes);
    Test.add_func ("/models/syntax/syntax-document/a_parse_out_of_budget_stops_unfinished", test_a_parse_out_of_budget_stops_unfinished);
    Test.add_func ("/models/syntax/syntax-document/an_unfinished_parse_keeps_answering_from_the_previous_trees", test_an_unfinished_parse_keeps_answering_from_the_previous_trees);
    Test.add_func ("/models/syntax/syntax-document/resuming_finishes_the_parse", test_resuming_finishes_the_parse);
    Test.add_func ("/models/syntax/syntax-document/new_text_replaces_an_unfinished_parse", test_new_text_replaces_an_unfinished_parse);
    Test.add_func ("/models/syntax/syntax-document/a_reference_to_a_local_is_told_apart_from_other_names", test_a_reference_to_a_local_is_told_apart_from_other_names);
    Test.add_func ("/models/syntax/syntax-document/a_reference_is_not_repainted_as_its_definition", test_a_reference_is_not_repainted_as_its_definition);
    Test.add_func ("/models/syntax/syntax-document/a_definition_is_not_visible_outside_its_scope", test_a_definition_is_not_visible_outside_its_scope);
    Test.add_func ("/models/syntax/syntax-document/an_inner_scope_sees_the_definitions_around_it", test_an_inner_scope_sees_the_definitions_around_it);
    Test.add_func ("/models/syntax/syntax-document/a_scope_that_does_not_inherit_hides_the_definitions_around_it", test_a_scope_that_does_not_inherit_hides_the_definitions_around_it);
    Test.add_func ("/models/syntax/syntax-document/a_later_capture_on_the_node_cancels_the_reference", test_a_later_capture_on_the_node_cancels_the_reference);
    Test.add_func ("/models/syntax/syntax-document/a_reference_ahead_of_its_definition_is_not_resolved", test_a_reference_ahead_of_its_definition_is_not_resolved);
    Test.add_func ("/models/syntax/syntax-document/a_pattern_for_locals_only_applies_to_resolved_references", test_a_pattern_for_locals_only_applies_to_resolved_references);
    Test.add_func ("/models/syntax/syntax-document/locals_follow_an_edit", test_locals_follow_an_edit);
    Test.add_func ("/models/syntax/syntax-document/a_line_broken_after_a_block_opener_goes_one_level_in", test_a_line_broken_after_a_block_opener_goes_one_level_in);
    Test.add_func ("/models/syntax/syntax-document/a_line_broken_after_an_ordinary_statement_stays_level", test_a_line_broken_after_an_ordinary_statement_stays_level);
    Test.add_func ("/models/syntax/syntax-document/each_position_is_answered_by_its_own_context", test_each_position_is_answered_by_its_own_context);
    Test.add_func ("/models/syntax/syntax-document/a_line_broken_inside_open_parentheses_goes_one_level_in", test_a_line_broken_inside_open_parentheses_goes_one_level_in);
    Test.add_func ("/models/syntax/syntax-document/a_line_broken_after_a_block_closer_stays_level", test_a_line_broken_after_a_block_closer_stays_level);
    Test.add_func ("/models/syntax/syntax-document/a_line_broken_in_its_leading_whitespace_is_left_alone", test_a_line_broken_in_its_leading_whitespace_is_left_alone);
    Test.add_func ("/models/syntax/syntax-document/a_brace_opens_a_level_in_javascript", test_a_brace_opens_a_level_in_javascript);
    Test.add_func ("/models/syntax/syntax-document/a_colon_opens_a_level_in_python", test_a_colon_opens_a_level_in_python);
    Test.add_func ("/models/syntax/syntax-document/a_language_without_an_indents_query_has_nothing_to_say", test_a_language_without_an_indents_query_has_nothing_to_say);
    Test.add_func ("/models/syntax/syntax-document/a_block_closer_typed_first_on_its_line_comes_one_level_out", test_a_block_closer_typed_first_on_its_line_comes_one_level_out);
    Test.add_func ("/models/syntax/syntax-document/a_closing_brace_comes_one_level_out_in_javascript", test_a_closing_brace_comes_one_level_out_in_javascript);
    Test.add_func ("/models/syntax/syntax-document/the_same_word_later_on_a_line_closes_nothing", test_the_same_word_later_on_a_line_closes_nothing);
    Test.add_func ("/models/syntax/syntax-document/a_closer_with_more_typed_after_it_is_left_alone", test_a_closer_with_more_typed_after_it_is_left_alone);
    Test.add_func ("/models/syntax/syntax-document/a_class_opens_a_level_in_vala", test_a_class_opens_a_level_in_vala);
    Test.add_func ("/models/syntax/syntax-document/a_statement_inside_a_vala_method_stays_level", test_a_statement_inside_a_vala_method_stays_level);
    Test.add_func ("/models/syntax/syntax-document/a_closing_brace_comes_one_level_out_in_vala", test_a_closing_brace_comes_one_level_out_in_vala);
    Test.add_func ("/models/syntax/syntax-document/ruby_block_openers_each_go_one_level_in", test_ruby_block_openers_each_go_one_level_in);
    Test.add_func ("/models/syntax/syntax-document/ruby_block_openers_go_in_inside_a_class_too", test_ruby_block_openers_go_in_inside_a_class_too);
    Test.add_func ("/models/syntax/syntax-document/ruby_ordinary_lines_stay_level", test_ruby_ordinary_lines_stay_level);
    Test.add_func ("/models/syntax/syntax-document/openers_in_other_languages_go_one_level_in", test_openers_in_other_languages_go_one_level_in);
    Test.add_func ("/models/syntax/syntax-document/ordinary_lines_in_other_languages_stay_level", test_ordinary_lines_in_other_languages_stay_level);
    Test.add_func ("/models/syntax/syntax-document/ruby_openers_go_in_with_code_all_around_them", test_ruby_openers_go_in_with_code_all_around_them);
    Test.add_func ("/models/syntax/syntax-document/ruby_ordinary_lines_stay_level_with_code_all_around_them", test_ruby_ordinary_lines_stay_level_with_code_all_around_them);
    Test.add_func ("/models/syntax/syntax-document/ruby_nested_openers_go_in_while_the_outer_block_is_still_open", test_ruby_nested_openers_go_in_while_the_outer_block_is_still_open);
    Test.add_func ("/models/syntax/syntax-document/an_inner_closer_comes_out_while_the_outer_block_is_still_open", test_an_inner_closer_comes_out_while_the_outer_block_is_still_open);
    Test.run ();
}
