// Builds the JSON grammar from the checkout Meson itself fetched
// (OPUS_TEST_GRAMMAR_REPOSITORY, set by tests/meson.build), so no test
// here touches the network. Skipped where that checkout isn't a git
// repository, or there is no git or C compiler to build with.

private bool can_build () {
    string repository = Environment.get_variable ("OPUS_TEST_GRAMMAR_REPOSITORY");
    bool possible = FileUtils.test (Path.build_filename (repository, ".git"), FileTest.EXISTS)
        && HostCommand.has_program ("git")
        && HostCommand.has_program ("cc");
    if (!possible) {
        Test.skip ("needs git, cc and a git checkout of the JSON grammar");
    }
    return possible;
}

/** The JSON grammar as its bundled package pins it, fetched from the local checkout instead. */
private Syntax.GrammarSource json_grammar (string path = "") {
    string repository = Environment.get_variable ("OPUS_TEST_GRAMMAR_REPOSITORY");
    string rev;
    try {
        rev = Syntax.LanguagePackage.load (Path.build_filename (Environment.get_variable ("OPUS_LANGUAGES_DIR"), "json")).grammar.rev;
    } catch (Syntax.PackageError e) {
        error ("%s", e.message);
    }
    return new Syntax.GrammarSource ("json", repository, rev, path);
}

private string new_directory () {
    return Path.build_filename (Environment.get_tmp_dir (), "opus-grammar-builder-test-%u".printf (Random.next_int ()));
}

private void test_a_built_grammar_loads () {
    if (!can_build ()) {
        return;
    }
    string output = new_directory ();
    var builder = new Syntax.GrammarBuilder (new_directory (), output);
    var grammar = json_grammar ();

    uint32 abi = 0;
    try {
        builder.build (grammar);
        abi = new Syntax.GrammarLoader ({ output }).load (grammar).abi_version ();
    } catch (Error e) {
        error ("%s", e.message);
    }

    assert_cmpuint (abi, CompareOperator.GE, TreeSitter.MIN_COMPATIBLE_LANGUAGE_VERSION);
}

private void test_the_library_is_named_for_the_grammar_and_its_commit () {
    if (!can_build ()) {
        return;
    }
    string output = new_directory ();
    var builder = new Syntax.GrammarBuilder (new_directory (), output);
    var grammar = json_grammar ();

    string library = "";
    try {
        library = builder.build (grammar);
    } catch (Syntax.BuildError e) {
        error ("%s", e.message);
    }

    assert_cmpstr (library, CompareOperator.EQ, Path.build_filename (output, "json-%s.so".printf (grammar.rev)));
    assert_true (FileUtils.test (library, FileTest.IS_REGULAR));
}

private void test_a_grammar_already_built_is_left_alone () {
    if (!can_build ()) {
        return;
    }
    var builder = new Syntax.GrammarBuilder (new_directory (), new_directory ());
    var grammar = json_grammar ();
    string library;
    try {
        library = builder.build (grammar);
        FileUtils.set_contents (library, "stands in for the built library");
        builder.build (grammar);
    } catch (Error e) {
        error ("%s", e.message);
    }

    string contents;
    try {
        FileUtils.get_contents (library, out contents);
    } catch (FileError e) {
        error ("%s", e.message);
    }

    assert_cmpstr (contents, CompareOperator.EQ, "stands in for the built library");
}

private void test_a_commit_the_repository_does_not_have_fails () {
    if (!can_build ()) {
        return;
    }
    var builder = new Syntax.GrammarBuilder (new_directory (), new_directory ());
    var grammar = new Syntax.GrammarSource ("json", Environment.get_variable ("OPUS_TEST_GRAMMAR_REPOSITORY"), "0000000000000000000000000000000000000000", "");

    try {
        builder.build (grammar);
        assert_not_reached ();
    } catch (Syntax.BuildError e) {
        assert_true (e is Syntax.BuildError.FAILED);
    }
}

private void test_a_path_without_a_parser_fails () {
    if (!can_build ()) {
        return;
    }
    var builder = new Syntax.GrammarBuilder (new_directory (), new_directory ());

    try {
        builder.build (json_grammar ("no-such-subdirectory"));
        assert_not_reached ();
    } catch (Syntax.BuildError e) {
        assert_true (e.message.contains ("parser.c"));
    }
}

private void test_a_failed_build_leaves_no_library_behind () {
    if (!can_build ()) {
        return;
    }
    string output = new_directory ();
    var builder = new Syntax.GrammarBuilder (new_directory (), output);
    var grammar = json_grammar ("no-such-subdirectory");

    try {
        builder.build (grammar);
    } catch (Syntax.BuildError e) {
        // Expected: the test is about what the failure leaves on disk.
    }

    assert_false (FileUtils.test (builder.library_path (grammar), FileTest.EXISTS));
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/grammar-builder/a_built_grammar_loads", test_a_built_grammar_loads);
    Test.add_func ("/models/syntax/grammar-builder/the_library_is_named_for_the_grammar_and_its_commit", test_the_library_is_named_for_the_grammar_and_its_commit);
    Test.add_func ("/models/syntax/grammar-builder/a_grammar_already_built_is_left_alone", test_a_grammar_already_built_is_left_alone);
    Test.add_func ("/models/syntax/grammar-builder/a_commit_the_repository_does_not_have_fails", test_a_commit_the_repository_does_not_have_fails);
    Test.add_func ("/models/syntax/grammar-builder/a_path_without_a_parser_fails", test_a_path_without_a_parser_fails);
    Test.add_func ("/models/syntax/grammar-builder/a_failed_build_leaves_no_library_behind", test_a_failed_build_leaves_no_library_behind);
    Test.run ();
}
