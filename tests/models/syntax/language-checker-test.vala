// Runs against the bundled JSON grammar — OPUS_GRAMMARS_DIR is set by
// tests/meson.build.

private string new_directory () {
    string directory = Path.build_filename (Environment.get_tmp_dir (), "opus-language-checker-test-%u".printf (Random.next_int ()));
    DirUtils.create_with_parents (directory, 0700);
    return directory;
}

private void write_file (string directory, string name, string contents) {
    DirUtils.create_with_parents (directory, 0700);
    try {
        FileUtils.set_contents (Path.build_filename (directory, name), contents);
    } catch (FileError e) {
        error ("%s", e.message);
    }
}

private const string JSON_MANIFEST = """{ "name": "json", "grammar": { "repository": "r", "rev": "abc" } }""";

/** A package folder named `json` holding `manifest` and, when given, the two queries. */
private string package_with (string manifest, string? highlights = null, string? injections = null) {
    string package = Path.build_filename (new_directory (), "json");
    write_file (package, "language.json", manifest);
    if (highlights != null) {
        write_file (Path.build_filename (package, "queries"), "highlights.scm", highlights);
    }
    if (injections != null) {
        write_file (Path.build_filename (package, "queries"), "injections.scm", injections);
    }
    return package;
}

private string[] check (string package, string[] language_directories = {}) {
    var checker = new Syntax.LanguageChecker (language_directories, new Syntax.GrammarLoader ({ Environment.get_variable ("OPUS_GRAMMARS_DIR") }));
    return checker.check (package);
}

private void test_a_sound_package_has_no_problems () {
    string package = package_with (JSON_MANIFEST, "(string) @string", "((comment) @injection.content (#set! injection.language \"comment\"))");

    var problems = check (package);

    assert_cmpuint (problems.length, CompareOperator.EQ, 0);
}

private void test_an_invalid_manifest_is_reported_by_file () {
    string package = package_with ("""{ "file-types": ["json"] }""");

    var problems = check (package);

    assert_cmpuint (problems.length, CompareOperator.EQ, 1);
    assert_true (problems[0].has_prefix ("language.json:"));
}

private void test_a_folder_without_a_manifest_is_reported () {
    string package = new_directory ();

    var problems = check (package);

    assert_cmpuint (problems.length, CompareOperator.EQ, 1);
    assert_true (problems[0].contains ("language.json"));
}

private void test_a_grammar_that_cannot_be_loaded_is_reported () {
    string package = package_with ("""{ "name": "klingon", "grammar": { "repository": "r", "rev": "abc" } }""", "(string) @string");

    var problems = check (package);

    assert_cmpuint (problems.length, CompareOperator.EQ, 1);
    assert_true (problems[0].has_prefix ("grammar:"));
}

private void test_a_query_that_does_not_compile_is_reported_by_file_and_line () {
    string package = package_with (JSON_MANIFEST, "(string) @string\n(no_such_node) @keyword");

    var problems = check (package);

    assert_cmpstrv (problems, { "queries/highlights.scm: line 2: the grammar has no such node type" });
}

private void test_a_predicate_opus_does_not_implement_is_reported () {
    string package = package_with (JSON_MANIFEST, "((string) @string (#lua-match? @string \"a\"))");

    var problems = check (package);

    assert_cmpuint (problems.length, CompareOperator.EQ, 1);
    assert_true (problems[0].has_prefix ("queries/highlights.scm:"));
    assert_true (problems[0].contains ("lua-match?"));
}

private void test_every_broken_query_is_reported_at_once () {
    string package = package_with (JSON_MANIFEST, "(no_such_node) @keyword", "(no_such_node) @injection.content");

    var problems = check (package);

    assert_cmpuint (problems.length, CompareOperator.EQ, 2);
    assert_true (problems[0].has_prefix ("queries/highlights.scm:"));
    assert_true (problems[1].has_prefix ("queries/injections.scm:"));
}

private void test_inherited_queries_are_checked_too () {
    string installed = new_directory ();
    write_file (Path.build_filename (installed, "base", "queries"), "highlights.scm", "(no_such_node) @keyword");
    write_file (Path.build_filename (installed, "base"), "language.json", """{ "name": "base" }""");
    string package = package_with (JSON_MANIFEST, "; inherits: base\n(string) @string");

    var problems = check (package, { installed });

    assert_cmpuint (problems.length, CompareOperator.EQ, 1);
    assert_true (problems[0].has_prefix ("queries/highlights.scm:"));
}

private void test_a_package_without_a_grammar_has_nothing_to_check () {
    string package = package_with ("""{ "name": "json" }""", "(anything) @goes");

    var problems = check (package);

    assert_cmpuint (problems.length, CompareOperator.EQ, 0);
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/language-checker/a_sound_package_has_no_problems", test_a_sound_package_has_no_problems);
    Test.add_func ("/models/syntax/language-checker/an_invalid_manifest_is_reported_by_file", test_an_invalid_manifest_is_reported_by_file);
    Test.add_func ("/models/syntax/language-checker/a_folder_without_a_manifest_is_reported", test_a_folder_without_a_manifest_is_reported);
    Test.add_func ("/models/syntax/language-checker/a_grammar_that_cannot_be_loaded_is_reported", test_a_grammar_that_cannot_be_loaded_is_reported);
    Test.add_func ("/models/syntax/language-checker/a_query_that_does_not_compile_is_reported_by_file_and_line", test_a_query_that_does_not_compile_is_reported_by_file_and_line);
    Test.add_func ("/models/syntax/language-checker/a_predicate_opus_does_not_implement_is_reported", test_a_predicate_opus_does_not_implement_is_reported);
    Test.add_func ("/models/syntax/language-checker/every_broken_query_is_reported_at_once", test_every_broken_query_is_reported_at_once);
    Test.add_func ("/models/syntax/language-checker/inherited_queries_are_checked_too", test_inherited_queries_are_checked_too);
    Test.add_func ("/models/syntax/language-checker/a_package_without_a_grammar_has_nothing_to_check", test_a_package_without_a_grammar_has_nothing_to_check);
    Test.run ();
}
