// What a real repo's various working-tree states classify as (untracked,
// staged, modified, deleted, renamed, conflicted) — as opposed to
// git-status-run-test.vala, which covers run()/run_async()'s own plumbing.
// Same tmpdir-fixture pattern as find-in-files-search-test.vala.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-status-classify-test-XXXXXX");
}

private void remove_recursive (string path) {
    if (FileUtils.test (path, FileTest.IS_DIR)) {
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

/** Runs a real `git` command in `root_path` for a test fixture's own setup — never the thing under test itself (that's GitStatus's own run()). */
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

/** A fresh repo with committer identity set. */
/** `-b main`: the conflict fixture below checks `main` back out by name — never the machine's own `init.defaultBranch` (unset on CI, `master` by git's default). */
private void init_repo (string root_path) throws Error {
    run_git (root_path, { "init", "-q", "-b", "main" });
    run_git (root_path, { "config", "user.email", "test@opus.dev" });
    run_git (root_path, { "config", "user.name", "Opus Test" });
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-status/untracked-file-is-new", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");

            var status = GitStatus.run (root_path);

            assert (status != null);
            assert (status.status_for (path) == GitFileStatus.NEW);
            assert (status.tooltip_for (path) == "Untracked");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status/staged-new-file-is-still-new", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });

            var status = GitStatus.run (root_path);

            assert (status != null);
            assert (status.status_for (path) == GitFileStatus.NEW);
            assert (status.tooltip_for (path) == "Added");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status/modified-tracked-file-is-modified", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "init" });
            FileUtils.set_contents (path, "hello world");

            var status = GitStatus.run (root_path);

            assert (status != null);
            assert (status.status_for (path) == GitFileStatus.MODIFIED);
            assert (status.tooltip_for (path) == "Modified");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status/committed-unmodified-file-is-none", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "init" });

            var status = GitStatus.run (root_path);

            assert (status != null);
            assert (status.status_for (path) == GitFileStatus.NONE);
            assert (status.tooltip_for (path) == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status/deleted-tracked-file-reports-none", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "init" });
            FileUtils.remove (path);

            var status = GitStatus.run (root_path);

            assert (status != null);
            assert (status.status_for (path) == GitFileStatus.NONE);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status/staged-then-deleted-file-reports-none", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            FileUtils.remove (path);

            var status = GitStatus.run (root_path);

            // Real porcelain line here is "AD a.txt" — staged as added,
            // then deleted from the worktree before ever being committed.
            // The file is gone; classify() must not let the "A" column
            // win over that.
            assert (status != null);
            assert (status.status_for (path) == GitFileStatus.NONE);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status/renamed-file-attributes-status-to-the-new-path", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var old_path = Path.build_filename (root_path, "old.txt");
            var new_path = Path.build_filename (root_path, "new.txt");
            FileUtils.set_contents (old_path, "hello");
            run_git (root_path, { "add", "old.txt" });
            run_git (root_path, { "commit", "-q", "-m", "init" });
            run_git (root_path, { "mv", "old.txt", "new.txt" });

            var status = GitStatus.run (root_path);

            assert (status != null);
            assert (status.status_for (new_path) == GitFileStatus.MODIFIED);
            assert (status.tooltip_for (new_path) == "Renamed");
            assert (status.status_for (old_path) == GitFileStatus.NONE);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status/conflicted-file-is-conflict", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "base\n");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "init" });

            run_git (root_path, { "checkout", "-q", "-b", "feature" });
            FileUtils.set_contents (path, "feature change\n");
            run_git (root_path, { "commit", "-q", "-a", "-m", "feature change" });

            run_git (root_path, { "checkout", "-q", "main" });
            FileUtils.set_contents (path, "main change\n");
            run_git (root_path, { "commit", "-q", "-a", "-m", "main change" });

            // Expected to fail with a real conflict — run_git() doesn't
            // check exit status, and that failure is exactly the fixture
            // this test needs: a.txt left with unresolved conflict markers.
            run_git (root_path, { "merge", "-q", "--no-edit", "feature" });

            var status = GitStatus.run (root_path);

            assert (status != null);
            assert (status.status_for (path) == GitFileStatus.CONFLICT);
            assert (status.tooltip_for (path) == "Conflicted");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status/ignored-file-is-ignored", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            FileUtils.set_contents (Path.build_filename (root_path, ".gitignore"), "secret.txt\n");
            var path = Path.build_filename (root_path, "secret.txt");
            FileUtils.set_contents (path, "hello");

            var status = GitStatus.run (root_path);

            assert (status != null);
            assert (status.status_for (path) == GitFileStatus.IGNORED);
            assert (status.tooltip_for (path) == "Ignored");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status/ignored-folder-is-one-entry-not-its-contents", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            FileUtils.set_contents (Path.build_filename (root_path, ".gitignore"), "out/\n");
            var dir = Path.build_filename (root_path, "out");
            DirUtils.create (dir, 0755);
            var inner_path = Path.build_filename (dir, "a.o");
            FileUtils.set_contents (inner_path, "hello");

            var status = GitStatus.run (root_path);

            assert (status != null);
            assert (status.status_for (dir) == GitFileStatus.IGNORED);
            assert (status.status_for (inner_path) == GitFileStatus.NONE);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
