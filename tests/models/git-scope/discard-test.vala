// Same tmpdir-fixture pattern as stage-test.vala: a real `git init` per
// test, since the thing under test is a real git mutation —
// GitScope.WorkingTree.run() is how each test checks the result stuck.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-scope-discard-test-XXXXXX");
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

private bool has_change (GenericArray<GitScope.Change> changes, string path, GitScope.ChangeKind kind) {
    for (uint i = 0; i < changes.length; i++) {
        if (changes[i].path == path && changes[i].kind == kind) {
            return true;
        }
    }
    return false;
}

private void init_conflict (string root_path) throws Error {
    init_repo (root_path);
    commit_file (root_path, "a.txt", "base\n", "base");
    run_git (root_path, { "checkout", "-q", "-b", "side" });
    commit_file (root_path, "a.txt", "theirs\n", "side");
    run_git (root_path, { "checkout", "-q", "main" });
    commit_file (root_path, "a.txt", "ours\n", "main");
    run_git (root_path, { "merge", "side" });
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-scope-discard/restores-a-tracked-edit", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "add a.txt" });
            FileUtils.set_contents (path, "hello world");

            var changes = new GenericArray<GitScope.Change> ();
            changes.add (new GitScope.Change (path, GitScope.ChangeKind.MODIFIED));
            GitScope.Discard.run (root_path, changes);

            string contents;
            FileUtils.get_contents (path, out contents);
            assert (contents == "hello");
            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree != null);
            assert (tree.unstaged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-discard/deletes-an-untracked-file", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");

            var changes = new GenericArray<GitScope.Change> ();
            changes.add (new GitScope.Change (path, GitScope.ChangeKind.UNTRACKED));
            GitScope.Discard.run (root_path, changes);

            assert (!FileUtils.test (path, FileTest.EXISTS));
            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree != null);
            assert (tree.unstaged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-discard/handles-a-tracked-and-an-untracked-change-together", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var tracked_path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (tracked_path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "add a.txt" });
            FileUtils.set_contents (tracked_path, "hello world");
            var untracked_path = Path.build_filename (root_path, "b.txt");
            FileUtils.set_contents (untracked_path, "new file");

            var changes = new GenericArray<GitScope.Change> ();
            changes.add (new GitScope.Change (tracked_path, GitScope.ChangeKind.MODIFIED));
            changes.add (new GitScope.Change (untracked_path, GitScope.ChangeKind.UNTRACKED));
            GitScope.Discard.run (root_path, changes);

            string contents;
            FileUtils.get_contents (tracked_path, out contents);
            assert (contents == "hello");
            assert (!FileUtils.test (untracked_path, FileTest.EXISTS));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-discard/restores-a-deleted-tracked-file", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "add a.txt" });
            FileUtils.remove (path);

            var changes = new GenericArray<GitScope.Change> ();
            changes.add (new GitScope.Change (path, GitScope.ChangeKind.DELETED));
            GitScope.Discard.run (root_path, changes);

            assert (FileUtils.test (path, FileTest.EXISTS));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-discard/with-no-changes-is-a-no-op-success", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);

            GitScope.Discard.run (root_path, new GenericArray<GitScope.Change> ());
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-discard/outside-a-repository-fails", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");

            var changes = new GenericArray<GitScope.Change> ();
            changes.add (new GitScope.Change (path, GitScope.ChangeKind.UNTRACKED));
            try {
                GitScope.Discard.run (root_path, changes);
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

    Test.add_func ("/git-scope-discard/a-partially-staged-file-goes-back-to-its-staged-version-not-head", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "head\n", "add a.txt");
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "staged\n");
            run_git (root_path, { "add", "a.txt" });
            FileUtils.set_contents (path, "staged\nplus unstaged\n");

            var changes = new GenericArray<GitScope.Change> ();
            changes.add (new GitScope.Change (path, GitScope.ChangeKind.MODIFIED));
            GitScope.Discard.run (root_path, changes);

            assert (read_file (path) == "staged\n");
            var tree = GitScope.WorkingTree.run (root_path);
            assert (has_change (tree.staged, path, GitScope.ChangeKind.MODIFIED));
            assert (tree.unstaged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-discard/deletes-an-untracked-directory-whole", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var dir = Path.build_filename (root_path, "scratch");
            DirUtils.create_with_parents (dir, 0755);
            FileUtils.set_contents (Path.build_filename (dir, "a.txt"), "a");
            FileUtils.set_contents (Path.build_filename (dir, "b.txt"), "b");

            var changes = new GenericArray<GitScope.Change> ();
            changes.add (new GitScope.Change (dir, GitScope.ChangeKind.UNTRACKED));
            GitScope.Discard.run (root_path, changes);

            assert (!FileUtils.test (dir, FileTest.EXISTS));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-discard/a-tracked-failure-stops-before-any-untracked-file-is-deleted", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "hello", "add a.txt");
            var untracked = Path.build_filename (root_path, "keep-me.txt");
            FileUtils.set_contents (untracked, "precious");
            var gone = Path.build_filename (root_path, "never-existed.txt");

            var changes = new GenericArray<GitScope.Change> ();
            changes.add (new GitScope.Change (gone, GitScope.ChangeKind.MODIFIED));
            changes.add (new GitScope.Change (untracked, GitScope.ChangeKind.UNTRACKED));
            assert_git_refuses (() => GitScope.Discard.run (root_path, changes), "did not match");

            assert (FileUtils.test (untracked, FileTest.EXISTS));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-discard/leaves-other-changed-files-alone", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "a", "add a.txt");
            commit_file (root_path, "b.txt", "b", "add b.txt");
            var a = Path.build_filename (root_path, "a.txt");
            var b = Path.build_filename (root_path, "b.txt");
            FileUtils.set_contents (a, "a changed");
            FileUtils.set_contents (b, "b changed");

            var changes = new GenericArray<GitScope.Change> ();
            changes.add (new GitScope.Change (a, GitScope.ChangeKind.MODIFIED));
            GitScope.Discard.run (root_path, changes);

            assert (read_file (a) == "a");
            assert (read_file (b) == "b changed");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-discard/a-conflicted-path-is-refused-not-silently-resolved", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            var path = Path.build_filename (root_path, "a.txt");

            var changes = new GenericArray<GitScope.Change> ();
            changes.add (new GitScope.Change (path, GitScope.ChangeKind.CONFLICT));
            assert_git_refuses (() => GitScope.Discard.run (root_path, changes), "unmerged");

            assert (GitScope.WorkingTree.run (root_path).conflicts.length == 1);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
