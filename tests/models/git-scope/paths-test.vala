int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-scope-paths/a-path-is-under-its-own-ancestor", () => {
        assert (GitScope.Paths.is_at_or_under ("/repo/src/models/a.vala", "/repo/src"));
    });

    Test.add_func ("/git-scope-paths/a-path-is-at-itself", () => {
        assert (GitScope.Paths.is_at_or_under ("/repo/src", "/repo/src"));
    });

    Test.add_func ("/git-scope-paths/a-sibling-sharing-a-name-prefix-is-not-under", () => {
        assert (!GitScope.Paths.is_at_or_under ("/repo/src-old/a.vala", "/repo/src"));
    });

    Test.add_func ("/git-scope-paths/an-ancestor-is-not-under-its-descendant", () => {
        assert (!GitScope.Paths.is_at_or_under ("/repo", "/repo/src"));
    });

    Test.add_func ("/git-scope-paths/siblings-widen-to-their-parent", () => {
        var ancestor = GitScope.Paths.common_ancestor ("/repo/src/models", "/repo/src/views");

        assert (ancestor == "/repo/src");
    });

    Test.add_func ("/git-scope-paths/a-parent-and-its-descendant-widen-to-the-parent", () => {
        var ancestor = GitScope.Paths.common_ancestor ("/repo/src/models/a.vala", "/repo/src");

        assert (ancestor == "/repo/src");
    });

    Test.add_func ("/git-scope-paths/a-descendant-does-not-narrow-its-ancestor", () => {
        var ancestor = GitScope.Paths.common_ancestor ("/repo/src", "/repo/src/models/a.vala");

        assert (ancestor == "/repo/src");
    });

    Test.add_func ("/git-scope-paths/the-same-path-stays-as-it-is", () => {
        var ancestor = GitScope.Paths.common_ancestor ("/repo/src", "/repo/src");

        assert (ancestor == "/repo/src");
    });

    Test.add_func ("/git-scope-paths/siblings-sharing-a-name-prefix-widen-to-their-parent", () => {
        var ancestor = GitScope.Paths.common_ancestor ("/repo/src", "/repo/src-old");

        assert (ancestor == "/repo");
    });

    Test.add_func ("/git-scope-paths/unrelated-paths-widen-to-the-filesystem-root", () => {
        var ancestor = GitScope.Paths.common_ancestor ("/repo/src", "/elsewhere");

        assert (ancestor == "/");
    });

    return Test.run ();
}
