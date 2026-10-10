// Same tmpdir-fixture pattern as stage-test.vala: a real `git init` (and a real merge conflict) per test.

// Same tmpdir-fixture pattern as working-tree-test.vala: a real `git
// init` per test, since the thing under test is a real git mutation —
// GitScope.WorkingTree.run() is how each test checks the result stuck.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-scope-operation-test-XXXXXX");
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

/** A real merge conflict on a.txt: "base" committed on main, then both main and side rewrite its one line. The merge stops with MERGE_HEAD parked. */
private void init_conflict (string root_path) throws Error {
    init_repo (root_path);
    FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "base\n");
    run_git (root_path, { "add", "a.txt" });
    run_git (root_path, { "commit", "-q", "-m", "base" });
    run_git (root_path, { "checkout", "-q", "-b", "side" });
    FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "theirs\n");
    run_git (root_path, { "commit", "-q", "-am", "side" });
    run_git (root_path, { "checkout", "-q", "main" });
    FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "ours\n");
    run_git (root_path, { "commit", "-q", "-am", "main" });
    run_git (root_path, { "merge", "side" });
}

private string read_file (string path) throws Error {
    string contents;
    FileUtils.get_contents (path, out contents);
    return contents;
}

private bool merge_parked (string root_path) {
    return FileUtils.test (Path.build_filename (root_path, ".git", "MERGE_HEAD"), FileTest.EXISTS);
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

private string last_subject (string root_path) throws Error {
    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
    launcher.set_cwd (root_path);
    string subject;
    launcher.spawnv ({ "git", "log", "-1", "--format=%s" }).communicate_utf8 (null, null, out subject, null);
    return subject.strip ();
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-scope-operation/commit-records-the-staged-changes", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });

            GitScope.Operation.commit (root_path, "first");

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree.staged.length == 0);
            assert (tree.unstaged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-operation/commit-closes-a-parked-merge", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            GitScope.Resolve.accept_theirs (root_path, { Path.build_filename (root_path, "a.txt") });

            GitScope.Operation.commit (root_path, "merge side");

            assert (!merge_parked (root_path));
            assert (GitScope.WorkingTree.run (root_path).operation == GitScope.OperationKind.NONE);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-operation/commit-with-nothing-staged-fails", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);

            try {
                GitScope.Operation.commit (root_path, "empty");
                assert_not_reached ();
            } catch (GitScope.CommandError e) {
                assert (e is GitScope.CommandError.FAILED);
            }
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-operation/abort-drops-a-parked-merge", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            var path = Path.build_filename (root_path, "a.txt");

            GitScope.Operation.abort (root_path, GitScope.OperationKind.MERGE);

            assert (!merge_parked (root_path));
            assert (read_file (path) == "ours\n");
            assert (GitScope.WorkingTree.run (root_path).conflicts.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-operation/resume-continues-a-parked-cherry-pick-with-the-given-message", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            run_git (root_path, { "merge", "--abort" });
            run_git (root_path, { "cherry-pick", "side" }); // same one-line clash, parked as a cherry-pick
            var path = Path.build_filename (root_path, "a.txt");
            assert (GitScope.WorkingTree.run (root_path).operation == GitScope.OperationKind.CHERRY_PICK);
            GitScope.Resolve.accept_theirs (root_path, { path });

            GitScope.Operation.resume (root_path, GitScope.OperationKind.CHERRY_PICK, "picked side");

            assert (GitScope.WorkingTree.run (root_path).operation == GitScope.OperationKind.NONE);
            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
            launcher.set_cwd (root_path);
            string subject;
            launcher.spawnv ({ "git", "log", "-1", "--format=%s" }).communicate_utf8 (null, null, out subject, null);
            assert (subject.strip () == "picked side");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-operation/resume-and-abort-do-nothing-for-none", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);

            GitScope.Operation.resume (root_path, GitScope.OperationKind.NONE, "x");
            GitScope.Operation.abort (root_path, GitScope.OperationKind.NONE);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-operation/resume-continues-a-parked-rebase", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            run_git (root_path, { "merge", "--abort" });
            run_git (root_path, { "rebase", "side" });
            var path = Path.build_filename (root_path, "a.txt");
            GitScope.Resolve.accept_theirs (root_path, { path }); // during a rebase "theirs" is the commit being replayed

            GitScope.Operation.resume (root_path, GitScope.OperationKind.REBASE, "main, rebased");

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree.operation == GitScope.OperationKind.NONE);
            assert (tree.conflicts.length == 0);
            assert (last_subject (root_path) == "main, rebased");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-operation/abort-drops-a-parked-rebase", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            run_git (root_path, { "merge", "--abort" });
            run_git (root_path, { "rebase", "side" });

            GitScope.Operation.abort (root_path, GitScope.OperationKind.REBASE);

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree.operation == GitScope.OperationKind.NONE);
            assert (tree.conflicts.length == 0);
            assert (last_subject (root_path) == "main");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-operation/abort-drops-a-parked-revert", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            run_git (root_path, { "merge", "--abort" });
            run_git (root_path, { "revert", "--no-edit", "HEAD~1" });

            GitScope.Operation.abort (root_path, GitScope.OperationKind.REVERT);

            assert (GitScope.WorkingTree.run (root_path).operation == GitScope.OperationKind.NONE);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-operation/resume-with-a-conflict-still-open-is-refused", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            run_git (root_path, { "merge", "--abort" });
            run_git (root_path, { "cherry-pick", "side" });

            assert_git_refuses (() => GitScope.Operation.resume (root_path, GitScope.OperationKind.CHERRY_PICK, "x"), "unmerged");

            assert (GitScope.WorkingTree.run (root_path).operation == GitScope.OperationKind.CHERRY_PICK);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-operation/commit-with-a-conflict-still-open-is-refused", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);

            assert_git_refuses (() => GitScope.Operation.commit (root_path, "too early"), "unmerged");

            assert (merge_parked (root_path));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-operation/commit-keeps-a-multi-line-message-with-quotes", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "hello");
            run_git (root_path, { "add", "a.txt" });

            GitScope.Operation.commit (root_path, "add: \"a.txt\"\n\n- it's the first one");

            assert (last_subject (root_path) == "add: \"a.txt\"");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-operation/a-merge-commit-with-every-conflict-taken-as-ours-is-allowed", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            GitScope.Resolve.accept_ours (root_path, { Path.build_filename (root_path, "a.txt") });
            assert (GitScope.WorkingTree.run (root_path).staged.length == 0); // index equals HEAD

            GitScope.Operation.commit (root_path, "merge side, keeping ours");

            assert (!merge_parked (root_path));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
