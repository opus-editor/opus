private string new_languages_directory () {
    string directory = Path.build_filename (Environment.get_tmp_dir (), "opus-query-source-test-%u".printf (Random.next_int ()));
    DirUtils.create_with_parents (directory, 0700);
    return directory;
}

private void add_query (string languages_directory, string language, string query_name, string text) {
    string queries = Path.build_filename (languages_directory, language, "queries");
    DirUtils.create_with_parents (queries, 0700);
    try {
        FileUtils.set_contents (Path.build_filename (languages_directory, language, "language.json"), "{ \"name\": \"%s\" }".printf (language));
        FileUtils.set_contents (Path.build_filename (queries, query_name + ".scm"), text);
    } catch (FileError e) {
        error ("%s", e.message);
    }
}

private unowned TreeSitter.Language json_language () {
    var loader = new Syntax.GrammarLoader ({ Environment.get_variable ("OPUS_GRAMMARS_DIR") });
    try {
        return loader.load (new Syntax.GrammarSource ("json", "https://example.org/json", "abc", ""));
    } catch (Syntax.GrammarError e) {
        error ("%s", e.message);
    }
}

private void test_a_query_file_is_read_as_is () {
    string languages = new_languages_directory ();
    add_query (languages, "json", "highlights", "(string) @string\n");
    var source = new Syntax.QuerySource (new Syntax.LanguageRegistry ({ languages }));

    var text = source.read ("json", "highlights");

    assert_cmpstr (text, CompareOperator.EQ, "(string) @string\n");
}

private void test_a_language_without_that_query_reads_as_null () {
    string languages = new_languages_directory ();
    add_query (languages, "json", "highlights", "(string) @string\n");
    var source = new Syntax.QuerySource (new Syntax.LanguageRegistry ({ languages }));

    var text = source.read ("json", "injections");

    assert_null (text);
}

private void test_an_unknown_language_reads_as_null () {
    var source = new Syntax.QuerySource (new Syntax.LanguageRegistry ({ new_languages_directory () }));

    var text = source.read ("json", "highlights");

    assert_null (text);
}

private void test_an_inherits_line_is_replaced_by_the_inherited_queries_in_order () {
    string languages = new_languages_directory ();
    add_query (languages, "ecma", "highlights", "(ecma)");
    add_query (languages, "_jsx", "highlights", "(jsx)");
    add_query (languages, "tsx", "highlights", "(before)\n; inherits: ecma,_jsx\n(after)");
    var source = new Syntax.QuerySource (new Syntax.LanguageRegistry ({ languages }));

    var text = source.read ("tsx", "highlights");

    assert_cmpstr (text, CompareOperator.EQ, "(before)\n(ecma)\n(jsx)\n\n(after)");
}

private void test_inheritance_is_followed_through_several_languages () {
    string languages = new_languages_directory ();
    add_query (languages, "ecma", "highlights", "(ecma)");
    add_query (languages, "typescript", "highlights", "; inherits: ecma\n(typescript)");
    add_query (languages, "tsx", "highlights", "; inherits: typescript\n(tsx)");
    var source = new Syntax.QuerySource (new Syntax.LanguageRegistry ({ languages }));

    var text = source.read ("tsx", "highlights");

    assert_cmpstr (text, CompareOperator.EQ, "(ecma)\n\n(typescript)\n\n(tsx)");
}

private void test_inheriting_a_language_that_does_not_exist_adds_nothing () {
    string languages = new_languages_directory ();
    add_query (languages, "tsx", "highlights", "; inherits: ecma\n(tsx)");
    var source = new Syntax.QuerySource (new Syntax.LanguageRegistry ({ languages }));

    var text = source.read ("tsx", "highlights");

    assert_cmpstr (text, CompareOperator.EQ, "\n\n(tsx)");
}

private void test_an_inheritance_cycle_ends () {
    string languages = new_languages_directory ();
    add_query (languages, "a", "highlights", "; inherits: b\n(a)");
    add_query (languages, "b", "highlights", "; inherits: a\n(b)");
    var source = new Syntax.QuerySource (new Syntax.LanguageRegistry ({ languages }));

    var text = source.read ("a", "highlights");

    assert_cmpstr (text, CompareOperator.EQ, "\n\n(b)\n\n(a)");
}

private void test_a_valid_query_compiles () {
    unowned TreeSitter.Language language = json_language ();

    uint32 patterns = 0;
    try {
        patterns = Syntax.QuerySource.compile (language, "(string) @string\n(number) @constant.numeric").pattern_count ();
    } catch (Syntax.QueryError e) {
        error ("%s", e.message);
    }

    assert_cmpuint (patterns, CompareOperator.EQ, 2);
}

private void test_a_query_naming_an_unknown_node_reports_its_line () {
    unowned TreeSitter.Language language = json_language ();

    try {
        Syntax.QuerySource.compile (language, "(string) @string\n\n(no_such_node) @keyword");
        assert_not_reached ();
    } catch (Syntax.QueryError e) {
        assert_true (e.message.has_prefix ("line 3:"));
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/query-source/a_query_file_is_read_as_is", test_a_query_file_is_read_as_is);
    Test.add_func ("/models/syntax/query-source/a_language_without_that_query_reads_as_null", test_a_language_without_that_query_reads_as_null);
    Test.add_func ("/models/syntax/query-source/an_unknown_language_reads_as_null", test_an_unknown_language_reads_as_null);
    Test.add_func ("/models/syntax/query-source/an_inherits_line_is_replaced_by_the_inherited_queries_in_order", test_an_inherits_line_is_replaced_by_the_inherited_queries_in_order);
    Test.add_func ("/models/syntax/query-source/inheritance_is_followed_through_several_languages", test_inheritance_is_followed_through_several_languages);
    Test.add_func ("/models/syntax/query-source/inheriting_a_language_that_does_not_exist_adds_nothing", test_inheriting_a_language_that_does_not_exist_adds_nothing);
    Test.add_func ("/models/syntax/query-source/an_inheritance_cycle_ends", test_an_inheritance_cycle_ends);
    Test.add_func ("/models/syntax/query-source/a_valid_query_compiles", test_a_valid_query_compiles);
    Test.add_func ("/models/syntax/query-source/a_query_naming_an_unknown_node_reports_its_line", test_a_query_naming_an_unknown_node_reports_its_line);
    Test.run ();
}
