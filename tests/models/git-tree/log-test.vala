// Same tmpdir-fixture pattern as tests/models/git-scope: a real `git init` per test.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-tree-test-XXXXXX");
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
    launcher.spawnv (argv).wait ();
}

private void init_repo (string root_path) throws Error {
    run_git (root_path, { "init", "-q", "-b", "main" });
    run_git (root_path, { "config", "user.email", "test@opus.dev" });
    run_git (root_path, { "config", "user.name", "Opus Test" });
}

/** A commit touching `name` — returns nothing; the log is how tests read hashes back. */
private void commit_file (string root_path, string name, string message) throws Error {
    FileUtils.set_contents (Path.build_filename (root_path, name), message);
    run_git (root_path, { "add", name });
    run_git (root_path, { "commit", "-q", "-m", message });
}

private GitTree.Commit? by_subject (GenericArray<GitTree.Commit> commits, string subject) {
    for (uint i = 0; i < commits.length; i++) {
        if (commits[i].subject == subject) {
            return commits[i];
        }
    }
    return null;
}

private void assert_split (string subject, string branch, string message) {
    string got_branch, got_message;
    GitTree.Stash.split_subject (subject, out got_branch, out got_message);
    assert (got_branch == branch && got_message == message);
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-tree-log/reads-every-field-of-a-commit", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "a");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "add: a.txt\n\nWhy it exists.\nMore." });
            run_git (root_path, { "tag", "v1" });

            var commits = GitTree.Log.run (root_path);

            assert (commits != null && commits.length == 1);
            var c = commits[0];
            assert (c.hash.length == 40 && c.short_hash.length == 7);
            assert (c.parents.length == 0);
            assert (c.author == "Opus Test" && c.email == "test@opus.dev");
            assert (c.timestamp > 1600000000);
            assert (c.subject == "add: a.txt");
            assert (c.body_first_line == "Why it exists.");
            assert (c.is_head);
            assert (c.refs.length == 2);
            assert (c.refs[0].name == "main" && c.refs[0].is_head);
            assert (c.refs[1].name == "v1" && c.refs[1].kind == GitTree.RefKind.TAG);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-log/newest-first-with-parents-linked", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "first");
            commit_file (root_path, "a.txt", "second");

            var commits = GitTree.Log.run (root_path);

            assert (commits.length == 2);
            assert (commits[0].subject == "second");
            assert (commits[0].parents.length == 1 && commits[0].parents[0] == commits[1].hash);
            assert (commits[0].body_first_line == "");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-log/covers-every-branch-not-just-head", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            run_git (root_path, { "checkout", "-q", "-b", "side" });
            commit_file (root_path, "b.txt", "on side");
            run_git (root_path, { "checkout", "-q", "main" });

            var commits = GitTree.Log.run (root_path);

            assert (commits.length == 2);
            assert (by_subject (commits, "on side") != null);
            assert (by_subject (commits, "base").is_head);
            assert (!by_subject (commits, "on side").is_head);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-log/leaves-stashes-out", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "dirty");
            run_git (root_path, { "stash" });

            assert (GitTree.Log.run (root_path).length == 1);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-log/limit-and-skip-page-through", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "one");
            commit_file (root_path, "a.txt", "two");
            commit_file (root_path, "a.txt", "three");

            var page = GitTree.Log.run (root_path, 2, 1);

            assert (page.length == 2);
            assert (page[0].subject == "two" && page[1].subject == "one");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-log/a-repository-with-no-commits-is-empty-not-null", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var commits = GitTree.Log.run (root_path);
            assert (commits != null && commits.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-log/outside-a-repository-is-null", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var elsewhere = make_tmp_dir ();
            assert (GitTree.Log.run (elsewhere) == null);
            remove_recursive (elsewhere);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-log/a-detached-head-is-marked-without-a-ref", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "one");
            commit_file (root_path, "a.txt", "two");
            run_git (root_path, { "checkout", "-q", "HEAD~1" });

            var commits = GitTree.Log.run (root_path);

            assert (by_subject (commits, "one").is_head);
            assert (!by_subject (commits, "two").is_head);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-log/stashes-list-newest-first-with-their-base-and-cleaned-message", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "first change");
            run_git (root_path, { "stash", "push", "-m", "my note" });
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "second change");
            run_git (root_path, { "stash" });
            var head = GitTree.Log.run (root_path)[0];

            var stashes = GitTree.Log.stashes (root_path);

            assert (stashes.length == 2);
            assert (stashes[0].name == "stash@{0}" && stashes[1].name == "stash@{1}");
            assert (stashes[0].base_hash == head.hash && stashes[1].base_hash == head.hash);
            assert (stashes[0].branch == "main");
            assert (stashes[0].message.has_suffix ("base")); // "WIP on main: <hash> base"
            assert (stashes[1].message == "my note" && stashes[1].branch == "main");
            assert (stashes[0].timestamp >= stashes[1].timestamp);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-log/no-stashes-is-empty-not-null", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");

            var stashes = GitTree.Log.stashes (root_path);

            assert (stashes != null && stashes.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-log/stash-subjects-split-into-branch-and-message", () => {
        assert_split ("WIP on main: 1a2b3c4 add: thing", "main", "1a2b3c4 add: thing");
        assert_split ("On rc/0.3.0: rc/0.3.0: feature", "rc/0.3.0", "rc/0.3.0: feature");
        assert_split ("custom text", "", "custom text");
        assert_split ("On nothing", "", "On nothing");
    });

    return Test.run ();
}
