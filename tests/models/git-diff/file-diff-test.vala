
private string describe (GitDiff.FileDiff diff) {
    var out = new StringBuilder ();
    for (uint i = 0; i < diff.lines.length; i++) {
        var l = diff.lines[i];
        var marker = l.kind == GitDiff.LineKind.ADDED ? "+" : l.kind == GitDiff.LineKind.REMOVED ? "-" : " ";
        out.append ("%s%d|%d|%s\n".printf (marker, l.old_number, l.new_number, l.text));
    }
    return out.str;
}

/** Every line with words marked, "<index>:<start>-<end>,..." joined by spaces — "" when nothing is. */
private string describe_words (GitDiff.FileDiff diff) {
    string[] marked = {};
    for (uint i = 0; i < diff.lines.length; i++) {
        string[] ranges = {};
        foreach (var range in diff.lines[i].word_changes) {
            ranges += "%d-%d".printf (range.start, range.end);
        }
        if (ranges.length > 0) {
            marked += "%u:%s".printf (i, string.joinv (",", ranges));
        }
    }
    return string.joinv (" ", marked);
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-diff-file-diff/a-removed-line-followed-by-an-added-one-pairs-their-words", () => {
        var diff = GitDiff.FileDiff.parse_unified ("@@ -1,2 +1,2 @@\n a\n-the old word\n+the new word\n");

        assert_cmpstr (describe_words (diff), CompareOperator.EQ, "1:4-7 2:4-7");
    });

    Test.add_func ("/git-diff-file-diff/a-run-of-equal-length-pairs-line-by-line", () => {
        var diff = GitDiff.FileDiff.parse_unified ("@@ -1,2 +1,2 @@\n-x = 1\n-y = 2\n+x = 3\n+y = 4\n");

        assert_cmpstr (describe_words (diff), CompareOperator.EQ, "0:4-5 1:4-5 2:4-5 3:4-5");
    });

    Test.add_func ("/git-diff-file-diff/unequal-runs-mark-no-words", () => {
        var diff = GitDiff.FileDiff.parse_unified ("@@ -1,1 +1,2 @@\n-one\n+one\n+two\n");

        assert_cmpstr (describe_words (diff), CompareOperator.EQ, "");
    });

    Test.add_func ("/git-diff-file-diff/a-run-over-five-lines-marks-no-words", () => {
        var text = new StringBuilder ("@@ -1,6 +1,6 @@\n");
        for (int i = 1; i <= 6; i++) {
            text.append ("-a %d\n".printf (i));
        }
        for (int i = 1; i <= 6; i++) {
            text.append ("+b %d\n".printf (i));
        }

        var diff = GitDiff.FileDiff.parse_unified (text.str);

        assert_cmpstr (describe_words (diff), CompareOperator.EQ, "");
    });

    Test.add_func ("/git-diff-file-diff/pure-additions-and-removals-mark-no-words", () => {
        var diff = GitDiff.FileDiff.parse_unified ("@@ -1,2 +1,2 @@\n-gone\n a\n+new\n");

        assert_cmpstr (describe_words (diff), CompareOperator.EQ, "");
    });

    Test.add_func ("/git-diff-file-diff/numbers-context-added-and-removed-lines", () => {
        try {
            var diff = GitDiff.FileDiff.compute ("a\nb\nc\n", "a\nB\nc\nd\n");

            assert (describe (diff) == " 1|1|a\n-2|0|b\n+0|2|B\n 3|3|c\n+0|4|d\n");
            assert (diff.added_count == 2 && diff.removed_count == 1);
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/git-diff-file-diff/identical-sides-are-all-context", () => {
        try {
            var diff = GitDiff.FileDiff.compute ("a\nb\n", "a\nb\n");

            assert (describe (diff) == " 1|1|a\n 2|2|b\n");
            assert (diff.added_count == 0 && diff.removed_count == 0);
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/git-diff-file-diff/a-new-file-is-all-added", () => {
        try {
            var diff = GitDiff.FileDiff.compute ("", "x\ny\n");

            assert (describe (diff) == "+0|1|x\n+0|2|y\n");
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/git-diff-file-diff/a-deleted-file-is-all-removed", () => {
        try {
            var diff = GitDiff.FileDiff.compute ("x\ny\n", "");

            assert (describe (diff) == "-1|0|x\n-2|0|y\n");
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/git-diff-file-diff/both-empty-is-nothing", () => {
        try {
            var diff = GitDiff.FileDiff.compute ("", "");

            assert (diff.lines.length == 0);
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/git-diff-file-diff/a-missing-final-newline-is-noted-not-shown", () => {
        try {
            var diff = GitDiff.FileDiff.compute ("a\nb", "a\nb\n");

            assert (describe (diff) == " 1|1|a\n-2|0|b\n+0|2|b\n");
            assert (diff.left_no_newline && !diff.right_no_newline);
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/git-diff-file-diff/crlf-is-stripped-for-display", () => {
        try {
            var diff = GitDiff.FileDiff.compute ("a\r\nb\r\n", "a\r\nc\r\n");

            assert (describe (diff) == " 1|1|a\n-2|0|b\n+0|2|c\n");
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/git-diff-file-diff/blank-and-unicode-lines-survive", () => {
        try {
            var diff = GitDiff.FileDiff.compute ("ção\n\nfim\n", "ção\n\nfim!\n");

            assert (describe (diff) == " 1|1|ção\n 2|2|\n-3|0|fim\n+0|3|fim!\n");
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/git-diff-file-diff/the-whole-file-comes-back-even-far-from-a-change", () => {
        try {
            var left = new StringBuilder ();
            var right = new StringBuilder ();
            for (int i = 1; i <= 40; i++) {
                left.append ("line %d\n".printf (i));
                right.append (i == 40 ? "changed\n" : "line %d\n".printf (i));
            }

            var diff = GitDiff.FileDiff.compute (left.str, right.str);

            assert (diff.lines.length == 41);
            assert (diff.lines[0].kind == GitDiff.LineKind.CONTEXT && diff.lines[0].old_number == 1);
            assert (diff.lines[39].kind == GitDiff.LineKind.REMOVED && diff.lines[39].old_number == 40);
            assert (diff.lines[40].kind == GitDiff.LineKind.ADDED && diff.lines[40].new_number == 40);
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/git-diff-file-diff/parse-unified-reads-a-fixed-diff", () => {
        var diff = GitDiff.FileDiff.parse_unified ("--- a\n+++ b\n@@ -1,2 +1,2 @@\n one\n-two\n+deux\n\\ No newline at end of file\n");

        assert (describe (diff) == " 1|1|one\n-2|0|two\n+0|2|deux\n");
        assert (diff.right_no_newline && !diff.left_no_newline);
    });

    return Test.run ();
}
