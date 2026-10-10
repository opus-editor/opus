// Same tmpdir-fixture pattern as working-tree-test.vala: a real `git
// init` per test, since the thing under test is a real git mutation —
// GitScope.WorkingTree.run() is how each test checks the result stuck.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-scope-stage-test-XXXXXX");
}

private void remove_recursive (string path) {
    if (FileUtils.test (path, FileTest.IS_DIR) && !FileUtils.test (path, FileTest.IS_SYMLINK)) {
        Dir dir;
        try {
            dir = Dir.open (path);
        } catch (Error e) {
            return;
        }
        string? entry;
        while ((entry = dir.read_name ()) != null) {
            remove_recursive (Path.build_filename (path, entry));
        }
        DirUtils.remove (path);
    } else {
        FileUtils.remove (path);
    }
}

private void run_git (string root_path, string[] args) throws Error {
    string[] argv = { "git" };
    foreach (var arg in args) {
        argv += arg;
    }
    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
    launcher.set_cwd (root_path);
    var process = launcher.spawnv (argv);
    process.wait ();
}

private void init_repo (string root_path) throws Error {
    run_git (root_path, { "init", "-q", "-b", "main" });
    run_git (root_path, { "config", "user.email", "test@opus.dev" });
    run_git (root_path, { "config", "user.name", "Opus Test" });
}

private bool has_change (GenericArray<GitScope.Change> changes, string path, GitScope.ChangeKind kind) {
    for (uint i = 0; i < changes.length; i++) {
        if (changes[i].path == path && changes[i].kind == kind) {
            return true;
        }
    }
    return false;
}

private void commit_file (string root_path, string name, string contents, string message) throws Error {
    FileUtils.set_contents (Path.build_filename (root_path, name), contents);
    run_git (root_path, { "add", name });
    run_git (root_path, { "commit", "-q", "-m", message });
}

private string read_file (string path) throws Error {
    string contents;
    FileUtils.get_contents (path, out contents);
    return contents;
}

/** Runs `step` expecting git to refuse — the FAILED error, with `needle` somewhere in git's own words. */
private delegate void GitStep () throws GitScope.CommandError;
private void assert_git_refuses (GitStep step, string needle) {
    try {
        step ();
        assert_not_reached ();
    } catch (GitScope.CommandError e) {
        assert (e is GitScope.CommandError.FAILED);
        if (!e.message.contains (needle)) {
            error ("expected \"%s\" in: %s", needle, e.message);
        }
    }
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-scope-stage/add-stages-an-untracked-file", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");

            GitScope.Stage.add (root_path, { path });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree != null);
            assert (has_change (tree.staged, path, GitScope.ChangeKind.ADDED));
            assert (tree.unstaged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-stage/add-stages-an-unstaged-edit", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "add a.txt" });
            FileUtils.set_contents (path, "hello world");

            GitScope.Stage.add (root_path, { path });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree != null);
            assert (has_change (tree.staged, path, GitScope.ChangeKind.MODIFIED));
            assert (tree.unstaged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-stage/unstage-moves-a-staged-change-back", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });

            GitScope.Stage.unstage (root_path, { path });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree != null);
            assert (has_change (tree.unstaged, path, GitScope.ChangeKind.UNTRACKED));
            assert (tree.staged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-stage/unstage-of-a-staged-edit-in-a-committed-repo-uses-restore", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "add a.txt" });
            FileUtils.set_contents (path, "hello world");
            run_git (root_path, { "add", "a.txt" });

            GitScope.Stage.unstage (root_path, { path });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree != null);
            assert (has_change (tree.unstaged, path, GitScope.ChangeKind.MODIFIED));
            assert (tree.staged.length == 0);
            // restore --staged leaves the worktree edit untouched — only the index changed.
            string contents;
            FileUtils.get_contents (path, out contents);
            assert (contents == "hello world");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-stage/add-with-no-paths-is-a-no-op-success", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);

            GitScope.Stage.add (root_path, {});
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-stage/add-outside-a-repository-fails", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");

            try {
                GitScope.Stage.add (root_path, { path });
                assert_not_reached ();
            } catch (GitScope.CommandError e) {
                assert (e is GitScope.CommandError.FAILED);
                assert (e.message.contains ("not a git repository"));
            }
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-stage/unstage-of-a-rename-with-both-paths-leaves-nothing-staged", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var old_path = Path.build_filename (root_path, "a.txt");
            var new_path = Path.build_filename (root_path, "b.txt");
            FileUtils.set_contents (old_path, "same contents, moved");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "add a.txt" });
            run_git (root_path, { "mv", "a.txt", "b.txt" });

            GitScope.Stage.unstage (root_path, { new_path, old_path });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree.staged.length == 0);
            assert (has_change (tree.unstaged, old_path, GitScope.ChangeKind.DELETED));
            assert (has_change (tree.unstaged, new_path, GitScope.ChangeKind.UNTRACKED));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-stage/add-of-a-deleted-tracked-file-stages-the-deletion", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "hello", "add a.txt");
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.remove (path);

            GitScope.Stage.add (root_path, { path });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (has_change (tree.staged, path, GitScope.ChangeKind.DELETED));
            assert (tree.unstaged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-stage/unstage-of-a-staged-deletion-brings-the-index-entry-back", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "hello", "add a.txt");
            var path = Path.build_filename (root_path, "a.txt");
            run_git (root_path, { "rm", "-q", "a.txt" });

            GitScope.Stage.unstage (root_path, { path });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree.staged.length == 0);
            assert (has_change (tree.unstaged, path, GitScope.ChangeKind.DELETED));
            assert (!FileUtils.test (path, FileTest.EXISTS)); // the worktree is never touched
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-stage/unstage-of-a-new-file-in-a-committed-repo-makes-it-untracked", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "hello", "add a.txt");
            var path = Path.build_filename (root_path, "b.txt");
            FileUtils.set_contents (path, "new");
            run_git (root_path, { "add", "b.txt" });

            GitScope.Stage.unstage (root_path, { path });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree.staged.length == 0);
            assert (has_change (tree.unstaged, path, GitScope.ChangeKind.UNTRACKED));
            assert (read_file (path) == "new");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-stage/add-stages-several-paths-at-once-and-nothing-else", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var a = Path.build_filename (root_path, "a.txt");
            var b = Path.build_filename (root_path, "b.txt");
            var c = Path.build_filename (root_path, "c.txt");
            FileUtils.set_contents (a, "a");
            FileUtils.set_contents (b, "b");
            FileUtils.set_contents (c, "c");

            GitScope.Stage.add (root_path, { a, c });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (has_change (tree.staged, a, GitScope.ChangeKind.ADDED));
            assert (has_change (tree.staged, c, GitScope.ChangeKind.ADDED));
            assert (has_change (tree.unstaged, b, GitScope.ChangeKind.UNTRACKED));
            assert (tree.staged.length == 2);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-stage/add-of-a-path-that-no-longer-exists-fails-and-stages-nothing", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var a = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (a, "a");
            var gone = Path.build_filename (root_path, "gone.txt");

            assert_git_refuses (() => GitScope.Stage.add (root_path, { a, gone }), "did not match");

            assert (GitScope.WorkingTree.run (root_path).staged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-stage/add-of-a-file-in-a-subdirectory-keeps-its-path", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            DirUtils.create_with_parents (Path.build_filename (root_path, "src", "deep"), 0755);
            var path = Path.build_filename (root_path, "src", "deep", "a.txt");
            FileUtils.set_contents (path, "a");

            GitScope.Stage.add (root_path, { path });

            assert (has_change (GitScope.WorkingTree.run (root_path).staged, path, GitScope.ChangeKind.ADDED));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
