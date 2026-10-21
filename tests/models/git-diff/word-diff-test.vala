// Pure logic, no git involved: GitDiff.WordDiff over fixed line pairs.

private string describe (GitDiff.CharRange[] ranges) {
    string[] parts = {};
    foreach (var range in ranges) {
        parts += "%d-%d".printf (range.start, range.end);
    }
    return string.joinv (",", parts);
}

private void check (string old_line, string new_line, string expected_old, string expected_new) {
    GitDiff.CharRange[] old_ranges;
    GitDiff.CharRange[] new_ranges;

    GitDiff.WordDiff.compute (old_line, new_line, out old_ranges, out new_ranges);

    assert_cmpstr (describe (old_ranges), CompareOperator.EQ, expected_old);
    assert_cmpstr (describe (new_ranges), CompareOperator.EQ, expected_new);
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-diff-word-diff/one-changed-word-is-marked-on-both-sides", () => {
        check ("the quick fox", "the slow fox", "4-9", "4-8");
    });

    Test.add_func ("/git-diff-word-diff/a-deleted-word-takes-its-space-along-and-marks-nothing-on-the-new-side", () => {
        check ("native with GTK4, in Vala.", "native with GTK4, in.", "20-25", "");
    });

    Test.add_func ("/git-diff-word-diff/punctuation-splits-tokens-so-only-the-word-inside-is-marked", () => {
        check ("one.two(three)", "one.two(four)", "8-13", "8-12");
    });

    Test.add_func ("/git-diff-word-diff/a-renamed-identifier-is-marked-whole", () => {
        check ("getUserName ()", "getUserId ()", "0-11", "0-9");
    });

    Test.add_func ("/git-diff-word-diff/an-indentation-change-marks-the-spaces", () => {
        check ("  x = 1", "    x = 1", "0-2", "0-4");
    });

    Test.add_func ("/git-diff-word-diff/two-separate-changes-stay-two-ranges", () => {
        check ("a = 1; b = 2;", "a = 9; b = 8;", "4-5,11-12", "4-5,11-12");
    });

    Test.add_func ("/git-diff-word-diff/touching-changed-tokens-merge-into-one-range", () => {
        check ("return a + b;", "return (a + b) * 2;", "", "7-8,13-18");
    });

    Test.add_func ("/git-diff-word-diff/equal-lines-mark-nothing", () => {
        check ("same", "same", "", "");
    });

    Test.add_func ("/git-diff-word-diff/an-empty-side-marks-the-other-whole", () => {
        check ("", "new text", "", "0-8");
    });

    Test.add_func ("/git-diff-word-diff/offsets-are-characters-not-bytes", () => {
        check ("ação x", "ação y", "5-6", "5-6");
    });

    return Test.run ();
}
