private int score_of (string target, string query_text) {
    var query = new Opus.FuzzyFinder.Query (query_text);
    int score;
    int[] ranges;
    if (!Opus.FuzzyFinder.Scorer.score (target, target.casefold (), query, out score, out ranges)) {
        return 0;
    }
    return score;
}

private int[] ranges_of (string target, string query_text) {
    var query = new Opus.FuzzyFinder.Query (query_text);
    int score;
    int[] ranges;
    Opus.FuzzyFinder.Scorer.score (target, target.casefold (), query, out score, out ranges);
    return ranges;
}

private void assert_ranges (int[] actual, int[] expected) {
    assert_cmpint (actual.length, CompareOperator.EQ, expected.length);
    for (int i = 0; i < expected.length; i++) {
        assert_cmpint (actual[i], CompareOperator.EQ, expected[i]);
    }
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/fuzzy-finder/scorer/matches-ordered-subsequence-case-insensitively", () => {
        assert_true (score_of ("src/App.vala", "apv") > 0);
        assert_true (score_of ("src/App.vala", "APP") > 0);
    });

    Test.add_func ("/fuzzy-finder/scorer/rejects-characters-out-of-order", () => {
        assert_cmpint (score_of ("src/App.vala", "vpa"), CompareOperator.EQ, 0);
    });

    Test.add_func ("/fuzzy-finder/scorer/rejects-empty-query-and-empty-target", () => {
        assert_cmpint (score_of ("src/App.vala", ""), CompareOperator.EQ, 0);
        assert_cmpint (score_of ("", "a"), CompareOperator.EQ, 0);
    });

    Test.add_func ("/fuzzy-finder/scorer/basename-prefix-beats-basename-substring", () => {
        assert_true (score_of ("src/window.ts", "win") > score_of ("src/mainwindow.ts", "win"));
    });

    Test.add_func ("/fuzzy-finder/scorer/shorter-basename-wins-the-same-prefix", () => {
        assert_true (score_of ("window.ts", "window") > score_of ("windowActions.ts", "window"));
    });

    Test.add_func ("/fuzzy-finder/scorer/basename-match-beats-directory-match", () => {
        assert_true (score_of ("lib/main.vala", "main") > score_of ("main/index.blp", "main"));
    });

    Test.add_func ("/fuzzy-finder/scorer/full-path-identity-is-the-highest-score", () => {
        assert_cmpint (score_of ("src/App.vala", "src/App.vala"), CompareOperator.EQ, Opus.FuzzyFinder.Scorer.PATH_IDENTITY_SCORE);
        assert_true (score_of ("src/App.vala", "src/App.vala") > score_of ("src/App.vala", "App.vala"));
    });

    Test.add_func ("/fuzzy-finder/scorer/path-separator-in-query-matches-across-directories", () => {
        assert_true (score_of ("src/models/file-tree.vala", "models/tree") > 0);
        assert_cmpint (score_of ("src/models/file-tree.vala", "tree/models"), CompareOperator.EQ, 0);
    });

    Test.add_func ("/fuzzy-finder/scorer/camel-case-initials-beat-scattered-letters", () => {
        assert_true (score_of ("NullPointerException.java", "npe") > score_of ("nxpxexception.java", "npe"));
    });

    Test.add_func ("/fuzzy-finder/scorer/quoted-query-requires-contiguous-match", () => {
        assert_true (score_of ("src/App.vala", "\"app\"") > 0);
        assert_cmpint (score_of ("src/App.vala", "\"apv\""), CompareOperator.EQ, 0);
    });

    Test.add_func ("/fuzzy-finder/scorer/ranges-cover-the-matched-characters", () => {
        assert_ranges (ranges_of ("src/App.vala", "app"), { 4, 7 });
        assert_ranges (ranges_of ("src/App.vala", "a.v"), { 4, 5, 7, 9 });
    });

    Test.add_func ("/fuzzy-finder/scorer/ranges-are-character-offsets-not-bytes", () => {
        assert_ranges (ranges_of ("açaí/App.vala", "app"), { 5, 8 });
    });

    Test.add_func ("/fuzzy-finder/scorer/contains-subsequence-is-a-superset-of-score", () => {
        assert_true (Opus.FuzzyFinder.Scorer.contains_subsequence ("src/app.vala", "apv"));
        assert_false (Opus.FuzzyFinder.Scorer.contains_subsequence ("src/app.vala", "vpa"));
        assert_true (Opus.FuzzyFinder.Scorer.contains_subsequence ("anything", ""));
    });

    Test.add_func ("/fuzzy-finder/scorer/char-bag-is-a-superset-check", () => {
        uint64 target = Opus.FuzzyFinder.Scorer.char_bag_of ("src/app.vala");
        uint64 inside = Opus.FuzzyFinder.Scorer.char_bag_of ("pal.");
        uint64 outside = Opus.FuzzyFinder.Scorer.char_bag_of ("z");
        assert_true ((target & inside) == inside);
        assert_false ((target & outside) == outside);
    });

    Test.add_func ("/fuzzy-finder/query/normalizes-whitespace-wildcards-and-backslashes", () => {
        var query = new Opus.FuzzyFinder.Query (" fi*le \\x ");
        assert_cmpstr (query.normalized, CompareOperator.EQ, "file/x");
        assert_true (query.contains_separator);
        assert_false (query.exact);
    });

    Test.add_func ("/fuzzy-finder/query/extends-only-when-the-previous-query-is-a-non-empty-prefix", () => {
        assert_true (new Opus.FuzzyFinder.Query ("foo").extends (new Opus.FuzzyFinder.Query ("fo")));
        assert_false (new Opus.FuzzyFinder.Query ("fo").extends (new Opus.FuzzyFinder.Query ("foo")));
        assert_false (new Opus.FuzzyFinder.Query ("foo").extends (new Opus.FuzzyFinder.Query ("")));
    });

    return Test.run ();
}
