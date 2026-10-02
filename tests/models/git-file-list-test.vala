// Same tmpdir-fixture pattern as find-in-files-search-test.vala: a real
// `git init` per test, since the thing under test is git's own answer.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-file-list-test-XXXXXX");
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

/** Runs a real `git` command in `root_path` for a test fixture's own setup — never the thing under test itself. */
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

private void write_file (string root_path, string relative_path, string contents = "") throws Error {
    var path = Path.build_filename (root_path, relative_path);
    DirUtils.create_with_parents (Path.get_dirname (path), 0755);
    FileUtils.set_contents (path, contents);
}

/** A repository with one tracked file (`tracked.txt`) and a `.gitignore` hiding `ignored.txt` and `build/`. */
private string make_repository () throws Error {
    var root_path = make_tmp_dir ();
    run_git (root_path, { "init", "-q" });
    write_file (root_path, ".gitignore", "ignored.txt\nbuild/\n");
    write_file (root_path, "tracked.txt");
    run_git (root_path, { "add", "tracked.txt" });
    run_git (root_path, { "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init" });
    return root_path;
}

private enum Outcome { FINISHED, CANCELLED, FAILED }

/** Runs `list` to completion on a main loop, collecting every batch. */
private Outcome run_listing (GitFileList list, Cancellable cancellable, GenericArray<string> collected, out uint batch_count) {
    var loop = new MainLoop ();
    var outcome = Outcome.FINISHED;
    uint batches = 0;
    list.batch.connect ((paths) => {
        batches++;
        foreach (var path in paths) {
            collected.add (path);
        }
    });
    list.finished.connect ((was_cancelled) => {
        outcome = was_cancelled ? Outcome.CANCELLED : Outcome.FINISHED;
        loop.quit ();
    });
    list.failed.connect (() => {
        outcome = Outcome.FAILED;
        loop.quit ();
    });
    list.start (cancellable);
    loop.run ();
    batch_count = batches;
    return outcome;
}

private bool contains (GenericArray<string> paths, string wanted) {
    for (uint i = 0; i < paths.length; i++) {
        if (paths[i] == wanted) {
            return true;
        }
    }
    return false;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-file-list/lists-tracked-and-untracked-files-but-not-ignored-ones", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            write_file (root_path, "src/untracked.vala");
            write_file (root_path, "ignored.txt");
            write_file (root_path, "build/out.o");
            var collected = new GenericArray<string> ();
            uint batch_count;

            var outcome = run_listing (new GitFileList (root_path), new Cancellable (), collected, out batch_count);

            assert_true (outcome == Outcome.FINISHED);
            assert_true (contains (collected, "tracked.txt"));
            assert_true (contains (collected, "src/untracked.vala"));
            assert_true (contains (collected, ".gitignore"));
            assert_false (contains (collected, "ignored.txt"));
            assert_false (contains (collected, "build/out.o"));
            assert_cmpuint (collected.length, CompareOperator.EQ, 3);
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-file-list/skips-symlinks-and-tracked-files-deleted-from-disk", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            FileUtils.symlink ("tracked.txt", Path.build_filename (root_path, "link.txt"));
            write_file (root_path, "gone.txt");
            run_git (root_path, { "add", "gone.txt" });
            FileUtils.remove (Path.build_filename (root_path, "gone.txt"));
            var collected = new GenericArray<string> ();
            uint batch_count;

            run_listing (new GitFileList (root_path), new Cancellable (), collected, out batch_count);

            assert_false (contains (collected, "link.txt"));
            assert_false (contains (collected, "gone.txt"));
            assert_true (contains (collected, "tracked.txt"));
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-file-list/lists-non-ascii-names-unquoted", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            write_file (root_path, "café.txt");
            var collected = new GenericArray<string> ();
            uint batch_count;

            run_listing (new GitFileList (root_path), new Cancellable (), collected, out batch_count);

            assert_true (contains (collected, "café.txt"));
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-file-list/streams-in-batches-of-the-configured-size", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            write_file (root_path, "a.txt");
            write_file (root_path, "b.txt");
            var list = new GitFileList (root_path);
            list.batch_size = 3;
            var collected = new GenericArray<string> ();
            uint batch_count;

            run_listing (list, new Cancellable (), collected, out batch_count);

            assert_cmpuint (collected.length, CompareOperator.EQ, 4);
            assert_cmpuint (batch_count, CompareOperator.EQ, 2);
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-file-list/outside-a-repository-fails-instead-of-finishing", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            write_file (root_path, "plain.txt");
            var collected = new GenericArray<string> ();
            uint batch_count;

            var outcome = run_listing (new GitFileList (root_path), new Cancellable (), collected, out batch_count);

            assert_true (outcome == Outcome.FAILED);
            assert_cmpuint (collected.length, CompareOperator.EQ, 0);
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-file-list/cancelled-before-start-reports-cancelled-and-lists-nothing", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var cancellable = new Cancellable ();
            cancellable.cancel ();
            var collected = new GenericArray<string> ();
            uint batch_count;

            var outcome = run_listing (new GitFileList (root_path), cancellable, collected, out batch_count);

            assert_true (outcome == Outcome.CANCELLED);
            assert_cmpuint (collected.length, CompareOperator.EQ, 0);
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-file-list/is-repository-root-only-at-the-top-of-a-repository", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            write_file (root_path, "src/untracked.vala");

            assert_true (GitFileList.is_repository_root (root_path));
            assert_false (GitFileList.is_repository_root (Path.build_filename (root_path, "src")));
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-file-list/list-sync-returns-the-same-listing-at-once", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            write_file (root_path, "ignored.txt");

            var paths = GitFileList.list_sync (root_path);

            assert_nonnull (paths);
            assert_cmpuint (paths.length, CompareOperator.EQ, 2);
            assert_cmpstr (paths[0], CompareOperator.EQ, ".gitignore");
            assert_cmpstr (paths[1], CompareOperator.EQ, "tracked.txt");
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-file-list/list-sync-outside-a-repository-returns-null", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();

            assert_null (GitFileList.list_sync (root_path));
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
