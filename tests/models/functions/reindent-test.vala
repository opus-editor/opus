// Functions.Native.Reindent over the bundled languages — OPUS_LANGUAGES_DIR and OPUS_GRAMMARS_DIR are set by tests/meson.build.

private string reindent (string language, string text, bool insert_spaces = true, int indent_size = 2) {
    if (Syntax.Languages.instance == null) {
        Syntax.Languages.instance = new Syntax.Languages ({ Environment.get_variable ("OPUS_LANGUAGES_DIR") }, { Environment.get_variable ("OPUS_GRAMMARS_DIR") }, { "keyword" });
    }
    var input = Functions.Input.of_document (text);
    input.language = language;
    input.insert_spaces = insert_spaces;
    input.indent_size = indent_size;
    try {
        return new Functions.Native.Reindent ().run (input)[0];
    } catch (Functions.FunctionError e) {
        error (e.message);
    }
}

private void test_a_lua_function_body_goes_in_and_end_comes_out () {
    assert_cmpstr (reindent ("lua", "function foo()\nx = 1\n    if x then\n  y = 2\n        end\nend\n"), CompareOperator.EQ, "function foo()\n  x = 1\n  if x then\n    y = 2\n  end\nend\n");
}

private void test_blank_lines_are_emptied_and_the_rest_keeps_its_text () {
    assert_cmpstr (reindent ("lua", "local a = 1\n   \n  local b = 2\n"), CompareOperator.EQ, "local a = 1\n\nlocal b = 2\n");
}

private void test_tabs_follow_the_editors_setting () {
    assert_cmpstr (reindent ("lua", "function foo()\nx = 1\nend", false), CompareOperator.EQ, "function foo()\n\tx = 1\nend");
}

private void test_a_language_whose_whitespace_is_syntax_is_refused () {
    Syntax.Languages.instance = Syntax.Languages.instance ?? new Syntax.Languages ({ Environment.get_variable ("OPUS_LANGUAGES_DIR") }, { Environment.get_variable ("OPUS_GRAMMARS_DIR") }, { "keyword" });
    var input = Functions.Input.of_document ("def foo():\n  return 1\n");
    input.language = "python";

    try {
        new Functions.Native.Reindent ().run (input);
        assert_not_reached ();
    } catch (Functions.FunctionError e) {
        assert_true (e is Functions.FunctionError.UNSUPPORTED);
    }
}

private void test_a_file_the_grammar_cannot_read_is_refused_with_the_line () {
    Syntax.Languages.instance = Syntax.Languages.instance ?? new Syntax.Languages ({ Environment.get_variable ("OPUS_LANGUAGES_DIR") }, { Environment.get_variable ("OPUS_GRAMMARS_DIR") }, { "keyword" });
    var input = Functions.Input.of_document ("local a = 1\nlocal b = = 2\n");
    input.language = "lua";

    try {
        new Functions.Native.Reindent ().run (input);
        assert_not_reached ();
    } catch (Functions.FunctionError e) {
        assert_true (e is Functions.FunctionError.UNSUPPORTED);
        assert_true (e.message.contains ("line 2"));
    }
}

private void test_a_file_without_a_language_is_refused () {
    var input = Functions.Input.of_document ("x");

    try {
        new Functions.Native.Reindent ().run (input);
        assert_not_reached ();
    } catch (Functions.FunctionError e) {
        assert_true (e is Functions.FunctionError.UNSUPPORTED);
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/functions/reindent/a_lua_function_body_goes_in_and_end_comes_out", test_a_lua_function_body_goes_in_and_end_comes_out);
    Test.add_func ("/models/functions/reindent/blank_lines_are_emptied_and_the_rest_keeps_its_text", test_blank_lines_are_emptied_and_the_rest_keeps_its_text);
    Test.add_func ("/models/functions/reindent/tabs_follow_the_editors_setting", test_tabs_follow_the_editors_setting);
    Test.add_func ("/models/functions/reindent/a_language_whose_whitespace_is_syntax_is_refused", test_a_language_whose_whitespace_is_syntax_is_refused);
    Test.add_func ("/models/functions/reindent/a_file_the_grammar_cannot_read_is_refused_with_the_line", test_a_file_the_grammar_cannot_read_is_refused_with_the_line);
    Test.add_func ("/models/functions/reindent/a_file_without_a_language_is_refused", test_a_file_without_a_language_is_refused);
    Test.run ();
}
