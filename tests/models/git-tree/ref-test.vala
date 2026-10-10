// Same tmpdir-fixture pattern as tests/models/git-scope: a real `git init` per test.

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-tree-ref/sorts-head-then-local-remote-tag", () => {
        var refs = GitTree.Ref.parse ("tag: refs/tags/v0.2.0, refs/remotes/origin/main, HEAD -> refs/heads/main, refs/heads/rc/0.2.0");

        assert (refs.length == 4);
        assert (refs[0].name == "main" && refs[0].kind == GitTree.RefKind.LOCAL && refs[0].is_head);
        assert (refs[1].name == "rc/0.2.0" && refs[1].kind == GitTree.RefKind.LOCAL && !refs[1].is_head);
        assert (refs[2].name == "origin/main" && refs[2].kind == GitTree.RefKind.REMOTE && !refs[2].is_head);
        assert (refs[3].name == "v0.2.0" && refs[3].kind == GitTree.RefKind.TAG);
    });

    Test.add_func ("/git-tree-ref/a-detached-head-is-not-a-ref", () => {
        assert (GitTree.Ref.parse ("HEAD").length == 0);
        var refs = GitTree.Ref.parse ("HEAD, refs/tags/v1");
        assert (refs.length == 1 && refs[0].name == "v1");
    });

    Test.add_func ("/git-tree-ref/a-remotes-own-head-pointer-is-not-a-ref", () => {
        var refs = GitTree.Ref.parse ("refs/remotes/origin/HEAD -> refs/remotes/origin/main, refs/remotes/origin/main, refs/heads/main");

        assert (refs.length == 2);
        assert (refs[0].name == "main");
        assert (refs[1].name == "origin/main" && refs[1].kind == GitTree.RefKind.REMOTE);
    });

    Test.add_func ("/git-tree-ref/empty-and-stash-decorations-give-nothing", () => {
        assert (GitTree.Ref.parse ("").length == 0);
        assert (GitTree.Ref.parse ("refs/stash").length == 0);
    });

    return Test.run ();
}
