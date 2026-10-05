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

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/languages/a_claimed_file_gets_its_language_loaded", test_a_claimed_file_gets_its_language_loaded);
    Test.add_func ("/models/syntax/languages/a_file_is_recognized_by_its_first_line", test_a_file_is_recognized_by_its_first_line);
    Test.add_func ("/models/syntax/languages/a_language_is_loaded_once_and_shared", test_a_language_is_loaded_once_and_shared);
    Test.add_func ("/models/syntax/languages/a_file_no_package_claims_has_no_language", test_a_file_no_package_claims_has_no_language);
    Test.add_func ("/models/syntax/languages/a_language_that_cannot_be_loaded_is_no_language", test_a_language_that_cannot_be_loaded_is_no_language);
    Test.add_func ("/models/syntax/languages/new_style_keys_reach_a_language_already_loaded", test_new_style_keys_reach_a_language_already_loaded);
    Test.add_func ("/models/syntax/languages/new_style_keys_apply_to_a_language_loaded_afterwards", test_new_style_keys_apply_to_a_language_loaded_afterwards);
    Test.run ();
}
