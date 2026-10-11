
private string sides (GitDiff.Request r) {
    return "%s -> %s".printf (side (r.left), side (r.right));
}

private string side (GitDiff.Side s) {
    switch (s.kind) {
        case GitDiff.SideKind.EMPTY: return "empty";
        case GitDiff.SideKind.WORKTREE: return "worktree:" + Path.get_basename (s.path);
        default: return "%s:%s".printf (s.revision == "" ? "index" : s.revision, s.path);
    }
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-diff-sides/unstaged-modified-is-index-to-worktree", () => {
        var r = GitDiff.Request.for_working_change ("/r", new GitScope.Change ("/r/a.txt", GitScope.ChangeKind.MODIFIED), "unstaged");
        assert (sides (r) == "index:a.txt -> worktree:a.txt");
        assert (r.title == "a.txt (Working Tree)" && r.is_live);
    });

    Test.add_func ("/git-diff-sides/untracked-is-nothing-to-worktree", () => {
        var r = GitDiff.Request.for_working_change ("/r", new GitScope.Change ("/r/n.txt", GitScope.ChangeKind.UNTRACKED), "unstaged");
        assert (sides (r) == "empty -> worktree:n.txt");
    });

    Test.add_func ("/git-diff-sides/unstaged-deleted-is-index-to-nothing", () => {
        var r = GitDiff.Request.for_working_change ("/r", new GitScope.Change ("/r/a.txt", GitScope.ChangeKind.DELETED), "unstaged");
        assert (sides (r) == "index:a.txt -> empty");
        assert (r.title == "a.txt (Index)");
    });

    Test.add_func ("/git-diff-sides/staged-modified-is-head-to-index", () => {
        var r = GitDiff.Request.for_working_change ("/r", new GitScope.Change ("/r/a.txt", GitScope.ChangeKind.MODIFIED), "staged");
        assert (sides (r) == "HEAD:a.txt -> index:a.txt");
        assert (r.title == "a.txt (Index)" && r.is_live);
    });

    Test.add_func ("/git-diff-sides/staged-added-is-nothing-to-index", () => {
        var r = GitDiff.Request.for_working_change ("/r", new GitScope.Change ("/r/a.txt", GitScope.ChangeKind.ADDED), "staged");
        assert (sides (r) == "empty -> index:a.txt");
    });

    Test.add_func ("/git-diff-sides/staged-deleted-is-head-to-nothing", () => {
        var r = GitDiff.Request.for_working_change ("/r", new GitScope.Change ("/r/a.txt", GitScope.ChangeKind.DELETED), "staged");
        assert (sides (r) == "HEAD:a.txt -> empty");
    });

    Test.add_func ("/git-diff-sides/a-staged-rename-reads-head-at-the-old-path", () => {
        var r = GitDiff.Request.for_working_change ("/r", new GitScope.Change ("/r/new.txt", GitScope.ChangeKind.RENAMED, "", "/r/old.txt"), "staged");
        assert (sides (r) == "HEAD:old.txt -> index:new.txt");
        assert (r.relative_path == "new.txt");
    });

    Test.add_func ("/git-diff-sides/a-commits-file-is-parent-to-commit", () => {
        var r = GitDiff.Request.for_commit_change ("/r", new GitScope.Change ("/r/a.txt", GitScope.ChangeKind.MODIFIED), "abc1234def", "parent99");
        assert (sides (r) == "parent99:a.txt -> abc1234def:a.txt");
        assert (r.title == "a.txt (abc1234)" && !r.is_live);
    });

    Test.add_func ("/git-diff-sides/a-root-commits-file-has-no-left", () => {
        var r = GitDiff.Request.for_commit_change ("/r", new GitScope.Change ("/r/a.txt", GitScope.ChangeKind.ADDED), "abc1234def", null);
        assert (sides (r) == "empty -> abc1234def:a.txt");
    });

    Test.add_func ("/git-diff-sides/a-commits-deleted-file-has-no-right", () => {
        var r = GitDiff.Request.for_commit_change ("/r", new GitScope.Change ("/r/a.txt", GitScope.ChangeKind.DELETED), "abc1234def", "parent99");
        assert (sides (r) == "parent99:a.txt -> empty");
        assert (r.title == "a.txt (parent9)");
    });

    Test.add_func ("/git-diff-sides/the-uri-tells-requests-apart", () => {
        var a = GitDiff.Request.for_working_change ("/r", new GitScope.Change ("/r/a.txt", GitScope.ChangeKind.MODIFIED), "unstaged");
        var b = GitDiff.Request.for_working_change ("/r", new GitScope.Change ("/r/a.txt", GitScope.ChangeKind.MODIFIED), "staged");
        assert (a.uri != b.uri);
        assert (a.uri == GitDiff.Request.for_working_change ("/r", new GitScope.Change ("/r/a.txt", GitScope.ChangeKind.MODIFIED), "unstaged").uri);
    });

    return Test.run ();
}
