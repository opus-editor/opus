private unichar[] chars_of (string text) {
    unichar[] result = {};
    int index = 0;
    unichar c;
    while (text.get_next_char (ref index, out c)) {
        result += c;
    }
    return result;
}

private Syntax.BracketPair pair (string open, string close, string[] not_in = {}, bool auto_close = true, bool surround = true) {
    return new Syntax.BracketPair (open, close, not_in, auto_close, surround);
}

private AutoClose all_on () {
    return new AutoClose (AutoCloseSettings.all_on (), null);
}

private AutoClose with_settings (bool brackets, bool quotes, bool surround_selection, bool track) {
    return new AutoClose (new AutoCloseSettings (brackets, quotes, surround_selection, track), null);
}

/** An AutoClose whose language declares `pairs_json` (the manifest's own array) and whose syntax calls every place `captures`. */
private AutoClose in_scope (string pairs_json, string[] captures) {
    var package = parse_package ("""{ "name": "fake", "pairs": """ + pairs_json + " }");
    var scope = new Syntax.Scope (package, captures);
    return new AutoClose (AutoCloseSettings.all_on (), (offset, of_character) => scope);
}

private Cursor selecting (int anchor, int position) {
    var cursor = new Cursor (anchor);
    cursor.position_offset = position;
    return cursor;
}

private Syntax.LanguagePackage parse_package (string manifest) {
    try {
        return Syntax.LanguagePackage.parse ("/packages/fake", manifest);
    } catch (Syntax.PackageError e) {
        error ("%s", e.message);
    }
}

/** `text` with the edit applied and `|` where the caret lands; null when the keystroke is plain typing. */
private string? typed (AutoClose auto_close, string text, int offset, unichar ch, InsertedPairs? memory = null, bool overtype_mode = false) {
    var tagged = auto_close.typing_edit (chars_of (text), new Cursor (offset), ch, overtype_mode, memory ?? new InsertedPairs ());
    if (tagged == null) {
        return null;
    }
    return applied (tagged, text);
}

private string applied (TaggedTextEdit tagged, string text) {
    var edit = tagged.edit;
    var caret = tagged.caret_in_new_text < 0 ? edit.new_text.char_count () : tagged.caret_in_new_text;
    var inserted = edit.new_text.substring (0, edit.new_text.index_of_nth_char (caret)) + "|" + edit.new_text.substring (edit.new_text.index_of_nth_char (caret));
    return text.substring (0, text.index_of_nth_char (edit.start_offset)) + inserted + text.substring (text.index_of_nth_char (edit.end_offset));
}

private InsertedPairs remembering (int open_offset, int close_offset, Syntax.BracketPair p) {
    var memory = new InsertedPairs ();
    memory.remember (open_offset, close_offset, p);
    return memory;
}

// ---- auto-close ----

private void test_an_opener_at_the_end_of_the_text_closes () {
    assert_cmpstr (typed (all_on (), "a = ", 4, '('), CompareOperator.EQ, "a = (|)");
}

private void test_an_opener_before_a_word_is_plain () {
    assert_null (typed (all_on (), "return value", 7, '('));
}

private void test_an_opener_before_punctuation_or_a_closer_closes () {
    assert_cmpstr (typed (all_on (), "f;", 1, '('), CompareOperator.EQ, "f(|);");
    assert_cmpstr (typed (all_on (), "f)", 1, '('), CompareOperator.EQ, "f(|))");
    assert_cmpstr (typed (all_on (), "f x", 1, '('), CompareOperator.EQ, "f(|) x");
}

private void test_a_pair_that_does_not_auto_close_is_plain () {
    var auto_close = in_scope ("""[{ "open": "<", "close": ">", "auto-close": false }]""", {});

    assert_null (typed (auto_close, "Vec", 3, '<'));
}

private void test_the_brackets_switch_leaves_quotes_closing () {
    var auto_close = with_settings (false, true, true, true);

    assert_null (typed (auto_close, "", 0, '('));
    assert_cmpstr (typed (auto_close, "", 0, '"'), CompareOperator.EQ, "\"|\"");
}

private void test_the_quotes_switch_leaves_brackets_closing () {
    var auto_close = with_settings (true, false, true, true);

    assert_null (typed (auto_close, "", 0, '"'));
    assert_cmpstr (typed (auto_close, "", 0, '('), CompareOperator.EQ, "(|)");
}

private void test_a_longer_open_closes_on_its_last_character () {
    var auto_close = in_scope ("""[{ "open": "/*", "close": " */" }]""", {});

    assert_null (typed (auto_close, "", 0, '/'));
    assert_cmpstr (typed (auto_close, "/", 1, '*'), CompareOperator.EQ, "/*| */");
}

private void test_a_pair_is_plain_inside_a_capture_it_avoids () {
    var auto_close = in_scope ("""[{ "open": "\"", "close": "\"", "not-in": ["string"] }]""", { "string.special" });

    assert_null (typed (auto_close, "", 0, '"'));
}

private void test_a_pair_closes_inside_a_capture_it_does_not_avoid () {
    var auto_close = in_scope ("""[{ "open": "\"", "close": "\"", "not-in": ["string"] }]""", { "comment" });

    assert_cmpstr (typed (auto_close, "", 0, '"'), CompareOperator.EQ, "\"|\"");
}

private void test_a_quote_after_a_word_character_is_plain () {
    assert_null (typed (all_on (), "don", 3, '\''));
    assert_null (typed (all_on (), "1", 1, '"'));
    assert_null (typed (all_on (), "_", 1, '"'));
}

private void test_a_quote_closing_an_open_string_is_plain () {
    assert_null (typed (all_on (), "\"hello ", 7, '"'));
}

private void test_a_quote_after_a_closed_string_closes () {
    assert_cmpstr (typed (all_on (), "\"a\" ", 4, '"'), CompareOperator.EQ, "\"a\" \"|\"");
}

private void test_a_quote_where_the_pair_is_inert_does_not_count_toward_an_open_string () {
    var auto_close = in_scope ("""[{ "open": "'", "close": "'", "not-in": ["comment"] }]""", { "comment" });
    var inside_comment = in_scope ("""[{ "open": "'", "close": "'", "not-in": ["comment"] }]""", {});

    assert_null (typed (auto_close, "// don't ", 9, '\''));
    assert_null (typed (inside_comment, "x = 'a", 6, '\''));
}

private void test_the_quote_count_is_per_line () {
    assert_cmpstr (typed (all_on (), "\"open\n", 6, '"'), CompareOperator.EQ, "\"open\n\"|\"");
}

// ---- overtype ----

private void test_typing_a_remembered_closer_moves_past_it () {
    var memory = remembering (0, 4, pair ("(", ")"));

    var tagged = all_on ().typing_edit (chars_of ("(foo)"), new Cursor (4), ')', false, memory);

    assert_nonnull (tagged);
    assert_cmpstr (tagged.edit.old_text, CompareOperator.EQ, tagged.edit.new_text);
    assert_cmpint (tagged.edit.start_offset, CompareOperator.EQ, 4);
    assert_cmpint (tagged.edit.end_offset, CompareOperator.EQ, 5);
}

private void test_typing_a_closer_nobody_remembers_inserts_it () {
    assert_null (typed (all_on (), "(foo)", 4, ')'));
}

private void test_without_tracking_any_closer_under_the_caret_is_skipped () {
    var auto_close = with_settings (true, true, true, false);

    var tagged = auto_close.typing_edit (chars_of ("(foo)"), new Cursor (4), ')', false, new InsertedPairs ());

    assert_nonnull (tagged);
    assert_cmpstr (tagged.edit.old_text, CompareOperator.EQ, ")");
}

private void test_the_typed_character_must_be_the_one_under_the_caret () {
    var memory = remembering (0, 4, pair ("(", ")"));

    assert_cmpstr (typed (all_on (), "(foo)", 4, '[', memory), CompareOperator.EQ, "(foo[|])");
}

private void test_a_quote_after_a_backslash_is_never_skipped () {
    var memory = remembering (0, 3, pair ("\"", "\""));

    assert_null (typed (all_on (), "\"a\\\"", 3, '"', memory));
}

private void test_a_longer_closer_is_never_skipped () {
    var memory = remembering (0, 2, pair ("/*", " */"));

    assert_null (typed (all_on (), "/* */", 2, ' ', memory));
}

private void test_a_closer_is_not_skipped_when_its_kind_is_off () {
    var auto_close = with_settings (false, true, true, true);
    var memory = remembering (0, 1, pair ("(", ")"));

    assert_null (typed (auto_close, "()", 1, ')', memory));
}

// ---- insert-key overtype mode ----

private void test_in_overtype_mode_nothing_closes_or_skips () {
    var memory = remembering (0, 1, pair ("(", ")"));

    assert_null (typed (all_on (), "", 0, '(', null, true));
    assert_null (typed (all_on (), "()", 1, ')', memory, true));
}

private void test_in_overtype_mode_a_selection_still_gets_surrounded () {
    var tagged = all_on ().typing_edit (chars_of ("foo"), selecting (0, 3), '(', true, new InsertedPairs ());

    assert_cmpstr (tagged.edit.new_text, CompareOperator.EQ, "(foo)");
}

// ---- surround ----

private void test_typing_an_opener_over_a_selection_wraps_it_and_keeps_it_selected () {
    var tagged = all_on ().typing_edit (chars_of ("foo"), selecting (0, 3), '(', false, new InsertedPairs ());

    assert_cmpstr (tagged.edit.new_text, CompareOperator.EQ, "(foo)");
    assert_cmpint (tagged.anchor_in_new_text, CompareOperator.EQ, 1);
    assert_cmpint (tagged.caret_in_new_text, CompareOperator.EQ, 4);
}

private void test_typing_a_closer_over_a_selection_wraps_it_too () {
    var tagged = all_on ().typing_edit (chars_of ("foo"), selecting (0, 3), ')', false, new InsertedPairs ());

    assert_cmpstr (tagged.edit.new_text, CompareOperator.EQ, "(foo)");
}

private void test_a_backwards_selection_stays_backwards_when_wrapped () {
    var tagged = all_on ().typing_edit (chars_of ("foo"), selecting (3, 0), '"', false, new InsertedPairs ());

    assert_cmpint (tagged.anchor_in_new_text, CompareOperator.EQ, 4);
    assert_cmpint (tagged.caret_in_new_text, CompareOperator.EQ, 1);
}

private void test_a_longer_open_does_not_surround () {
    var auto_close = in_scope ("""[{ "open": "/*", "close": " */" }]""", {});

    assert_null (auto_close.typing_edit (chars_of ("/foo"), selecting (1, 4), '*', false, new InsertedPairs ()));
}

private void test_a_pair_that_does_not_surround_replaces_the_selection () {
    var auto_close = in_scope ("""[{ "open": "(", "close": ")", "surround": false }]""", {});

    assert_null (auto_close.typing_edit (chars_of ("foo"), selecting (0, 3), '(', false, new InsertedPairs ()));
}

private void test_with_surround_off_the_selection_is_replaced () {
    var auto_close = with_settings (true, true, false, true);

    assert_null (auto_close.typing_edit (chars_of ("foo"), selecting (0, 3), '(', false, new InsertedPairs ()));
}

// ---- backspace ----

private void test_backspace_inside_a_remembered_empty_pair_takes_both_out () {
    var memory = remembering (0, 1, pair ("(", ")"));

    var tagged = all_on ().backspace_edit (chars_of ("()"), new Cursor (1), false, memory);

    assert_nonnull (tagged);
    assert_cmpint (tagged.edit.start_offset, CompareOperator.EQ, 0);
    assert_cmpint (tagged.edit.end_offset, CompareOperator.EQ, 2);
    assert_cmpstr (tagged.edit.new_text, CompareOperator.EQ, "");
}

private void test_backspace_inside_a_pair_nobody_remembers_is_plain () {
    assert_null (all_on ().backspace_edit (chars_of ("()"), new Cursor (1), false, new InsertedPairs ()));
}

private void test_without_tracking_backspace_takes_any_empty_pair_out () {
    var auto_close = with_settings (true, true, true, false);

    var tagged = auto_close.backspace_edit (chars_of ("x()"), new Cursor (2), false, new InsertedPairs ());

    assert_nonnull (tagged);
    assert_cmpint (tagged.edit.start_offset, CompareOperator.EQ, 1);
    assert_cmpint (tagged.edit.end_offset, CompareOperator.EQ, 3);
}

private void test_backspace_with_something_between_the_pair_is_plain () {
    var memory = remembering (0, 2, pair ("(", ")"));

    assert_null (all_on ().backspace_edit (chars_of ("(a)"), new Cursor (2), false, memory));
}

private void test_backspace_in_overtype_mode_is_plain () {
    var memory = remembering (0, 1, pair ("(", ")"));

    assert_null (all_on ().backspace_edit (chars_of ("()"), new Cursor (1), true, memory));
}

private void test_backspace_with_a_selection_is_plain () {
    var memory = remembering (0, 1, pair ("(", ")"));

    assert_null (all_on ().backspace_edit (chars_of ("()"), selecting (0, 1), false, memory));
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/auto-close/an_opener_at_the_end_of_the_text_closes", test_an_opener_at_the_end_of_the_text_closes);
    Test.add_func ("/models/auto-close/an_opener_before_a_word_is_plain", test_an_opener_before_a_word_is_plain);
    Test.add_func ("/models/auto-close/an_opener_before_punctuation_or_a_closer_closes", test_an_opener_before_punctuation_or_a_closer_closes);
    Test.add_func ("/models/auto-close/a_pair_that_does_not_auto_close_is_plain", test_a_pair_that_does_not_auto_close_is_plain);
    Test.add_func ("/models/auto-close/the_brackets_switch_leaves_quotes_closing", test_the_brackets_switch_leaves_quotes_closing);
    Test.add_func ("/models/auto-close/the_quotes_switch_leaves_brackets_closing", test_the_quotes_switch_leaves_brackets_closing);
    Test.add_func ("/models/auto-close/a_longer_open_closes_on_its_last_character", test_a_longer_open_closes_on_its_last_character);
    Test.add_func ("/models/auto-close/a_pair_is_plain_inside_a_capture_it_avoids", test_a_pair_is_plain_inside_a_capture_it_avoids);
    Test.add_func ("/models/auto-close/a_pair_closes_inside_a_capture_it_does_not_avoid", test_a_pair_closes_inside_a_capture_it_does_not_avoid);
    Test.add_func ("/models/auto-close/a_quote_after_a_word_character_is_plain", test_a_quote_after_a_word_character_is_plain);
    Test.add_func ("/models/auto-close/a_quote_closing_an_open_string_is_plain", test_a_quote_closing_an_open_string_is_plain);
    Test.add_func ("/models/auto-close/a_quote_after_a_closed_string_closes", test_a_quote_after_a_closed_string_closes);
    Test.add_func ("/models/auto-close/a_quote_where_the_pair_is_inert_does_not_count_toward_an_open_string", test_a_quote_where_the_pair_is_inert_does_not_count_toward_an_open_string);
    Test.add_func ("/models/auto-close/the_quote_count_is_per_line", test_the_quote_count_is_per_line);
    Test.add_func ("/models/auto-close/typing_a_remembered_closer_moves_past_it", test_typing_a_remembered_closer_moves_past_it);
    Test.add_func ("/models/auto-close/typing_a_closer_nobody_remembers_inserts_it", test_typing_a_closer_nobody_remembers_inserts_it);
    Test.add_func ("/models/auto-close/without_tracking_any_closer_under_the_caret_is_skipped", test_without_tracking_any_closer_under_the_caret_is_skipped);
    Test.add_func ("/models/auto-close/the_typed_character_must_be_the_one_under_the_caret", test_the_typed_character_must_be_the_one_under_the_caret);
    Test.add_func ("/models/auto-close/a_quote_after_a_backslash_is_never_skipped", test_a_quote_after_a_backslash_is_never_skipped);
    Test.add_func ("/models/auto-close/a_longer_closer_is_never_skipped", test_a_longer_closer_is_never_skipped);
    Test.add_func ("/models/auto-close/a_closer_is_not_skipped_when_its_kind_is_off", test_a_closer_is_not_skipped_when_its_kind_is_off);
    Test.add_func ("/models/auto-close/in_overtype_mode_nothing_closes_or_skips", test_in_overtype_mode_nothing_closes_or_skips);
    Test.add_func ("/models/auto-close/in_overtype_mode_a_selection_still_gets_surrounded", test_in_overtype_mode_a_selection_still_gets_surrounded);
    Test.add_func ("/models/auto-close/typing_an_opener_over_a_selection_wraps_it_and_keeps_it_selected", test_typing_an_opener_over_a_selection_wraps_it_and_keeps_it_selected);
    Test.add_func ("/models/auto-close/typing_a_closer_over_a_selection_wraps_it_too", test_typing_a_closer_over_a_selection_wraps_it_too);
    Test.add_func ("/models/auto-close/a_backwards_selection_stays_backwards_when_wrapped", test_a_backwards_selection_stays_backwards_when_wrapped);
    Test.add_func ("/models/auto-close/a_longer_open_does_not_surround", test_a_longer_open_does_not_surround);
    Test.add_func ("/models/auto-close/a_pair_that_does_not_surround_replaces_the_selection", test_a_pair_that_does_not_surround_replaces_the_selection);
    Test.add_func ("/models/auto-close/with_surround_off_the_selection_is_replaced", test_with_surround_off_the_selection_is_replaced);
    Test.add_func ("/models/auto-close/backspace_inside_a_remembered_empty_pair_takes_both_out", test_backspace_inside_a_remembered_empty_pair_takes_both_out);
    Test.add_func ("/models/auto-close/backspace_inside_a_pair_nobody_remembers_is_plain", test_backspace_inside_a_pair_nobody_remembers_is_plain);
    Test.add_func ("/models/auto-close/without_tracking_backspace_takes_any_empty_pair_out", test_without_tracking_backspace_takes_any_empty_pair_out);
    Test.add_func ("/models/auto-close/backspace_with_something_between_the_pair_is_plain", test_backspace_with_something_between_the_pair_is_plain);
    Test.add_func ("/models/auto-close/backspace_in_overtype_mode_is_plain", test_backspace_in_overtype_mode_is_plain);
    Test.add_func ("/models/auto-close/backspace_with_a_selection_is_plain", test_backspace_with_a_selection_is_plain);
    return Test.run ();
}
