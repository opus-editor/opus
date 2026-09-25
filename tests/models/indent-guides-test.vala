private void test_empty_text_has_no_guides () {
    // Regression: string.split("\n") on "" returns a zero-length array,
    // not one empty line — a brand-new untitled tab's buffer is exactly
    // this case and must not crash levels_for_lines()/active_guide().
    var guides = new IndentGuides ("", 2);

    var levels = guides.levels_for_lines (0, 0);

    assert_cmpint (levels[0], CompareOperator.EQ, 0);

    int start_line, end_line, level;
    guides.active_guide (0, out start_line, out end_line, out level);

    assert_cmpint (level, CompareOperator.EQ, 0);
}

private void test_flat_code_has_no_guides () {
    var guides = new IndentGuides ("line1\nline2\nline3", 2);

    var levels = guides.levels_for_lines (0, 2);

    assert_cmpint (levels[0], CompareOperator.EQ, 0);
    assert_cmpint (levels[1], CompareOperator.EQ, 0);
    assert_cmpint (levels[2], CompareOperator.EQ, 0);
}

private void test_nested_block_shows_one_guide_per_indent_level () {
    var guides = new IndentGuides ("def foo():\n  a = 1\n  b = 2", 2);

    var levels = guides.levels_for_lines (0, 2);

    assert_cmpint (levels[0], CompareOperator.EQ, 0); // "def foo():"
    assert_cmpint (levels[1], CompareOperator.EQ, 1); // "  a = 1"
    assert_cmpint (levels[2], CompareOperator.EQ, 1); // "  b = 2"
}

private void test_blank_line_opening_a_block_inherits_the_line_below_it () {
    var guides = new IndentGuides ("def foo():\n\n  a = 1", 2);

    var levels = guides.levels_for_lines (0, 2);

    assert_cmpint (levels[0], CompareOperator.EQ, 0); // "def foo():"
    assert_cmpint (levels[1], CompareOperator.EQ, 1); // blank line, about to enter the block
    assert_cmpint (levels[2], CompareOperator.EQ, 1); // "  a = 1"
}

private void test_blank_line_between_two_lines_at_the_same_depth_matches_them () {
    var guides = new IndentGuides ("def foo():\n  a = 1\n\n  b = 2", 2);

    var levels = guides.levels_for_lines (0, 3);

    assert_cmpint (levels[0], CompareOperator.EQ, 0); // "def foo():"
    assert_cmpint (levels[1], CompareOperator.EQ, 1); // "  a = 1"
    assert_cmpint (levels[2], CompareOperator.EQ, 1); // blank line, between two same-depth lines
    assert_cmpint (levels[3], CompareOperator.EQ, 1); // "  b = 2"
}

private void test_blank_line_at_a_dedent_matches_the_deeper_block () {
    // Deliberately documents the non-offside scope cut (see IndentGuides'
    // own doc comment): the blank line keeps the deeper block's level
    // rather than dropping to the shallower one below it.
    var guides = new IndentGuides ("def foo():\n  if x:\n    a = 1\n\n  b = 2", 2);

    var levels = guides.levels_for_lines (0, 4);

    assert_cmpint (levels[0], CompareOperator.EQ, 0); // "def foo():"
    assert_cmpint (levels[1], CompareOperator.EQ, 1); // "  if x:"
    assert_cmpint (levels[2], CompareOperator.EQ, 2); // "    a = 1"
    assert_cmpint (levels[3], CompareOperator.EQ, 2); // blank line, still the deeper block
    assert_cmpint (levels[4], CompareOperator.EQ, 1); // "  b = 2"
}

private void test_blank_line_before_any_content_has_no_guide () {
    var guides = new IndentGuides ("\n  a = 1", 2);

    var levels = guides.levels_for_lines (0, 1);

    assert_cmpint (levels[0], CompareOperator.EQ, 0); // blank line, nothing above it yet
    assert_cmpint (levels[1], CompareOperator.EQ, 1); // "  a = 1"
}

private void test_blank_line_after_all_content_has_no_guide () {
    var guides = new IndentGuides ("  a = 1\n", 2);

    var levels = guides.levels_for_lines (0, 1);

    assert_cmpint (levels[0], CompareOperator.EQ, 1); // "  a = 1"
    assert_cmpint (levels[1], CompareOperator.EQ, 0); // blank line, nothing below it
}

private void test_a_tab_indented_line_matches_an_equally_wide_space_indented_line () {
    var guides = new IndentGuides ("def foo():\n\tspaced\n    also_spaced", 4);

    var levels = guides.levels_for_lines (0, 2);

    assert_cmpint (levels[1], CompareOperator.EQ, levels[2]);
    assert_cmpint (levels[1], CompareOperator.EQ, 1);
}

private void test_active_guide_for_a_cursor_deep_inside_a_block_is_just_that_inner_block () {
    var guides = new IndentGuides ("def foo():\n  if x:\n    a = 1\n    b = 2\n  c = 3", 2);

    int start_line, end_line, level;
    guides.active_guide (2, out start_line, out end_line, out level); // "    a = 1"

    assert_cmpint (start_line, CompareOperator.EQ, 2);
    assert_cmpint (end_line, CompareOperator.EQ, 3); // stops before "  c = 3" (shallower)
    assert_cmpint (level, CompareOperator.EQ, 2);
}

private void test_active_guide_for_a_cursor_on_a_scope_opening_line_targets_the_block_it_opens () {
    // "  if x:" opens a block one level deeper than its own — the active
    // guide should be that child block's, not "if x:"'s own outer level
    // (which, unlike this one, also runs through "def foo():"'s other
    // statements and would wrongly lump unrelated siblings together).
    var guides = new IndentGuides ("def foo():\n  if x:\n    a = 1\n    b = 2\n  c = 3", 2);

    int start_line, end_line, level;
    guides.active_guide (1, out start_line, out end_line, out level); // "  if x:"

    assert_cmpint (start_line, CompareOperator.EQ, 2); // starts at the child line, not "if x:" itself
    assert_cmpint (end_line, CompareOperator.EQ, 3); // stops before "  c = 3" (back to "if x:"'s own level)
    assert_cmpint (level, CompareOperator.EQ, 2);
}

private void test_active_guide_for_a_cursor_on_a_scope_closing_line_targets_the_block_that_just_ended () {
    // "next_stmt" sits right after a dedent — mirrors the opening case:
    // the active guide is the block that just closed above it.
    var guides = new IndentGuides ("def foo():\n  a = 1\nnext_stmt", 2);

    int start_line, end_line, level;
    guides.active_guide (2, out start_line, out end_line, out level); // "next_stmt"

    assert_cmpint (start_line, CompareOperator.EQ, 1); // "  a = 1"
    assert_cmpint (end_line, CompareOperator.EQ, 1);
    assert_cmpint (level, CompareOperator.EQ, 1);
}

private void test_active_guide_for_a_cursor_on_an_unindented_line_that_opens_a_block_still_targets_it () {
    var guides = new IndentGuides ("def foo():\n  a = 1\n  b = 2", 2);

    int start_line, end_line, level;
    guides.active_guide (0, out start_line, out end_line, out level); // "def foo():", unindented itself

    assert_cmpint (start_line, CompareOperator.EQ, 1);
    assert_cmpint (end_line, CompareOperator.EQ, 2);
    assert_cmpint (level, CompareOperator.EQ, 1);
}

private void test_active_guide_for_a_cursor_on_a_plain_unindented_line_is_absent () {
    // Neither opens nor closes anything — just two top-level statements.
    var guides = new IndentGuides ("print(1)\nprint(2)", 2);

    int start_line, end_line, level;
    guides.active_guide (0, out start_line, out end_line, out level); // "print(1)"

    assert_cmpint (start_line, CompareOperator.EQ, -1);
    assert_cmpint (end_line, CompareOperator.EQ, -1);
    assert_cmpint (level, CompareOperator.EQ, 0);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/indent-guides/empty_text_has_no_guides", test_empty_text_has_no_guides);
    Test.add_func ("/models/indent-guides/flat_code_has_no_guides", test_flat_code_has_no_guides);
    Test.add_func ("/models/indent-guides/nested_block_shows_one_guide_per_indent_level", test_nested_block_shows_one_guide_per_indent_level);
    Test.add_func ("/models/indent-guides/blank_line_opening_a_block_inherits_the_line_below_it", test_blank_line_opening_a_block_inherits_the_line_below_it);
    Test.add_func ("/models/indent-guides/blank_line_between_two_lines_at_the_same_depth_matches_them", test_blank_line_between_two_lines_at_the_same_depth_matches_them);
    Test.add_func ("/models/indent-guides/blank_line_at_a_dedent_matches_the_deeper_block", test_blank_line_at_a_dedent_matches_the_deeper_block);
    Test.add_func ("/models/indent-guides/blank_line_before_any_content_has_no_guide", test_blank_line_before_any_content_has_no_guide);
    Test.add_func ("/models/indent-guides/blank_line_after_all_content_has_no_guide", test_blank_line_after_all_content_has_no_guide);
    Test.add_func ("/models/indent-guides/a_tab_indented_line_matches_an_equally_wide_space_indented_line", test_a_tab_indented_line_matches_an_equally_wide_space_indented_line);
    Test.add_func ("/models/indent-guides/active_guide_for_a_cursor_deep_inside_a_block_is_just_that_inner_block", test_active_guide_for_a_cursor_deep_inside_a_block_is_just_that_inner_block);
    Test.add_func ("/models/indent-guides/active_guide_for_a_cursor_on_a_scope_opening_line_targets_the_block_it_opens", test_active_guide_for_a_cursor_on_a_scope_opening_line_targets_the_block_it_opens);
    Test.add_func ("/models/indent-guides/active_guide_for_a_cursor_on_a_scope_closing_line_targets_the_block_that_just_ended", test_active_guide_for_a_cursor_on_a_scope_closing_line_targets_the_block_that_just_ended);
    Test.add_func ("/models/indent-guides/active_guide_for_a_cursor_on_an_unindented_line_that_opens_a_block_still_targets_it", test_active_guide_for_a_cursor_on_an_unindented_line_that_opens_a_block_still_targets_it);
    Test.add_func ("/models/indent-guides/active_guide_for_a_cursor_on_a_plain_unindented_line_is_absent", test_active_guide_for_a_cursor_on_a_plain_unindented_line_is_absent);
    return Test.run ();
}
