private Syntax.LanguagePackage parse (string manifest) {
    try {
        return Syntax.LanguagePackage.parse ("/packages/example", manifest);
    } catch (Syntax.PackageError e) {
        error ("the manifest should have parsed: %s", e.message);
    }
}

private void assert_invalid (string manifest) {
    try {
        Syntax.LanguagePackage.parse ("/packages/example", manifest);
        assert_not_reached ();
    } catch (Syntax.PackageError e) {
        assert_true (e is Syntax.PackageError.INVALID);
    }
}

private void test_a_minimal_manifest_only_needs_a_name () {
    var package = parse ("""{ "name": "ruby" }""");

    assert_cmpstr (package.name, CompareOperator.EQ, "ruby");
    assert_cmpstr (package.directory, CompareOperator.EQ, "/packages/example");
}

private void test_a_title_is_how_the_language_is_written_for_a_person () {
    var package = parse ("""{ "name": "cpp", "title": "C++" }""");

    assert_cmpstr (package.title, CompareOperator.EQ, "C++");
}

private void test_a_package_without_a_title_goes_by_its_name () {
    var package = parse ("""{ "name": "ruby" }""");

    assert_cmpstr (package.title, CompareOperator.EQ, "ruby");
}

private void test_a_package_with_a_grammar_and_a_file_type_opens_files () {
    var package = parse ("""{ "name": "ruby", "file-types": ["rb"], "grammar": { "repository": "r", "rev": "abc" } }""");

    assert_true (package.opens_files);
}

private void test_a_package_claimed_only_by_a_shebang_opens_files () {
    var package = parse ("""{ "name": "ruby", "shebangs": ["ruby"], "grammar": { "repository": "r", "rev": "abc" } }""");

    assert_true (package.opens_files);
}

private void test_a_package_claiming_no_file_does_not_open_files () {
    var package = parse ("""{ "name": "comment", "grammar": { "repository": "r", "rev": "abc" } }""");

    assert_false (package.opens_files);
}

private void test_a_package_without_a_grammar_does_not_open_files () {
    var package = parse ("""{ "name": "ecma", "file-types": ["es"] }""");

    assert_false (package.opens_files);
}

private void test_string_file_types_are_extensions () {
    var package = parse ("""{ "name": "ruby", "file-types": ["rb", { "glob": "Gemfile" }, "rake"] }""");

    assert_cmpstrv (package.extensions, { "rb", "rake" });
}

private void test_glob_file_types_are_globs () {
    var package = parse ("""{ "name": "ruby", "file-types": ["rb", { "glob": "Gemfile" }] }""");

    assert_cmpstrv (package.globs, { "Gemfile" });
}

private void test_shebangs_are_read () {
    var package = parse ("""{ "name": "ruby", "shebangs": ["ruby", "jruby"] }""");

    assert_cmpstrv (package.shebangs, { "ruby", "jruby" });
}

private void test_injection_regex_is_compiled () {
    var package = parse ("""{ "name": "ruby", "injection-regex": "ruby|rb" }""");

    assert_true (package.injection_regex.match ("rb"));
}

private void test_a_grammar_is_named_after_its_language_by_default () {
    var package = parse ("""{ "name": "ruby", "grammar": { "repository": "https://example.org/ruby", "rev": "abc" } }""");

    assert_cmpstr (package.grammar.name, CompareOperator.EQ, "ruby");
    assert_cmpstr (package.grammar.repository, CompareOperator.EQ, "https://example.org/ruby");
    assert_cmpstr (package.grammar.rev, CompareOperator.EQ, "abc");
    assert_cmpstr (package.grammar.path, CompareOperator.EQ, "");
}

private void test_a_grammar_can_carry_its_own_name_and_path () {
    var package = parse ("""{ "name": "markdown.inline", "grammar": { "name": "markdown_inline", "repository": "r", "rev": "abc", "path": "tree-sitter-markdown-inline" } }""");

    assert_cmpstr (package.grammar.name, CompareOperator.EQ, "markdown_inline");
    assert_cmpstr (package.grammar.path, CompareOperator.EQ, "tree-sitter-markdown-inline");
}

private void test_a_grammar_symbol_swaps_what_c_cannot_spell () {
    var package = parse ("""{ "name": "c-sharp.script", "grammar": { "repository": "r", "rev": "abc" } }""");

    assert_cmpstr (package.grammar.symbol, CompareOperator.EQ, "tree_sitter_c_sharp_script");
}

private void test_a_package_without_a_grammar_has_none () {
    var package = parse ("""{ "name": "ecma" }""");

    assert_null (package.grammar);
}

private void test_a_missing_name_is_invalid () {
    assert_invalid ("""{ "file-types": ["rb"] }""");
}

private void test_malformed_json_is_invalid () {
    assert_invalid ("""{ "name": """);
}

private void test_a_manifest_that_is_not_an_object_is_invalid () {
    assert_invalid ("""["ruby"]""");
}

private void test_a_file_type_of_the_wrong_shape_is_invalid () {
    assert_invalid ("""{ "name": "ruby", "file-types": [42] }""");
}

private void test_an_injection_regex_that_does_not_compile_is_invalid () {
    assert_invalid ("""{ "name": "ruby", "injection-regex": "(" }""");
}

private void test_a_grammar_without_a_commit_is_invalid () {
    assert_invalid ("""{ "name": "ruby", "grammar": { "repository": "r" } }""");
}

private void test_loading_a_directory_without_a_manifest_is_unreadable () {
    string directory = Path.build_filename (Environment.get_tmp_dir (), "opus-language-package-test-%u".printf (Random.next_int ()));

    try {
        Syntax.LanguagePackage.load (directory);
        assert_not_reached ();
    } catch (Syntax.PackageError e) {
        assert_true (e is Syntax.PackageError.UNREADABLE);
    }
}

private void test_query_path_finds_an_existing_query_file () {
    string directory = Path.build_filename (Environment.get_tmp_dir (), "opus-language-package-test-%u".printf (Random.next_int ()));
    string queries = Path.build_filename (directory, "queries");
    string highlights = Path.build_filename (queries, "highlights.scm");
    DirUtils.create_with_parents (queries, 0700);
    try {
        FileUtils.set_contents (Path.build_filename (directory, "language.json"), """{ "name": "ruby" }""");
        FileUtils.set_contents (highlights, "(comment) @comment");
    } catch (FileError e) {
        error ("%s", e.message);
    }
    Syntax.LanguagePackage package;
    try {
        package = Syntax.LanguagePackage.load (directory);
    } catch (Syntax.PackageError e) {
        error ("%s", e.message);
    }

    assert_cmpstr (package.query_path ("highlights"), CompareOperator.EQ, highlights);
    assert_null (package.query_path ("injections"));
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/language-package/a_minimal_manifest_only_needs_a_name", test_a_minimal_manifest_only_needs_a_name);
    Test.add_func ("/models/syntax/language-package/string_file_types_are_extensions", test_string_file_types_are_extensions);
    Test.add_func ("/models/syntax/language-package/glob_file_types_are_globs", test_glob_file_types_are_globs);
    Test.add_func ("/models/syntax/language-package/shebangs_are_read", test_shebangs_are_read);
    Test.add_func ("/models/syntax/language-package/injection_regex_is_compiled", test_injection_regex_is_compiled);
    Test.add_func ("/models/syntax/language-package/a_grammar_is_named_after_its_language_by_default", test_a_grammar_is_named_after_its_language_by_default);
    Test.add_func ("/models/syntax/language-package/a_grammar_can_carry_its_own_name_and_path", test_a_grammar_can_carry_its_own_name_and_path);
    Test.add_func ("/models/syntax/language-package/a_grammar_symbol_swaps_what_c_cannot_spell", test_a_grammar_symbol_swaps_what_c_cannot_spell);
    Test.add_func ("/models/syntax/language-package/a_package_without_a_grammar_has_none", test_a_package_without_a_grammar_has_none);
    Test.add_func ("/models/syntax/language-package/a_missing_name_is_invalid", test_a_missing_name_is_invalid);
    Test.add_func ("/models/syntax/language-package/malformed_json_is_invalid", test_malformed_json_is_invalid);
    Test.add_func ("/models/syntax/language-package/a_manifest_that_is_not_an_object_is_invalid", test_a_manifest_that_is_not_an_object_is_invalid);
    Test.add_func ("/models/syntax/language-package/a_file_type_of_the_wrong_shape_is_invalid", test_a_file_type_of_the_wrong_shape_is_invalid);
    Test.add_func ("/models/syntax/language-package/an_injection_regex_that_does_not_compile_is_invalid", test_an_injection_regex_that_does_not_compile_is_invalid);
    Test.add_func ("/models/syntax/language-package/a_grammar_without_a_commit_is_invalid", test_a_grammar_without_a_commit_is_invalid);
    Test.add_func ("/models/syntax/language-package/loading_a_directory_without_a_manifest_is_unreadable", test_loading_a_directory_without_a_manifest_is_unreadable);
    Test.add_func ("/models/syntax/language-package/query_path_finds_an_existing_query_file", test_query_path_finds_an_existing_query_file);
    Test.add_func ("/models/syntax/language-package/a_title_is_how_the_language_is_written_for_a_person", test_a_title_is_how_the_language_is_written_for_a_person);
    Test.add_func ("/models/syntax/language-package/a_package_without_a_title_goes_by_its_name", test_a_package_without_a_title_goes_by_its_name);
    Test.add_func ("/models/syntax/language-package/a_package_with_a_grammar_and_a_file_type_opens_files", test_a_package_with_a_grammar_and_a_file_type_opens_files);
    Test.add_func ("/models/syntax/language-package/a_package_claimed_only_by_a_shebang_opens_files", test_a_package_claimed_only_by_a_shebang_opens_files);
    Test.add_func ("/models/syntax/language-package/a_package_claiming_no_file_does_not_open_files", test_a_package_claiming_no_file_does_not_open_files);
    Test.add_func ("/models/syntax/language-package/a_package_without_a_grammar_does_not_open_files", test_a_package_without_a_grammar_does_not_open_files);
    Test.run ();
}
