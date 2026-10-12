// LuaSandbox: a transform script's contract, the opus table, and what the sandbox keeps out.

private string write_script (string body) {
    try {
        var directory = DirUtils.make_tmp ("opus-lua-XXXXXX");
        var path = Path.build_filename (directory, "main.lua");
        FileUtils.set_contents (path, body);
        return path;
    } catch (Error e) {
        error (e.message);
    }
}

private LuaSandbox.TransformInput input_of (string[] texts) {
    LuaSandbox.Segment[] segments = {};
    int offset = 0;
    foreach (var text in texts) {
        segments += LuaSandbox.Segment () { text = text, start = offset, end = offset + text.char_count () };
        offset += text.char_count ();
    }
    return LuaSandbox.TransformInput () {
        kind = "selection", segments = segments, text = string.joinv ("", texts),
        cursors = { LuaSandbox.Caret () { anchor = 0, position = 4 } }, language = "lua", path = "/tmp/a.lua",
    };
}

private string[] run (string body, string[] texts) {
    try {
        return new LuaSandbox ().run_transform (write_script (body), input_of (texts));
    } catch (LuaError e) {
        error (e.message);
    }
}

/** The error a script ends in — null when it runs through. */
private LuaError? failure_of (string body, string[] texts, int limit = 100000000) {
    try {
        new LuaSandbox (limit).run_transform (write_script (body), input_of (texts));
        return null;
    } catch (LuaError e) {
        return e;
    }
}

private void test_transform_gets_one_string_back_per_segment () {
    var output = run ("function transform (input) local out = {} for i, s in ipairs (input.segments) do out[i] = opus.upper (s.text) end return out end", { "ação", "b" });

    assert_cmpstrv (output, { "AÇÃO", "B" });
}

private void test_the_input_carries_kind_text_language_path_and_cursors () {
    var output = run ("function transform (input) return { input.kind .. '|' .. input.text .. '|' .. input.language .. '|' .. input.path .. '|' .. #input.cursors .. '|' .. input.cursors[1].position .. '|' .. input.segments[2].start } end", { "ab", "cd" });

    assert_cmpstr (output[0], CompareOperator.EQ, "selection|abcd|lua|/tmp/a.lua|1|4|2");
}

private void test_opus_words_splits_identifiers_and_sentences () {
    var output = run ("function transform (input) return { table.concat (opus.words (input.segments[1].text), '|') } end", { "fooBar HTTPServer a-b_c v2Beta  última.palavra" });

    assert_cmpstr (output[0], CompareOperator.EQ, "foo|Bar|HTTP|Server|a|b|c|v2|Beta|última|palavra");
}

private void test_opus_lower_and_capitalize_know_accents () {
    var output = run ("function transform (input) return { opus.lower ('ÉCOLE'), opus.capitalize ('éCOLE') } end", { "x" });

    assert_cmpstrv (output, { "école", "École" });
}

private void test_an_error_in_the_script_names_the_file_and_line () {
    var failure = failure_of ("function transform (input)\n  error ('boom')\nend", { "x" });

    assert_true (failure is LuaError.RUN);
    assert_true (failure.message.contains ("main.lua:2: boom"));
}

private void test_a_script_without_transform_does_not_load () {
    assert_true (failure_of ("x = 1", { "x" }) is LuaError.LOAD);
}

private void test_a_loop_that_never_ends_is_stopped () {
    assert_true (failure_of ("function transform (input) while true do end end", { "x" }, 100000) is LuaError.TIMEOUT);
}

private void test_the_sandbox_has_no_way_out_of_the_process () {
    var output = run ("function transform (input) return { tostring (os), tostring (io), tostring (require), tostring (load), tostring (package) } end", { "x" });

    assert_cmpstrv (output, { "nil", "nil", "nil", "nil", "nil" });
}

private void test_a_result_that_is_not_a_table_of_strings_is_refused () {
    assert_true (failure_of ("function transform (input) return 'x' end", { "x" }) is LuaError.BAD_RESULT);
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/lib/lua-sandbox/transform_gets_one_string_back_per_segment", test_transform_gets_one_string_back_per_segment);
    Test.add_func ("/lib/lua-sandbox/the_input_carries_kind_text_language_path_and_cursors", test_the_input_carries_kind_text_language_path_and_cursors);
    Test.add_func ("/lib/lua-sandbox/opus_words_splits_identifiers_and_sentences", test_opus_words_splits_identifiers_and_sentences);
    Test.add_func ("/lib/lua-sandbox/opus_lower_and_capitalize_know_accents", test_opus_lower_and_capitalize_know_accents);
    Test.add_func ("/lib/lua-sandbox/an_error_in_the_script_names_the_file_and_line", test_an_error_in_the_script_names_the_file_and_line);
    Test.add_func ("/lib/lua-sandbox/a_script_without_transform_does_not_load", test_a_script_without_transform_does_not_load);
    Test.add_func ("/lib/lua-sandbox/a_loop_that_never_ends_is_stopped", test_a_loop_that_never_ends_is_stopped);
    Test.add_func ("/lib/lua-sandbox/the_sandbox_has_no_way_out_of_the_process", test_the_sandbox_has_no_way_out_of_the_process);
    Test.add_func ("/lib/lua-sandbox/a_result_that_is_not_a_table_of_strings_is_refused", test_a_result_that_is_not_a_table_of_strings_is_refused);
    Test.run ();
}
