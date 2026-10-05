// Runs against the bundled JSON grammar — OPUS_GRAMMARS_DIR is set by
// tests/meson.build.

private string new_languages_directory () {
    string directory = Path.build_filename (Environment.get_tmp_dir (), "opus-loaded-language-test-%u".printf (Random.next_int ()));
    DirUtils.create_with_parents (directory, 0700);
    return directory;
}

/** Writes a package named `name`; a null `highlights_query` leaves it without one. */
private void add_package (string languages, string name, string manifest, string? highlights_query) {
    string queries = Path.build_filename (languages, name, "queries");
    DirUtils.create_with_parents (queries, 0700);
    try {
        FileUtils.set_contents (Path.build_filename (languages, name, "language.json"), manifest);
        if (highlights_query != null) {
            FileUtils.set_contents (Path.build_filename (queries, "highlights.scm"), highlights_query);
        }
    } catch (FileError e) {
        error ("%s", e.message);
    }
}

private Syntax.LoadedLanguage load (string languages, string name) throws Syntax.LanguageError {
    var registry = new Syntax.LanguageRegistry ({ languages });
    return Syntax.LoadedLanguage.load (
        registry.by_name (name),
        new Syntax.GrammarLoader ({ Environment.get_variable ("OPUS_GRAMMARS_DIR") }),
        new Syntax.QuerySource (registry),
        new Syntax.CaptureStyles ({ "string" })
    );
}

private void assert_unusable (string languages, string name, string message_part) {
    try {
        load (languages, name);
        assert_not_reached ();
    } catch (Syntax.LanguageError e) {
        assert_true (e.message.contains (message_part));
    }
}

private void test_a_package_with_a_grammar_and_highlights_loads () {
    string languages = new_languages_directory ();
    add_package (languages, "json", """{ "name": "json", "grammar": { "repository": "r", "rev": "abc" } }""", "(string) @string");

    Syntax.LoadedLanguage? language = null;
    try {
        language = load (languages, "json");
    } catch (Syntax.LanguageError e) {
        error ("%s", e.message);
    }

    assert_cmpstr (language.package.name, CompareOperator.EQ, "json");
}

private void test_a_package_borrowing_another_grammar_loads () {
    string languages = new_languages_directory ();
    add_package (languages, "jsonc", """{ "name": "jsonc", "grammar": { "name": "json", "repository": "r", "rev": "abc" } }""", "(string) @string");

    Syntax.LoadedLanguage? language = null;
    try {
        language = load (languages, "jsonc");
    } catch (Syntax.LanguageError e) {
        error ("%s", e.message);
    }

    assert_cmpstr (language.package.name, CompareOperator.EQ, "jsonc");
}

private void test_a_package_without_a_grammar_is_unusable () {
    string languages = new_languages_directory ();
    add_package (languages, "ecma", """{ "name": "ecma" }""", "(string) @string");

    assert_unusable (languages, "ecma", "no grammar");
}

private void test_a_package_without_highlights_is_unusable () {
    string languages = new_languages_directory ();
    add_package (languages, "json", """{ "name": "json", "grammar": { "repository": "r", "rev": "abc" } }""", null);

    assert_unusable (languages, "json", "no highlights query");
}

private void test_a_grammar_that_was_never_compiled_is_unusable () {
    string languages = new_languages_directory ();
    add_package (languages, "klingon", """{ "name": "klingon", "grammar": { "repository": "r", "rev": "abc" } }""", "(string) @string");

    assert_unusable (languages, "klingon", "klingon");
}

private void test_a_highlights_query_that_does_not_compile_is_unusable () {
    string languages = new_languages_directory ();
    add_package (languages, "json", """{ "name": "json", "grammar": { "repository": "r", "rev": "abc" } }""", "(no_such_node) @string");

    assert_unusable (languages, "json", "highlights query: line 1");
}

private void test_a_predicate_opus_does_not_implement_is_unusable () {
    string languages = new_languages_directory ();
    add_package (languages, "json", """{ "name": "json", "grammar": { "repository": "r", "rev": "abc" } }""", "((string) @string (#lua-match? @string \"a\"))");

    assert_unusable (languages, "json", "lua-match?");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/loaded-language/a_package_with_a_grammar_and_highlights_loads", test_a_package_with_a_grammar_and_highlights_loads);
    Test.add_func ("/models/syntax/loaded-language/a_package_borrowing_another_grammar_loads", test_a_package_borrowing_another_grammar_loads);
    Test.add_func ("/models/syntax/loaded-language/a_package_without_a_grammar_is_unusable", test_a_package_without_a_grammar_is_unusable);
    Test.add_func ("/models/syntax/loaded-language/a_package_without_highlights_is_unusable", test_a_package_without_highlights_is_unusable);
    Test.add_func ("/models/syntax/loaded-language/a_grammar_that_was_never_compiled_is_unusable", test_a_grammar_that_was_never_compiled_is_unusable);
    Test.add_func ("/models/syntax/loaded-language/a_highlights_query_that_does_not_compile_is_unusable", test_a_highlights_query_that_does_not_compile_is_unusable);
    Test.add_func ("/models/syntax/loaded-language/a_predicate_opus_does_not_implement_is_unusable", test_a_predicate_opus_does_not_implement_is_unusable);
    Test.run ();
}
