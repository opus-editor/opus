// OPUS_GRAMMARS_DIR is where the build put the bundled grammars — set by
// tests/meson.build.

private Syntax.GrammarSource grammar_named (string name) {
    return new Syntax.GrammarSource (name, "https://example.org/grammar", "abc", "");
}

private void test_a_bundled_grammar_loads () {
    var loader = new Syntax.GrammarLoader ({ Environment.get_variable ("OPUS_GRAMMARS_DIR") });

    uint32 abi = 0;
    try {
        abi = loader.load (grammar_named ("json")).abi_version ();
    } catch (Syntax.GrammarError e) {
        error ("%s", e.message);
    }

    assert_cmpuint (abi, CompareOperator.GE, TreeSitter.MIN_COMPATIBLE_LANGUAGE_VERSION);
    assert_cmpuint (abi, CompareOperator.LE, TreeSitter.LANGUAGE_VERSION);
}

private void test_a_grammar_is_loaded_once () {
    var loader = new Syntax.GrammarLoader ({ Environment.get_variable ("OPUS_GRAMMARS_DIR") });

    void* first = null;
    void* second = null;
    try {
        first = loader.load (grammar_named ("json"));
        second = loader.load (grammar_named ("json"));
    } catch (Syntax.GrammarError e) {
        error ("%s", e.message);
    }

    assert_true (first == second);
}

private void test_directories_are_searched_in_order () {
    string empty = Path.build_filename (Environment.get_tmp_dir (), "opus-grammar-loader-test-%u".printf (Random.next_int ()));
    DirUtils.create_with_parents (empty, 0700);
    var loader = new Syntax.GrammarLoader ({ empty, Environment.get_variable ("OPUS_GRAMMARS_DIR") });

    bool loaded = false;
    try {
        loader.load (grammar_named ("json"));
        loaded = true;
    } catch (Syntax.GrammarError e) {
        error ("%s", e.message);
    }

    assert_true (loaded);
}

private void test_a_library_built_for_the_pinned_commit_is_found () {
    string directory = Path.build_filename (Environment.get_tmp_dir (), "opus-grammar-loader-test-%u".printf (Random.next_int ()));
    DirUtils.create_with_parents (directory, 0700);
    var bundled_library = File.new_for_path (Path.build_filename (Environment.get_variable ("OPUS_GRAMMARS_DIR"), "json." + Syntax.GrammarLoader.LIBRARY_SUFFIX));
    try {
        bundled_library.copy (File.new_for_path (Path.build_filename (directory, "json-abc." + Syntax.GrammarLoader.LIBRARY_SUFFIX)), FileCopyFlags.NONE);
    } catch (Error e) {
        error ("%s", e.message);
    }
    var loader = new Syntax.GrammarLoader ({ directory });

    bool loaded = false;
    try {
        loader.load (grammar_named ("json"));
        loaded = true;
    } catch (Syntax.GrammarError e) {
        error ("%s", e.message);
    }

    assert_true (loaded);
}

private void test_a_grammar_that_was_never_compiled_is_not_found () {
    var loader = new Syntax.GrammarLoader ({ Environment.get_variable ("OPUS_GRAMMARS_DIR") });

    try {
        loader.load (grammar_named ("no-such-grammar"));
        assert_not_reached ();
    } catch (Syntax.GrammarError e) {
        assert_true (e is Syntax.GrammarError.NOT_FOUND);
    }
}

private void test_a_library_without_the_grammar_symbol_fails_to_load () {
    string directory = Path.build_filename (Environment.get_tmp_dir (), "opus-grammar-loader-test-%u".printf (Random.next_int ()));
    DirUtils.create_with_parents (directory, 0700);
    var json_library = File.new_for_path (Path.build_filename (Environment.get_variable ("OPUS_GRAMMARS_DIR"), "json." + Syntax.GrammarLoader.LIBRARY_SUFFIX));
    var renamed_library = File.new_for_path (Path.build_filename (directory, "other." + Syntax.GrammarLoader.LIBRARY_SUFFIX));
    try {
        json_library.copy (renamed_library, FileCopyFlags.NONE);
    } catch (Error e) {
        error ("%s", e.message);
    }
    var loader = new Syntax.GrammarLoader ({ directory });

    try {
        loader.load (grammar_named ("other"));
        assert_not_reached ();
    } catch (Syntax.GrammarError e) {
        assert_true (e is Syntax.GrammarError.LOAD_FAILED);
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/grammar-loader/a_bundled_grammar_loads", test_a_bundled_grammar_loads);
    Test.add_func ("/models/syntax/grammar-loader/a_grammar_is_loaded_once", test_a_grammar_is_loaded_once);
    Test.add_func ("/models/syntax/grammar-loader/directories_are_searched_in_order", test_directories_are_searched_in_order);
    Test.add_func ("/models/syntax/grammar-loader/a_library_built_for_the_pinned_commit_is_found", test_a_library_built_for_the_pinned_commit_is_found);
    Test.add_func ("/models/syntax/grammar-loader/a_grammar_that_was_never_compiled_is_not_found", test_a_grammar_that_was_never_compiled_is_not_found);
    Test.add_func ("/models/syntax/grammar-loader/a_library_without_the_grammar_symbol_fails_to_load", test_a_library_without_the_grammar_symbol_fails_to_load);
    Test.run ();
}
