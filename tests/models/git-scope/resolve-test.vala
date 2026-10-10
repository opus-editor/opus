// Same tmpdir-fixture pattern as stage-test.vala: a real `git init` (and a real merge conflict) per test.

// Same tmpdir-fixture pattern as working-tree-test.vala: a real `git
// init` per test, since the thing under test is a real git mutation —
// GitScope.WorkingTree.run() is how each test checks the result stuck.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-scope-resolve-test-XXXXXX");
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

private void commit_file (string root_path, string name, string contents, string message) throws Error {
    FileUtils.set_contents (Path.build_filename (root_path, name), contents);
    run_git (root_path, { "add", name });
    run_git (root_path, { "commit", "-q", "-m", message });
}

/** a.txt modified on main, deleted on side, merge parked: `UD`. */
private void init_deleted_by_them (string root_path) throws Error {
    init_repo (root_path);
    commit_file (root_path, "a.txt", "base\n", "base");
    run_git (root_path, { "checkout", "-q", "-b", "side" });
    run_git (root_path, { "rm", "-q", "a.txt" });
    run_git (root_path, { "commit", "-q", "-m", "side deletes" });
    run_git (root_path, { "checkout", "-q", "main" });
    commit_file (root_path, "a.txt", "ours\n", "main edits");
    run_git (root_path, { "merge", "side" });
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-scope-resolve/accept-ours-keeps-head-side-and-stages", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            var path = Path.build_filename (root_path, "a.txt");

            GitScope.Resolve.accept_ours (root_path, { path });

            assert (read_file (path) == "ours\n");
            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree.conflicts.length == 0);
            assert (tree.staged.length == 0); // same as HEAD: nothing to commit for this path
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-resolve/accept-theirs-takes-incoming-side-and-stages", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            var path = Path.build_filename (root_path, "a.txt");

            GitScope.Resolve.accept_theirs (root_path, { path });

            assert (read_file (path) == "theirs\n");
            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree.conflicts.length == 0);
            assert (has_change (tree.staged, path, GitScope.ChangeKind.MODIFIED));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-resolve/keep-stages-the-file-as-it-is", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "resolved by hand\n");

            GitScope.Resolve.keep (root_path, { path });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree.conflicts.length == 0);
            assert (has_change (tree.staged, path, GitScope.ChangeKind.MODIFIED));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-resolve/remove-deletes-the-file-and-stages-the-deletion", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            var path = Path.build_filename (root_path, "a.txt");

            GitScope.Resolve.remove (root_path, { path });

            assert (!FileUtils.test (path, FileTest.EXISTS));
            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree.conflicts.length == 0);
            assert (has_change (tree.staged, path, GitScope.ChangeKind.DELETED));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-resolve/has-conflict-markers-sees-gits-markers", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            var path = Path.build_filename (root_path, "a.txt");

            assert (GitScope.Resolve.has_conflict_markers (path));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-resolve/has-conflict-markers-is-false-once-resolved", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "<<< not a marker\n=== nor this\n");

            assert (!GitScope.Resolve.has_conflict_markers (path));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-resolve/has-conflict-markers-is-false-for-a-missing-file", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            assert (!GitScope.Resolve.has_conflict_markers (Path.build_filename (root_path, "nope.txt")));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-resolve/keep-on-a-file-deleted-by-them-keeps-our-version", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_deleted_by_them (root_path);
            var path = Path.build_filename (root_path, "a.txt");

            GitScope.Resolve.keep (root_path, { path });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree.conflicts.length == 0);
            assert (read_file (path) == "ours\n");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-resolve/remove-on-a-file-deleted-by-them-takes-the-deletion", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_deleted_by_them (root_path);
            var path = Path.build_filename (root_path, "a.txt");

            GitScope.Resolve.remove (root_path, { path });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree.conflicts.length == 0);
            assert (!FileUtils.test (path, FileTest.EXISTS));
            assert (has_change (tree.staged, path, GitScope.ChangeKind.DELETED));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-resolve/accept-theirs-on-a-file-they-deleted-is-refused", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_deleted_by_them (root_path);
            var path = Path.build_filename (root_path, "a.txt");

            assert_git_refuses (() => GitScope.Resolve.accept_theirs (root_path, { path }), "their version");

            assert (GitScope.WorkingTree.run (root_path).conflicts.length == 1);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-resolve/accept-resolves-several-files-at-once", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base\n", "base a");
            commit_file (root_path, "b.txt", "base\n", "base b");
            run_git (root_path, { "checkout", "-q", "-b", "side" });
            commit_file (root_path, "a.txt", "theirs\n", "side a");
            commit_file (root_path, "b.txt", "theirs\n", "side b");
            run_git (root_path, { "checkout", "-q", "main" });
            commit_file (root_path, "a.txt", "ours\n", "main a");
            commit_file (root_path, "b.txt", "ours\n", "main b");
            run_git (root_path, { "merge", "side" });
            var a = Path.build_filename (root_path, "a.txt");
            var b = Path.build_filename (root_path, "b.txt");

            GitScope.Resolve.accept_theirs (root_path, { a, b });

            assert (GitScope.WorkingTree.run (root_path).conflicts.length == 0);
            assert (read_file (a) == "theirs\n");
            assert (read_file (b) == "theirs\n");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-resolve/has-conflict-markers-sees-markers-with-crlf-line-endings", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "<<<<<<< HEAD\r\nours\r\n=======\r\ntheirs\r\n>>>>>>> side\r\n");

            assert (GitScope.Resolve.has_conflict_markers (path));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-resolve/has-conflict-markers-ignores-lookalikes", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "<<<<<<<no space\n========\n>>>>>>>\n <<<<<<< indented\n");

            assert (!GitScope.Resolve.has_conflict_markers (path));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-resolve/has-conflict-markers-sees-a-marker-deep-in-the-file", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path = Path.build_filename (root_path, "a.txt");
            var text = new StringBuilder ();
            for (int i = 0; i < 500; i++) {
                text.append ("line %d\n".printf (i));
            }
            text.append ("=======\n");
            FileUtils.set_contents (path, text.str);

            assert (GitScope.Resolve.has_conflict_markers (path));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
