// Runs against the bundled JSON grammar — OPUS_GRAMMARS_DIR is set by
// tests/meson.build.

private unowned TreeSitter.Language json_language () {
    var loader = new Syntax.GrammarLoader ({ Environment.get_variable ("OPUS_GRAMMARS_DIR") });
    try {
        return loader.load (new Syntax.GrammarSource ("json", "https://example.org/json", "abc", ""));
    } catch (Syntax.GrammarError e) {
        error ("%s", e.message);
    }
}

private TreeSitter.Query compile (string query_text) {
    try {
        return Syntax.QuerySource.compile (json_language (), query_text);
    } catch (Syntax.QueryError e) {
        error ("%s", e.message);
    }
}

/** The text of the first capture of every match of `query_text` over `json` that its predicates accept. */
private string[] accepted (string query_text, string json) {
    var query = compile (query_text);
    Syntax.QueryPredicates predicates;
    try {
        predicates = new Syntax.QueryPredicates (query);
    } catch (Syntax.QueryError e) {
        error ("%s", e.message);
    }
    var parser = new TreeSitter.Parser ();
    parser.set_language (json_language ());
    var tree = parser.parse_string (null, json, (uint32) json.length);
    var cursor = new TreeSitter.QueryCursor ();
    cursor.exec (query, tree.root_node ());
    Syntax.NodeTextFunc node_text = (node) => json.substring (node.start_byte (), node.end_byte () - node.start_byte ());

    string[] texts = {};
    TreeSitter.QueryMatch match;
    while (cursor.next_match (out match)) {
        if (predicates.accepts (match, node_text)) {
            texts += node_text (match.captures[0].node);
        }
    }
    return texts;
}

private void test_a_pattern_without_predicates_accepts_every_match () {
    var texts = accepted ("(number) @n", "[1, 2, 10]");

    assert_cmpstrv (texts, { "1", "2", "10" });
}

private void test_eq_accepts_only_the_equal_text () {
    var texts = accepted ("((number) @n (#eq? @n \"1\"))", "[1, 2, 10]");

    assert_cmpstrv (texts, { "1" });
}

private void test_not_eq_rejects_the_equal_text () {
    var texts = accepted ("((number) @n (#not-eq? @n \"1\"))", "[1, 2, 10]");

    assert_cmpstrv (texts, { "2", "10" });
}

private void test_eq_compares_two_captures () {
    var texts = accepted ("((pair key: (string) @k value: (string) @v) (#eq? @k @v))", "{\"a\": \"a\", \"b\": \"c\"}");

    assert_cmpstrv (texts, { "\"a\"" });
}

private void test_match_accepts_text_the_regex_finds () {
    var texts = accepted ("((number) @n (#match? @n \"^1\"))", "[1, 2, 10]");

    assert_cmpstrv (texts, { "1", "10" });
}

private void test_not_match_rejects_text_the_regex_finds () {
    var texts = accepted ("((number) @n (#not-match? @n \"^1\"))", "[1, 2, 10]");

    assert_cmpstrv (texts, { "2" });
}

private void test_any_of_accepts_each_listed_text () {
    var texts = accepted ("((number) @n (#any-of? @n \"2\" \"10\"))", "[1, 2, 10]");

    assert_cmpstrv (texts, { "2", "10" });
}

private void test_not_any_of_rejects_each_listed_text () {
    var texts = accepted ("((number) @n (#not-any-of? @n \"2\" \"10\"))", "[1, 2, 10]");

    assert_cmpstrv (texts, { "1" });
}

private void test_is_not_local_rejects_every_match () {
    var texts = accepted ("((number) @n (#is-not? local))", "[1, 2]");

    assert_cmpuint (texts.length, CompareOperator.EQ, 0);
}

private void test_is_local_rejects_every_match () {
    var texts = accepted ("((number) @n (#is? local))", "[1, 2]");

    assert_cmpuint (texts.length, CompareOperator.EQ, 0);
}

private void test_a_property_other_than_local_is_an_error () {
    var query = compile ("((number) @n (#is-not? exported))");

    try {
        new Syntax.QueryPredicates (query);
        assert_not_reached ();
    } catch (Syntax.QueryError e) {
        assert_true (e.message.contains ("local"));
    }
}

private void test_every_predicate_of_a_pattern_must_hold () {
    var texts = accepted ("((number) @n (#match? @n \"^1\") (#not-eq? @n \"10\"))", "[1, 2, 10]");

    assert_cmpstrv (texts, { "1" });
}

private void test_predicates_belong_to_their_own_pattern () {
    var texts = accepted ("((number) @n (#eq? @n \"1\"))\n(true) @t", "[1, 2, true]");

    assert_cmpstrv (texts, { "1", "true" });
}

private void test_set_gives_a_pattern_a_property () {
    var query = compile ("(number) @n\n((string) @injection.content (#set! injection.language \"comment\"))");

    string? value = null;
    try {
        value = new Syntax.QueryPredicates (query).property (1, "injection.language");
    } catch (Syntax.QueryError e) {
        error ("%s", e.message);
    }

    assert_cmpstr (value, CompareOperator.EQ, "comment");
}

private void test_a_bare_set_gives_an_empty_property () {
    var query = compile ("((string) @injection.content (#set! injection.combined))");

    string? value = null;
    try {
        value = new Syntax.QueryPredicates (query).property (0, "injection.combined");
    } catch (Syntax.QueryError e) {
        error ("%s", e.message);
    }

    assert_cmpstr (value, CompareOperator.EQ, "");
}

private void test_a_property_never_set_is_null () {
    var query = compile ("(number) @n\n((string) @injection.content (#set! injection.language \"comment\"))");

    string? value = "unset";
    try {
        value = new Syntax.QueryPredicates (query).property (0, "injection.language");
    } catch (Syntax.QueryError e) {
        error ("%s", e.message);
    }

    assert_null (value);
}

private void test_a_predicate_opus_does_not_implement_is_an_error () {
    var query = compile ("((number) @n (#lua-match? @n \"^1\"))");

    try {
        new Syntax.QueryPredicates (query);
        assert_not_reached ();
    } catch (Syntax.QueryError e) {
        assert_true (e.message.contains ("lua-match?"));
    }
}

private void test_a_regex_that_does_not_compile_is_an_error () {
    var query = compile ("((number) @n (#match? @n \"(\"))");

    try {
        new Syntax.QueryPredicates (query);
        assert_not_reached ();
    } catch (Syntax.QueryError e) {
        assert_true (e.message.has_prefix ("#match?"));
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/query-predicates/a_pattern_without_predicates_accepts_every_match", test_a_pattern_without_predicates_accepts_every_match);
    Test.add_func ("/models/syntax/query-predicates/eq_accepts_only_the_equal_text", test_eq_accepts_only_the_equal_text);
    Test.add_func ("/models/syntax/query-predicates/not_eq_rejects_the_equal_text", test_not_eq_rejects_the_equal_text);
    Test.add_func ("/models/syntax/query-predicates/eq_compares_two_captures", test_eq_compares_two_captures);
    Test.add_func ("/models/syntax/query-predicates/match_accepts_text_the_regex_finds", test_match_accepts_text_the_regex_finds);
    Test.add_func ("/models/syntax/query-predicates/not_match_rejects_text_the_regex_finds", test_not_match_rejects_text_the_regex_finds);
    Test.add_func ("/models/syntax/query-predicates/any_of_accepts_each_listed_text", test_any_of_accepts_each_listed_text);
    Test.add_func ("/models/syntax/query-predicates/not_any_of_rejects_each_listed_text", test_not_any_of_rejects_each_listed_text);
    Test.add_func ("/models/syntax/query-predicates/is_not_local_rejects_every_match", test_is_not_local_rejects_every_match);
    Test.add_func ("/models/syntax/query-predicates/is_local_rejects_every_match", test_is_local_rejects_every_match);
    Test.add_func ("/models/syntax/query-predicates/a_property_other_than_local_is_an_error", test_a_property_other_than_local_is_an_error);
    Test.add_func ("/models/syntax/query-predicates/every_predicate_of_a_pattern_must_hold", test_every_predicate_of_a_pattern_must_hold);
    Test.add_func ("/models/syntax/query-predicates/predicates_belong_to_their_own_pattern", test_predicates_belong_to_their_own_pattern);
    Test.add_func ("/models/syntax/query-predicates/set_gives_a_pattern_a_property", test_set_gives_a_pattern_a_property);
    Test.add_func ("/models/syntax/query-predicates/a_bare_set_gives_an_empty_property", test_a_bare_set_gives_an_empty_property);
    Test.add_func ("/models/syntax/query-predicates/a_property_never_set_is_null", test_a_property_never_set_is_null);
    Test.add_func ("/models/syntax/query-predicates/a_predicate_opus_does_not_implement_is_an_error", test_a_predicate_opus_does_not_implement_is_an_error);
    Test.add_func ("/models/syntax/query-predicates/a_regex_that_does_not_compile_is_an_error", test_a_regex_that_does_not_compile_is_an_error);
    Test.run ();
}
