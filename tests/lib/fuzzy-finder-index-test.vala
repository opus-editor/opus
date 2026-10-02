private Opus.FuzzyFinder.Index make_index () {
    var index = new Opus.FuzzyFinder.Index ();
    index.set_candidates ({
        "src/App.vala",
        "src/main.vala",
        "src/models/file-tree.vala",
        "src/views/main/main-window/index.vala",
        "README.md",
        "tests/models/file-tree-test.vala",
    });
    return index;
}

private string[] texts_of (Opus.FuzzyFinder.Index index, Opus.FuzzyFinder.Match[] matches) {
    var result = new string[matches.length];
    for (int i = 0; i < matches.length; i++) {
        result[i] = index.text_at (matches[i].candidate_index);
    }
    return result;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/fuzzy-finder/index/ranks-the-best-basename-match-first", () => {
        var index = make_index ();

        var matches = index.search (new Opus.FuzzyFinder.Query ("filetree"), 10);

        var texts = texts_of (index, matches);
        assert_cmpint (texts.length, CompareOperator.EQ, 2);
        assert_cmpstr (texts[0], CompareOperator.EQ, "src/models/file-tree.vala");
        assert_cmpstr (texts[1], CompareOperator.EQ, "tests/models/file-tree-test.vala");
    });

    Test.add_func ("/fuzzy-finder/index/empty-query-returns-nothing", () => {
        var index = make_index ();

        var matches = index.search (new Opus.FuzzyFinder.Query ("  "), 10);

        assert_cmpint (matches.length, CompareOperator.EQ, 0);
    });

    Test.add_func ("/fuzzy-finder/index/no-candidate-matches", () => {
        var index = make_index ();

        var matches = index.search (new Opus.FuzzyFinder.Query ("zzz"), 10);

        assert_cmpint (matches.length, CompareOperator.EQ, 0);
    });

    Test.add_func ("/fuzzy-finder/index/caps-at-max-results", () => {
        var index = make_index ();

        var matches = index.search (new Opus.FuzzyFinder.Query ("vala"), 2);

        assert_cmpint (matches.length, CompareOperator.EQ, 2);
    });

    Test.add_func ("/fuzzy-finder/index/directory-in-query-matches-the-whole-path", () => {
        var index = make_index ();

        var matches = index.search (new Opus.FuzzyFinder.Query ("tests/tree"), 10);

        var texts = texts_of (index, matches);
        assert_cmpint (texts.length, CompareOperator.EQ, 1);
        assert_cmpstr (texts[0], CompareOperator.EQ, "tests/models/file-tree-test.vala");
    });

    Test.add_func ("/fuzzy-finder/index/growing-query-gives-the-same-result-as-a-fresh-one", () => {
        var incremental = make_index ();
        var fresh = make_index ();

        incremental.search (new Opus.FuzzyFinder.Query ("ma"), 10);
        var grown = incremental.search (new Opus.FuzzyFinder.Query ("main"), 10);
        var direct = fresh.search (new Opus.FuzzyFinder.Query ("main"), 10);

        var grown_texts = texts_of (incremental, grown);
        var direct_texts = texts_of (fresh, direct);
        assert_cmpint (grown_texts.length, CompareOperator.EQ, direct_texts.length);
        for (int i = 0; i < direct_texts.length; i++) {
            assert_cmpstr (grown_texts[i], CompareOperator.EQ, direct_texts[i]);
        }
    });

    Test.add_func ("/fuzzy-finder/index/shrinking-query-widens-the-results-again", () => {
        var index = make_index ();

        index.search (new Opus.FuzzyFinder.Query ("main"), 10);
        var widened = index.search (new Opus.FuzzyFinder.Query ("ma"), 10);

        assert_true (widened.length > index.search (new Opus.FuzzyFinder.Query ("main"), 10).length);
    });

    Test.add_func ("/fuzzy-finder/index/appended-candidates-are-searchable-after-a-grown-query", () => {
        var index = make_index ();
        index.search (new Opus.FuzzyFinder.Query ("ma"), 10);

        index.append ({ "docs/manual.md" });
        var matches = index.search (new Opus.FuzzyFinder.Query ("man"), 10);

        var texts = texts_of (index, matches);
        bool found = false;
        foreach (var text in texts) {
            found = found || text == "docs/manual.md";
        }
        assert_true (found);
    });

    Test.add_func ("/fuzzy-finder/index/replace-direct-children-swaps-one-directory-level", () => {
        var index = make_index ();

        index.replace_direct_children ("src/", { "src/document.vala" });

        assert_cmpint (index.search (new Opus.FuzzyFinder.Query ("App"), 10).length, CompareOperator.EQ, 0);
        assert_cmpint (index.search (new Opus.FuzzyFinder.Query ("document"), 10).length, CompareOperator.EQ, 1);
        assert_cmpint (index.search (new Opus.FuzzyFinder.Query ("src/models/file-tree"), 10).length, CompareOperator.EQ, 1);
    });

    Test.add_func ("/fuzzy-finder/index/replace-direct-children-of-the-root", () => {
        var index = make_index ();

        index.replace_direct_children ("", { "CHANGELOG.md" });

        assert_cmpint (index.search (new Opus.FuzzyFinder.Query ("readme"), 10).length, CompareOperator.EQ, 0);
        assert_cmpint (index.search (new Opus.FuzzyFinder.Query ("changelog"), 10).length, CompareOperator.EQ, 1);
        assert_cmpint (index.search (new Opus.FuzzyFinder.Query ("App"), 10).length, CompareOperator.EQ, 1);
    });

    Test.add_func ("/fuzzy-finder/index/cancelled-search-returns-null", () => {
        var index = new Opus.FuzzyFinder.Index ();
        var many = new string[3000];
        for (int i = 0; i < many.length; i++) {
            many[i] = "dir/file-%d.txt".printf (i);
        }
        index.set_candidates (many);
        var cancellable = new Cancellable ();
        cancellable.cancel ();

        var matches = index.search (new Opus.FuzzyFinder.Query ("file"), 10, cancellable);

        assert_null (matches);
    });

    return Test.run ();
}
