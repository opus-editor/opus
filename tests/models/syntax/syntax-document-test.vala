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
    Test.run ();
}
