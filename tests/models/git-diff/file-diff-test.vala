
private string describe (GitDiff.FileDiff diff) {
    var out = new StringBuilder ();
    for (uint i = 0; i < diff.lines.length; i++) {
        var l = diff.lines[i];
        var marker = l.kind == GitDiff.LineKind.ADDED ? "+" : l.kind == GitDiff.LineKind.REMOVED ? "-" : " ";
        out.append ("%s%d|%d|%s\n".printf (marker, l.old_number, l.new_number, l.text));
    }
    return out.str;
}

int main (string[] args) {
    Test.init (ref args);

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
