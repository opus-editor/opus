private string new_languages_directory () {
    string directory = Path.build_filename (Environment.get_tmp_dir (), "opus-language-registry-test-%u".printf (Random.next_int ()));
    DirUtils.create_with_parents (directory, 0700);
    return directory;
}

private void add_package (string languages_directory, string folder, string manifest) {
    string directory = Path.build_filename (languages_directory, folder);
    DirUtils.create_with_parents (directory, 0700);
    try {
        FileUtils.set_contents (Path.build_filename (directory, "language.json"), manifest);
    } catch (FileError e) {
        error ("%s", e.message);
    }
}

private void test_a_package_is_found_by_name () {
    string languages = new_languages_directory ();
    add_package (languages, "ruby", """{ "name": "ruby" }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.by_name ("ruby");

    assert_cmpstr (package.name, CompareOperator.EQ, "ruby");
}

private void test_an_unknown_name_finds_nothing () {
    var registry = new Syntax.LanguageRegistry ({ new_languages_directory () });

    var package = registry.by_name ("ruby");

    assert_null (package);
}

private void test_a_file_is_detected_by_its_extension () {
    string languages = new_languages_directory ();
    add_package (languages, "ruby", """{ "name": "ruby", "file-types": ["rb"] }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.detect ("/project/app/models/user.rb");

    assert_cmpstr (package.name, CompareOperator.EQ, "ruby");
}

private void test_the_longest_extension_wins () {
    string languages = new_languages_directory ();
    add_package (languages, "json", """{ "name": "json", "file-types": ["js.map"] }""");
    add_package (languages, "map", """{ "name": "map", "file-types": ["map"] }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.detect ("/project/dist/app.js.map");

    assert_cmpstr (package.name, CompareOperator.EQ, "json");
}

private void test_a_hidden_file_name_is_not_an_extension () {
    string languages = new_languages_directory ();
    add_package (languages, "json", """{ "name": "json", "file-types": ["json"] }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.detect ("/project/.json");

    assert_null (package);
}

private void test_a_file_is_detected_by_a_file_name_glob () {
    string languages = new_languages_directory ();
    add_package (languages, "ruby", """{ "name": "ruby", "file-types": [{ "glob": "Gemfile" }] }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.detect ("/project/Gemfile");

    assert_cmpstr (package.name, CompareOperator.EQ, "ruby");
}

private void test_a_glob_naming_a_directory_matches_under_any_parent () {
    string languages = new_languages_directory ();
    add_package (languages, "toml", """{ "name": "toml", "file-types": [{ "glob": "containers.conf.d/*.conf" }] }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.detect ("/etc/containers/containers.conf.d/custom.conf");

    assert_cmpstr (package.name, CompareOperator.EQ, "toml");
}

private void test_a_glob_beats_an_extension () {
    string languages = new_languages_directory ();
    add_package (languages, "json", """{ "name": "json", "file-types": ["json"] }""");
    add_package (languages, "jsonc", """{ "name": "jsonc", "file-types": [{ "glob": "tsconfig.json" }] }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.detect ("/project/tsconfig.json");

    assert_cmpstr (package.name, CompareOperator.EQ, "jsonc");
}

private void test_the_longest_matching_glob_wins () {
    string languages = new_languages_directory ();
    add_package (languages, "a-short", """{ "name": "a-short", "file-types": [{ "glob": "*.lock" }] }""");
    add_package (languages, "b-long", """{ "name": "b-long", "file-types": [{ "glob": "Cargo.lock" }] }""");
    add_package (languages, "c-short", """{ "name": "c-short", "file-types": [{ "glob": "C*.lock" }] }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.detect ("/project/Cargo.lock");

    assert_cmpstr (package.name, CompareOperator.EQ, "b-long");
}

private void test_a_file_is_detected_by_its_shebang () {
    string languages = new_languages_directory ();
    add_package (languages, "python", """{ "name": "python", "shebangs": ["python"] }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.detect ("/project/bin/serve", "#!/usr/bin/env -S python3.12 -u");

    assert_cmpstr (package.name, CompareOperator.EQ, "python");
}

private void test_the_path_beats_the_shebang () {
    string languages = new_languages_directory ();
    add_package (languages, "python", """{ "name": "python", "shebangs": ["python"] }""");
    add_package (languages, "ruby", """{ "name": "ruby", "file-types": ["rb"] }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.detect ("/project/bin/serve.rb", "#!/usr/bin/python");

    assert_cmpstr (package.name, CompareOperator.EQ, "ruby");
}

private void test_a_file_nothing_claims_is_not_detected () {
    string languages = new_languages_directory ();
    add_package (languages, "ruby", """{ "name": "ruby", "file-types": ["rb"] }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.detect ("/project/notes.txt", "plain text");

    assert_null (package);
}

private void test_a_later_directory_replaces_a_same_named_package () {
    string builtin = new_languages_directory ();
    string user = new_languages_directory ();
    add_package (builtin, "ruby", """{ "name": "ruby", "file-types": ["rb"] }""");
    add_package (user, "ruby", """{ "name": "ruby", "file-types": ["ruby"] }""");
    var registry = new Syntax.LanguageRegistry ({ builtin, user });

    var package = registry.by_name ("ruby");

    assert_true (package.directory.has_prefix (user));
    assert_null (registry.detect ("/project/user.rb"));
}

private void test_a_later_directory_wins_a_shared_extension () {
    string builtin = new_languages_directory ();
    string user = new_languages_directory ();
    add_package (builtin, "zzz-builtin", """{ "name": "zzz-builtin", "file-types": ["x"] }""");
    add_package (user, "aaa-user", """{ "name": "aaa-user", "file-types": ["x"] }""");
    var registry = new Syntax.LanguageRegistry ({ builtin, user });

    var package = registry.detect ("/project/file.x");

    assert_cmpstr (package.name, CompareOperator.EQ, "aaa-user");
}

private void test_a_missing_directory_is_skipped () {
    string languages = new_languages_directory ();
    add_package (languages, "ruby", """{ "name": "ruby" }""");
    var registry = new Syntax.LanguageRegistry ({ Path.build_filename (languages, "does-not-exist"), languages });

    var package = registry.by_name ("ruby");

    assert_nonnull (package);
}

private void test_a_broken_package_does_not_cost_the_others () {
    string languages = new_languages_directory ();
    add_package (languages, "broken", """{ "file-types": """);
    add_package (languages, "ruby", """{ "name": "ruby" }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.by_name ("ruby");

    assert_nonnull (package);
}

private void test_an_injection_resolves_to_the_package_of_that_name () {
    string languages = new_languages_directory ();
    add_package (languages, "css", """{ "name": "css" }""");
    add_package (languages, "scss", """{ "name": "scss", "injection-regex": "s?css" }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.for_injection ("css");

    assert_cmpstr (package.name, CompareOperator.EQ, "css");
}

private void test_an_injection_resolves_through_the_injection_regex () {
    string languages = new_languages_directory ();
    add_package (languages, "javascript", """{ "name": "javascript", "injection-regex": "^(js|javascript)$" }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.for_injection ("js");

    assert_cmpstr (package.name, CompareOperator.EQ, "javascript");
}

private void test_the_injection_regex_matching_the_most_wins () {
    string languages = new_languages_directory ();
    add_package (languages, "a-java", """{ "name": "a-java", "injection-regex": "java" }""");
    add_package (languages, "b-javascript", """{ "name": "b-javascript", "injection-regex": "javascript" }""");
    add_package (languages, "c-js", """{ "name": "c-js", "injection-regex": "ja" }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.for_injection ("javascript");

    assert_cmpstr (package.name, CompareOperator.EQ, "b-javascript");
}

private void test_an_injection_nothing_matches_resolves_to_null () {
    string languages = new_languages_directory ();
    add_package (languages, "ruby", """{ "name": "ruby", "injection-regex": "ruby" }""");
    var registry = new Syntax.LanguageRegistry ({ languages });

    var package = registry.for_injection ("python");

    assert_null (package);
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/language-registry/a_package_is_found_by_name", test_a_package_is_found_by_name);
    Test.add_func ("/models/syntax/language-registry/an_unknown_name_finds_nothing", test_an_unknown_name_finds_nothing);
    Test.add_func ("/models/syntax/language-registry/a_file_is_detected_by_its_extension", test_a_file_is_detected_by_its_extension);
    Test.add_func ("/models/syntax/language-registry/the_longest_extension_wins", test_the_longest_extension_wins);
    Test.add_func ("/models/syntax/language-registry/a_hidden_file_name_is_not_an_extension", test_a_hidden_file_name_is_not_an_extension);
    Test.add_func ("/models/syntax/language-registry/a_file_is_detected_by_a_file_name_glob", test_a_file_is_detected_by_a_file_name_glob);
    Test.add_func ("/models/syntax/language-registry/a_glob_naming_a_directory_matches_under_any_parent", test_a_glob_naming_a_directory_matches_under_any_parent);
    Test.add_func ("/models/syntax/language-registry/a_glob_beats_an_extension", test_a_glob_beats_an_extension);
    Test.add_func ("/models/syntax/language-registry/the_longest_matching_glob_wins", test_the_longest_matching_glob_wins);
    Test.add_func ("/models/syntax/language-registry/a_file_is_detected_by_its_shebang", test_a_file_is_detected_by_its_shebang);
    Test.add_func ("/models/syntax/language-registry/the_path_beats_the_shebang", test_the_path_beats_the_shebang);
    Test.add_func ("/models/syntax/language-registry/a_file_nothing_claims_is_not_detected", test_a_file_nothing_claims_is_not_detected);
    Test.add_func ("/models/syntax/language-registry/a_later_directory_replaces_a_same_named_package", test_a_later_directory_replaces_a_same_named_package);
    Test.add_func ("/models/syntax/language-registry/a_later_directory_wins_a_shared_extension", test_a_later_directory_wins_a_shared_extension);
    Test.add_func ("/models/syntax/language-registry/a_missing_directory_is_skipped", test_a_missing_directory_is_skipped);
    Test.add_func ("/models/syntax/language-registry/a_broken_package_does_not_cost_the_others", test_a_broken_package_does_not_cost_the_others);
    Test.add_func ("/models/syntax/language-registry/an_injection_resolves_to_the_package_of_that_name", test_an_injection_resolves_to_the_package_of_that_name);
    Test.add_func ("/models/syntax/language-registry/an_injection_resolves_through_the_injection_regex", test_an_injection_resolves_through_the_injection_regex);
    Test.add_func ("/models/syntax/language-registry/the_injection_regex_matching_the_most_wins", test_the_injection_regex_matching_the_most_wins);
    Test.add_func ("/models/syntax/language-registry/an_injection_nothing_matches_resolves_to_null", test_an_injection_nothing_matches_resolves_to_null);
    Test.run ();
}
