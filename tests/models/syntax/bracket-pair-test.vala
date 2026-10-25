private unichar[] chars_of (string text) {
    unichar[] result = {};
    int index = 0;
    unichar c;
    while (text.get_next_char (ref index, out c)) {
        result += c;
    }
    return result;
}

private Syntax.BracketPair pair (string open, string close) {
    return new Syntax.BracketPair (open, close, {}, true, true);
}

private void test_a_pair_whose_open_is_its_close_is_a_quote () {
    assert_true (pair ("\"", "\"").is_quote);
    assert_false (pair ("(", ")").is_quote);
}

private void test_a_pair_is_inert_inside_a_capture_it_names () {
    var quote = new Syntax.BracketPair ("'", "'", { "string", "comment" }, true, true);

    assert_true (quote.inert_in ({ "comment" }));
    assert_false (quote.inert_in ({ "keyword" }));
}

private void test_a_named_capture_covers_its_more_specific_names () {
    var quote = new Syntax.BracketPair ("'", "'", { "string" }, true, true);

    assert_true (quote.inert_in ({ "string.special" }));
    assert_false (quote.inert_in ({ "stringy" }));
}

private void test_a_pair_with_nothing_to_avoid_is_never_inert () {
    assert_false (pair ("(", ")").inert_in ({ "string", "comment" }));
}

private void test_a_multi_character_open_is_found_before_an_offset () {
    var comment = pair ("/*", " */");

    assert_true (comment.opens_before (chars_of ("a /*"), 4));
    assert_false (comment.opens_before (chars_of ("a /"), 3));
    assert_false (comment.opens_before (chars_of ("*"), 1));
}

private void test_a_multi_character_close_is_found_at_an_offset () {
    var comment = pair ("/*", " */");

    assert_true (comment.closes_at (chars_of ("x */"), 1));
    assert_false (comment.closes_at (chars_of ("x *"), 1));
}

private void test_the_defaults_are_the_three_brackets_and_two_quotes () {
    var set = Syntax.PairSet.defaults ();

    string[] opens = {};
    foreach (var p in set.pairs) {
        opens += p.open;
    }
    assert_cmpstr (string.joinv ("", opens), CompareOperator.EQ, "([{\"'");
    assert_cmpstr (set.auto_close_before, CompareOperator.EQ, ";:.,=}])>");
}

private void test_typing_an_opener_finds_its_pair () {
    var set = Syntax.PairSet.defaults ();

    var found = set.opening_at (chars_of ("a"), 1, '(');

    assert_cmpstr (found.close, CompareOperator.EQ, ")");
}

private void test_typing_something_that_opens_nothing_finds_no_pair () {
    var set = Syntax.PairSet.defaults ();

    assert_null (set.opening_at (chars_of ("a"), 1, 'x'));
}

private void test_the_last_character_of_a_longer_open_needs_the_rest_before_it () {
    var set = new Syntax.PairSet ({ pair ("/*", " */") }, "");

    assert_nonnull (set.opening_at (chars_of ("a /"), 3, '*'));
    assert_null (set.opening_at (chars_of ("a "), 2, '*'));
}

private void test_the_longest_open_wins_when_two_end_the_same_way () {
    var set = new Syntax.PairSet ({ pair ("{", "}"), pair ("${", "}") }, "");

    assert_cmpstr (set.opening_at (chars_of ("$"), 1, '{').open, CompareOperator.EQ, "${");
    assert_cmpstr (set.opening_at (chars_of ("a"), 1, '{').open, CompareOperator.EQ, "{");
}

private void test_a_closer_may_go_at_the_end_of_the_text () {
    assert_true (Syntax.PairSet.defaults ().may_close_before (chars_of ("abc"), 3));
}

private void test_a_closer_may_go_before_whitespace_or_a_line_break () {
    var set = Syntax.PairSet.defaults ();

    assert_true (set.may_close_before (chars_of ("a b"), 1));
    assert_true (set.may_close_before (chars_of ("a\nb"), 1));
}

private void test_a_closer_may_go_before_a_listed_character () {
    var set = Syntax.PairSet.defaults ();

    assert_true (set.may_close_before (chars_of ("a;"), 1));
    assert_true (set.may_close_before (chars_of ("a)"), 1));
}

private void test_a_closer_may_not_go_before_a_word () {
    assert_false (Syntax.PairSet.defaults ().may_close_before (chars_of ("(value"), 1));
}

private void test_a_closer_may_go_before_a_bracket_s_close_but_not_a_quote () {
    var set = new Syntax.PairSet ({ pair ("/*", " */"), pair ("\"", "\"") }, "");

    assert_true (set.may_close_before (chars_of ("a */"), 1));
    assert_false (set.may_close_before (chars_of ("a\"b\""), 1));
}

private void test_a_single_character_closer_names_its_pair () {
    var set = new Syntax.PairSet ({ pair ("/*", " */"), pair ("(", ")") }, "");

    assert_cmpstr (set.closing_with (')').open, CompareOperator.EQ, "(");
    assert_null (set.closing_with ('/'));
    assert_null (set.closing_with ('x'));
}

private void test_an_empty_pair_is_found_around_the_offset_between_its_halves () {
    var set = Syntax.PairSet.defaults ();

    assert_cmpstr (set.around (chars_of ("x[]"), 2).close, CompareOperator.EQ, "]");
    assert_null (set.around (chars_of ("x[a]"), 2));
    assert_null (set.around (chars_of ("x[)"), 2));
}

private void test_brackets_open_a_line_on_enter_and_quotes_do_not_unless_told () {
    assert_true (pair ("(", ")").newline);
    assert_false (pair ("\"", "\"").newline);
    assert_false (new Syntax.BracketPair ("/*", " */", {}, true, true, false).newline);
    assert_true (new Syntax.BracketPair ("`", "`", {}, true, true, true).newline);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/bracket-pair/a_pair_whose_open_is_its_close_is_a_quote", test_a_pair_whose_open_is_its_close_is_a_quote);
    Test.add_func ("/models/syntax/bracket-pair/a_pair_is_inert_inside_a_capture_it_names", test_a_pair_is_inert_inside_a_capture_it_names);
    Test.add_func ("/models/syntax/bracket-pair/a_named_capture_covers_its_more_specific_names", test_a_named_capture_covers_its_more_specific_names);
    Test.add_func ("/models/syntax/bracket-pair/a_pair_with_nothing_to_avoid_is_never_inert", test_a_pair_with_nothing_to_avoid_is_never_inert);
    Test.add_func ("/models/syntax/bracket-pair/a_multi_character_open_is_found_before_an_offset", test_a_multi_character_open_is_found_before_an_offset);
    Test.add_func ("/models/syntax/bracket-pair/a_multi_character_close_is_found_at_an_offset", test_a_multi_character_close_is_found_at_an_offset);
    Test.add_func ("/models/syntax/bracket-pair/the_defaults_are_the_three_brackets_and_two_quotes", test_the_defaults_are_the_three_brackets_and_two_quotes);
    Test.add_func ("/models/syntax/bracket-pair/typing_an_opener_finds_its_pair", test_typing_an_opener_finds_its_pair);
    Test.add_func ("/models/syntax/bracket-pair/typing_something_that_opens_nothing_finds_no_pair", test_typing_something_that_opens_nothing_finds_no_pair);
    Test.add_func ("/models/syntax/bracket-pair/the_last_character_of_a_longer_open_needs_the_rest_before_it", test_the_last_character_of_a_longer_open_needs_the_rest_before_it);
    Test.add_func ("/models/syntax/bracket-pair/the_longest_open_wins_when_two_end_the_same_way", test_the_longest_open_wins_when_two_end_the_same_way);
    Test.add_func ("/models/syntax/bracket-pair/a_closer_may_go_at_the_end_of_the_text", test_a_closer_may_go_at_the_end_of_the_text);
    Test.add_func ("/models/syntax/bracket-pair/a_closer_may_go_before_whitespace_or_a_line_break", test_a_closer_may_go_before_whitespace_or_a_line_break);
    Test.add_func ("/models/syntax/bracket-pair/a_closer_may_go_before_a_listed_character", test_a_closer_may_go_before_a_listed_character);
    Test.add_func ("/models/syntax/bracket-pair/a_closer_may_not_go_before_a_word", test_a_closer_may_not_go_before_a_word);
    Test.add_func ("/models/syntax/bracket-pair/a_closer_may_go_before_a_bracket_s_close_but_not_a_quote", test_a_closer_may_go_before_a_bracket_s_close_but_not_a_quote);
    Test.add_func ("/models/syntax/bracket-pair/a_single_character_closer_names_its_pair", test_a_single_character_closer_names_its_pair);
    Test.add_func ("/models/syntax/bracket-pair/an_empty_pair_is_found_around_the_offset_between_its_halves", test_an_empty_pair_is_found_around_the_offset_between_its_halves);
    Test.add_func ("/models/syntax/bracket-pair/brackets_open_a_line_on_enter_and_quotes_do_not_unless_told", test_brackets_open_a_line_on_enter_and_quotes_do_not_unless_told);
    return Test.run ();
}
