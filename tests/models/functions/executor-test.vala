// Functions.Executor: a function's strings become the edits that put them in the text.

private class Echo : Object, Functions.IRunner {
    public string[] output;
    public Echo (string[] output) { this.output = output; }
    public string[] run (Functions.Input input) throws Functions.FunctionError { return output; }
}

private class Failing : Object, Functions.IRunner {
    public string[] run (Functions.Input input) throws Functions.FunctionError {
        throw new Functions.FunctionError.SCRIPT ("main.lua:3: boom");
    }
}

private Functions.Input selections_of (string text, int[] bounds) {
    var input = new Functions.Input () { kind = "selection", text = text };
    LuaSandbox.Segment[] segments = {};
    for (int i = 0; i + 1 < bounds.length; i += 2) {
        segments += LuaSandbox.Segment () { text = text.substring (text.index_of_nth_char (bounds[i]), text.index_of_nth_char (bounds[i + 1]) - text.index_of_nth_char (bounds[i])), start = bounds[i], end = bounds[i + 1] };
    }
    input.segments = segments;
    return input;
}

private TextEdit[] run (Functions.IRunner runner, Functions.Input input) {
    var loop = new MainLoop ();
    TextEdit[] edits = {};
    var function = new Functions.Function ("f", "F", "", Functions.Scope.BOTH, {}, runner);
    Functions.Executor.run_async.begin (function, input, (obj, result) => {
        try {
            edits = Functions.Executor.run_async.end (result);
        } catch (Functions.FunctionError e) {
            error (e.message);
        }
        loop.quit ();
    });
    loop.run ();
    return edits;
}

private void test_each_changed_segment_becomes_one_edit_in_place () {
    var edits = run (new Echo ({ "AB", "ef" }), selections_of ("ab cd ef", { 0, 2, 6, 8 }));

    assert_cmpint (edits.length, CompareOperator.EQ, 1);
    assert_cmpint (edits[0].start_offset, CompareOperator.EQ, 0);
    assert_cmpint (edits[0].end_offset, CompareOperator.EQ, 2);
    assert_cmpstr (edits[0].old_text, CompareOperator.EQ, "ab");
    assert_cmpstr (edits[0].new_text, CompareOperator.EQ, "AB");
}

private void test_the_whole_document_is_one_segment () {
    var edits = run (new Echo ({ "AÇÃO" }), Functions.Input.of_document ("ação"));

    assert_cmpint (edits.length, CompareOperator.EQ, 1);
    assert_cmpint (edits[0].end_offset, CompareOperator.EQ, 4);
    assert_cmpstr (edits[0].new_text, CompareOperator.EQ, "AÇÃO");
}

private void test_the_wrong_number_of_strings_is_a_bad_output () {
    try {
        Functions.Executor.edits_for (selections_of ("ab cd", { 0, 2, 3, 5 }), { "x" });
        assert_not_reached ();
    } catch (Functions.FunctionError e) {
        assert_true (e is Functions.FunctionError.BAD_OUTPUT);
    }
}

private void test_a_failing_function_hands_its_error_back () {
    var loop = new MainLoop ();
    string? message = null;
    var function = new Functions.Function ("f", "F", "", Functions.Scope.BOTH, {}, new Failing ());

    Functions.Executor.run_async.begin (function, Functions.Input.of_document ("x"), (obj, result) => {
        try {
            Functions.Executor.run_async.end (result);
        } catch (Functions.FunctionError e) {
            message = e.message;
        }
        loop.quit ();
    });
    loop.run ();

    assert_cmpstr (message, CompareOperator.EQ, "main.lua:3: boom");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/functions/executor/each_changed_segment_becomes_one_edit_in_place", test_each_changed_segment_becomes_one_edit_in_place);
    Test.add_func ("/models/functions/executor/the_whole_document_is_one_segment", test_the_whole_document_is_one_segment);
    Test.add_func ("/models/functions/executor/the_wrong_number_of_strings_is_a_bad_output", test_the_wrong_number_of_strings_is_a_bad_output);
    Test.add_func ("/models/functions/executor/a_failing_function_hands_its_error_back", test_a_failing_function_hands_its_error_back);
    Test.run ();
}
