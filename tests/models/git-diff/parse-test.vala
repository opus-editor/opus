// Pure logic, no subprocess/git involved: feeds fixed unified-diff
// strings directly into GitDiff.Engine.parse_unified_diff (internal,
// so this test file must be compiled as part of the same package —
// meson links opus_model_sources directly, same as every other model
// test).

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-diff-parse/pure-addition", () => {
        var hunks = GitDiff.Engine.parse_unified_diff ("@@ -0,0 +1,3 @@\n+a\n+b\n+c\n");
        assert (hunks.length == 1);
        assert (hunks[0].kind == GitDiff.HunkKind.ADDED);
        assert (hunks[0].current_start == 0);
        assert (hunks[0].current_count == 3);
    });

    Test.add_func ("/git-diff-parse/pure-removal", () => {
        var hunks = GitDiff.Engine.parse_unified_diff ("@@ -5,2 +4,0 @@\n-a\n-b\n");
        assert (hunks.length == 1);
        assert (hunks[0].kind == GitDiff.HunkKind.REMOVED);
        assert (hunks[0].current_start == 4);
        assert (hunks[0].current_count == 0);
    });

    Test.add_func ("/git-diff-parse/a-change", () => {
        var hunks = GitDiff.Engine.parse_unified_diff ("@@ -3,1 +3,2 @@\n-old\n+new1\n+new2\n");
        assert (hunks.length == 1);
        assert (hunks[0].kind == GitDiff.HunkKind.CHANGED);
        assert (hunks[0].current_start == 2);
        assert (hunks[0].current_count == 2);
    });

    Test.add_func ("/git-diff-parse/omitted-count-defaults-to-one", () => {
        var hunks = GitDiff.Engine.parse_unified_diff ("@@ -1 +1 @@\n-old\n+new\n");
        assert (hunks.length == 1);
        assert (hunks[0].kind == GitDiff.HunkKind.CHANGED);
        assert (hunks[0].current_start == 0);
        assert (hunks[0].current_count == 1);
    });

    Test.add_func ("/git-diff-parse/multiple-hunks-in-one-diff", () => {
        var hunks = GitDiff.Engine.parse_unified_diff (
            "@@ -0,0 +1,1 @@\n+a\n@@ -10,1 +11,0 @@\n-b\n"
        );
        assert (hunks.length == 2);
        assert (hunks[0].kind == GitDiff.HunkKind.ADDED);
        assert (hunks[1].kind == GitDiff.HunkKind.REMOVED);
    });

    Test.add_func ("/git-diff-parse/no-hunk-headers-yields-empty", () => {
        var hunks = GitDiff.Engine.parse_unified_diff ("diff --git a/x b/x\nindex 000..111 100644\n");
        assert (hunks.length == 0);
    });

    return Test.run ();
}
