// Runs against the bundled JSON grammar — OPUS_GRAMMARS_DIR is set by
// tests/meson.build.

private string new_languages_directory () {
    string directory = Path.build_filename (Environment.get_tmp_dir (), "opus-languages-test-%u".printf (Random.next_int ()));
    DirUtils.create_with_parents (directory, 0700);
    return directory;
}

private void add_package (string languages, string name, string manifest, string highlights_query) {
    string queries = Path.build_filename (languages, name, "queries");
    DirUtils.create_with_parents (queries, 0700);
    try {
        FileUtils.set_contents (Path.build_filename (languages, name, "language.json"), manifest);
        FileUtils.set_contents (Path.build_filename (queries, "highlights.scm"), highlights_query);
    } catch (FileError e) {
        error ("%s", e.message);
    }
}

private Syntax.Languages languages_over (string directory) {
    return new Syntax.Languages ({ directory }, { Environment.get_variable ("OPUS_GRAMMARS_DIR") }, { "string" });
}

private void test_a_claimed_file_gets_its_language_loaded () {
    string directory = new_languages_directory ();
    add_package (directory, "json", """{ "name": "json", "file-types": ["json"], "grammar": { "repository": "r", "rev": "abc" } }""", "(string) @string");
    var languages = languages_over (directory);

    var language = languages.detect ("/project/package.json");

    assert_cmpstr (language.package.name, CompareOperator.EQ, "json");
}

private void test_a_file_is_recognized_by_its_first_line () {
    string directory = new_languages_directory ();
    add_package (directory, "json", """{ "name": "json", "shebangs": ["jq"], "grammar": { "repository": "r", "rev": "abc" } }""", "(string) @string");
    var languages = languages_over (directory);

    var language = languages.detect ("/project/bin/filter", "#!/usr/bin/jq -f");

    assert_cmpstr (language.package.name, CompareOperator.EQ, "json");
}

private void test_a_language_is_loaded_once_and_shared () {
    string directory = new_languages_directory ();
    add_package (directory, "json", """{ "name": "json", "file-types": ["json"], "grammar": { "repository": "r", "rev": "abc" } }""", "(string) @string");
    var languages = languages_over (directory);

    var first = languages.detect ("/project/a.json");
    var second = languages.detect ("/project/b.json");

    assert_true (first == second);
}

private void test_a_file_no_package_claims_has_no_language () {
    string directory = new_languages_directory ();
    add_package (directory, "json", """{ "name": "json", "file-types": ["json"], "grammar": { "repository": "r", "rev": "abc" } }""", "(string) @string");
    var languages = languages_over (directory);

    var language = languages.detect ("/project/notes.txt");

    assert_null (language);
}

private void test_a_language_that_cannot_be_loaded_is_no_language () {
    string directory = new_languages_directory ();
    add_package (directory, "json", """{ "name": "json", "file-types": ["json"], "grammar": { "repository": "r", "rev": "abc" } }""", "(no_such_node) @string");
    var languages = languages_over (directory);

    var first = languages.detect ("/project/a.json");
    var second = languages.detect ("/project/b.json");

    assert_null (first);
    assert_null (second);
}

private void test_new_style_keys_reach_a_language_already_loaded () {
    string directory = new_languages_directory ();
    add_package (directory, "json", """{ "name": "json", "file-types": ["json"], "grammar": { "repository": "r", "rev": "abc" } }""", "(string) @string\n(number) @constant.numeric");
    var languages = languages_over (directory);
    var document = new Syntax.SyntaxDocument (languages.detect ("/project/a.json"));
    document.set_text ("[\"a\", 1]");

    languages.set_style_keys ({ "constant" });

    var spans = document.highlights (0, 0);
    assert_cmpuint (spans.length, CompareOperator.EQ, 1);
    assert_cmpstr (spans[0].style, CompareOperator.EQ, "constant");
}

private void test_new_style_keys_apply_to_a_language_loaded_afterwards () {
    string directory = new_languages_directory ();
    add_package (directory, "json", """{ "name": "json", "file-types": ["json"], "grammar": { "repository": "r", "rev": "abc" } }""", "(string) @string\n(number) @constant.numeric");
    var languages = languages_over (directory);

    languages.set_style_keys ({ "constant" });

    var document = new Syntax.SyntaxDocument (languages.detect ("/project/a.json"));
    document.set_text ("[\"a\", 1]");
    var spans = document.highlights (0, 0);
    assert_cmpuint (spans.length, CompareOperator.EQ, 1);
    assert_cmpstr (spans[0].style, CompareOperator.EQ, "constant");
}

private void test_reload_reads_an_edited_package_again () {
    string directory = new_languages_directory ();
    add_package (directory, "json", """{ "name": "json", "file-types": ["json"], "grammar": { "repository": "r", "rev": "abc" } }""", "(number) @string");
    var languages = languages_over (directory);
    languages.detect ("/project/a.json");
    add_package (directory, "json", """{ "name": "json", "file-types": ["json"], "grammar": { "repository": "r", "rev": "abc" } }""", "(string) @string");

    languages.reload ();

    var document = new Syntax.SyntaxDocument (languages.detect ("/project/a.json"));
    document.set_text ("[\"a\", 1]");
    var spans = document.highlights (0, 0);
    assert_cmpuint (spans.length, CompareOperator.EQ, 1);
    assert_cmpuint (spans[0].start_column, CompareOperator.EQ, 1);
}

private void test_reload_finds_a_package_added_since () {
    string directory = new_languages_directory ();
    var languages = languages_over (directory);
    add_package (directory, "json", """{ "name": "json", "file-types": ["json"], "grammar": { "repository": "r", "rev": "abc" } }""", "(string) @string");

    languages.reload ();

    assert_nonnull (languages.detect ("/project/a.json"));
}

private void test_reload_announces_the_change () {
    var languages = languages_over (new_languages_directory ());
    int announced = 0;
    languages.changed.connect (() => announced++);

    languages.reload ();

    assert_cmpint (announced, CompareOperator.EQ, 1);
}

private void test_a_watched_package_reloads_when_its_query_is_edited () {
    string directory = new_languages_directory ();
    add_package (directory, "json", """{ "name": "json", "file-types": ["json"], "grammar": { "repository": "r", "rev": "abc" } }""", "(number) @string");
    var languages = languages_over (directory);
    languages.watch (directory);
    var loop = new MainLoop ();
    bool announced = false;
    languages.changed.connect (() => {
        announced = true;
        loop.quit ();
    });
    Timeout.add_seconds (5, () => {
        loop.quit ();
        return Source.REMOVE;
    });

    add_package (directory, "json", """{ "name": "json", "file-types": ["json"], "grammar": { "repository": "r", "rev": "abc" } }""", "(string) @string");
    loop.run ();

    assert_true (announced);
}

private void test_a_grammar_never_compiled_is_built_on_first_use () {
    string repository = Environment.get_variable ("OPUS_TEST_GRAMMAR_REPOSITORY");
    if (!FileUtils.test (Path.build_filename (repository, ".git"), FileTest.EXISTS) || !HostCommand.has_program ("git") || !HostCommand.has_program ("cc")) {
        Test.skip ("needs git, cc and a git checkout of the JSON grammar");
        return;
    }
    string rev;
    try {
        rev = Syntax.LanguagePackage.load (Path.build_filename (Environment.get_variable ("OPUS_LANGUAGES_DIR"), "json")).grammar.rev;
    } catch (Syntax.PackageError e) {
        error ("%s", e.message);
    }
    string directory = new_languages_directory ();
    string built = new_languages_directory ();
    add_package (directory, "json", "{ \"name\": \"json\", \"file-types\": [\"json\"], \"grammar\": { \"repository\": \"%s\", \"rev\": \"%s\" } }".printf (repository, rev), "(string) @string");
    var languages = new Syntax.Languages ({ directory }, { built }, { "string" }, new Syntax.GrammarBuilder (new_languages_directory (), built));
    var loop = new MainLoop ();
    languages.changed.connect (() => loop.quit ());
    Timeout.add_seconds (60, () => {
        loop.quit ();
        return Source.REMOVE;
    });

    var before_the_build = languages.detect ("/project/a.json");
    loop.run ();

    assert_null (before_the_build);
    assert_nonnull (languages.detect ("/project/a.json"));
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/languages/a_claimed_file_gets_its_language_loaded", test_a_claimed_file_gets_its_language_loaded);
    Test.add_func ("/models/syntax/languages/a_file_is_recognized_by_its_first_line", test_a_file_is_recognized_by_its_first_line);
    Test.add_func ("/models/syntax/languages/a_language_is_loaded_once_and_shared", test_a_language_is_loaded_once_and_shared);
    Test.add_func ("/models/syntax/languages/a_file_no_package_claims_has_no_language", test_a_file_no_package_claims_has_no_language);
    Test.add_func ("/models/syntax/languages/a_language_that_cannot_be_loaded_is_no_language", test_a_language_that_cannot_be_loaded_is_no_language);
    Test.add_func ("/models/syntax/languages/new_style_keys_reach_a_language_already_loaded", test_new_style_keys_reach_a_language_already_loaded);
    Test.add_func ("/models/syntax/languages/new_style_keys_apply_to_a_language_loaded_afterwards", test_new_style_keys_apply_to_a_language_loaded_afterwards);
    Test.add_func ("/models/syntax/languages/reload_reads_an_edited_package_again", test_reload_reads_an_edited_package_again);
    Test.add_func ("/models/syntax/languages/reload_finds_a_package_added_since", test_reload_finds_a_package_added_since);
    Test.add_func ("/models/syntax/languages/reload_announces_the_change", test_reload_announces_the_change);
    Test.add_func ("/models/syntax/languages/a_watched_package_reloads_when_its_query_is_edited", test_a_watched_package_reloads_when_its_query_is_edited);
    Test.add_func ("/models/syntax/languages/a_grammar_never_compiled_is_built_on_first_use", test_a_grammar_never_compiled_is_built_on_first_use);
    Test.run ();
}
