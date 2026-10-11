
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-diff-conflict-parser/one-block-with-its-labels-and-ranges", () => {
        var conflicts = GitDiff.ConflictParser.parse ("a\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> side\nz\n");

        assert (conflicts.length == 1);
        var c = conflicts[0];
        assert (c.start_line == 1 && c.splitter_line == 3 && c.end_line == 5 && c.base_line == -1);
        assert (c.current_label == "HEAD" && c.incoming_label == "side");
        assert (c.current_first == 2 && c.current_last == 2);
        assert (c.incoming_first == 4 && c.incoming_last == 4);
    });

    Test.add_func ("/git-diff-conflict-parser/two-blocks-in-order", () => {
        var conflicts = GitDiff.ConflictParser.parse ("<<<<<<< a\n1\n=======\n2\n>>>>>>> b\nmid\n<<<<<<< a\n3\n=======\n4\n>>>>>>> b\n");

        assert (conflicts.length == 2);
        assert (conflicts[0].start_line == 0 && conflicts[1].start_line == 6);
    });

    Test.add_func ("/git-diff-conflict-parser/diff3-base-section-is-kept-out-of-current", () => {
        var conflicts = GitDiff.ConflictParser.parse ("<<<<<<< HEAD\nours\n||||||| base\norig\n=======\ntheirs\n>>>>>>> side\n");

        assert (conflicts.length == 1);
        var c = conflicts[0];
        assert (c.base_line == 2 && c.current_last == 1);
        assert (c.incoming_first == 5 && c.incoming_last == 5);
    });

    Test.add_func ("/git-diff-conflict-parser/a-block-without-its-close-is-dropped", () => {
        assert (GitDiff.ConflictParser.parse ("<<<<<<< HEAD\nours\n=======\ntheirs\n").length == 0);
        assert (!GitDiff.ConflictParser.contains_conflict ("<<<<<<< HEAD\nx\n"));
    });

    Test.add_func ("/git-diff-conflict-parser/a-splitter-lookalike-inside-content-does-not-split", () => {
        var conflicts = GitDiff.ConflictParser.parse ("<<<<<<< HEAD\n======= not exact\n=======\ntheirs\n>>>>>>> side\n");

        assert (conflicts.length == 1 && conflicts[0].splitter_line == 2);
    });

    Test.add_func ("/git-diff-conflict-parser/an-empty-side-has-an-empty-range", () => {
        var conflicts = GitDiff.ConflictParser.parse ("<<<<<<< HEAD\n=======\ntheirs\n>>>>>>> side\n");

        assert (conflicts.length == 1);
        assert (conflicts[0].current_last < conflicts[0].current_first);
    });

    Test.add_func ("/git-diff-conflict-parser/crlf-markers-still-match", () => {
        var conflicts = GitDiff.ConflictParser.parse ("<<<<<<< HEAD\r\nours\r\n=======\r\ntheirs\r\n>>>>>>> side\r\n");

        assert (conflicts.length == 1 && conflicts[0].incoming_label == "side");
    });

    Test.add_func ("/git-diff-conflict-parser/a-second-start-restarts-the-block", () => {
        var conflicts = GitDiff.ConflictParser.parse ("<<<<<<< a\nlost\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> side\n");

        assert (conflicts.length == 1 && conflicts[0].start_line == 2);
    });

    return Test.run ();
}
