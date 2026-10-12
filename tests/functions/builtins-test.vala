// The bundled functions in src/functions/, run as the `|` list would run them — OPUS_FUNCTIONS_DIR is set by tests/meson.build.

private Functions.Registry? registry = null;

private string run (string id, string text) {
    if (registry == null) {
        registry = new Functions.Registry ({ Environment.get_variable ("OPUS_FUNCTIONS_DIR") }, (name) => false);
        registry.reload ();
    }
    var function = registry.by_id (id);
    if (function == null) {
        error ("no bundled function %s", id);
    }
    try {
        return function.runner.run (Functions.Input.of_document (text))[0];
    } catch (Functions.FunctionError e) {
        error (e.message);
    }
}

private void test_the_case_functions_work_on_a_selection_only () {
    run ("uppercase", "x");
    foreach (var id in new string[] { "uppercase", "lowercase", "kebab-case", "pascal-case", "snake-case" }) {
        assert_true (registry.by_id (id).input == Functions.Scope.SELECTION);
    }
}

private void test_uppercase_and_lowercase_know_accents () {
    assert_cmpstr (run ("uppercase", "ação é\nboa"), CompareOperator.EQ, "AÇÃO É\nBOA");
    assert_cmpstr (run ("lowercase", "AÇÃO É\nBOA"), CompareOperator.EQ, "ação é\nboa");
}

private void test_kebab_case_joins_each_lines_words_with_dashes () {
    assert_cmpstr (run ("kebab-case", "fooBar HTTPServer\nsnake_case_name\n"), CompareOperator.EQ, "foo-bar-http-server\nsnake-case-name\n");
}

private void test_pascal_case_capitalizes_and_runs_the_words_together () {
    assert_cmpstr (run ("pascal-case", "foo-bar baz\nhttp_server"), CompareOperator.EQ, "FooBarBaz\nHttpServer");
}

private void test_snake_case_joins_each_lines_words_with_underscores () {
    assert_cmpstr (run ("snake-case", "fooBar Baz\nkebab-case"), CompareOperator.EQ, "foo_bar_baz\nkebab_case");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/functions/builtins/the_case_functions_work_on_a_selection_only", test_the_case_functions_work_on_a_selection_only);
    Test.add_func ("/functions/builtins/uppercase_and_lowercase_know_accents", test_uppercase_and_lowercase_know_accents);
    Test.add_func ("/functions/builtins/kebab_case_joins_each_lines_words_with_dashes", test_kebab_case_joins_each_lines_words_with_dashes);
    Test.add_func ("/functions/builtins/pascal_case_capitalizes_and_runs_the_words_together", test_pascal_case_capitalizes_and_runs_the_words_together);
    Test.add_func ("/functions/builtins/snake_case_joins_each_lines_words_with_underscores", test_snake_case_joins_each_lines_words_with_underscores);
    Test.run ();
}
