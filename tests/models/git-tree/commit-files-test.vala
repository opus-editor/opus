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


private bool has (GenericArray<GitScope.Change> changes, string name, GitScope.ChangeKind kind) {
    for (uint i = 0; i < changes.length; i++) {
        if (Path.get_basename (changes[i].path) == name && changes[i].kind == kind) {
            return true;
        }
    }
    return false;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-tree-commit-files/lists-what-a-commit-added-changed-and-removed", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "a");
            commit_file (root_path, "b.txt", "b");
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "a changed");
            FileUtils.set_contents (Path.build_filename (root_path, "c.txt"), "new");
            FileUtils.remove (Path.build_filename (root_path, "b.txt"));
            run_git (root_path, { "add", "-A" });
            run_git (root_path, { "commit", "-q", "-m", "mixed" });
            var head = GitTree.Log.run (root_path)[0];

            var files = GitTree.CommitFiles.run (root_path, head);

            assert (files != null && files.length == 3);
            assert (has (files, "a.txt", GitScope.ChangeKind.MODIFIED));
            assert (has (files, "b.txt", GitScope.ChangeKind.DELETED));
            assert (has (files, "c.txt", GitScope.ChangeKind.ADDED));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-commit-files/a-root-commit-lists-everything-as-added", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "first");

            var files = GitTree.CommitFiles.run (root_path, GitTree.Log.run (root_path)[0]);

            assert (files.length == 1 && has (files, "a.txt", GitScope.ChangeKind.ADDED));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-commit-files/a-rename-carries-its-old-path", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "same contents, moved");
            run_git (root_path, { "mv", "a.txt", "b.txt" });
            run_git (root_path, { "commit", "-q", "-m", "move" });

            var files = GitTree.CommitFiles.run (root_path, GitTree.Log.run (root_path)[0]);

            assert (files.length == 1);
            assert (files[0].kind == GitScope.ChangeKind.RENAMED);
            assert (files[0].path == Path.build_filename (root_path, "b.txt"));
            assert (files[0].old_path == Path.build_filename (root_path, "a.txt"));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-commit-files/a-merge-shows-what-it-brought-in-against-its-first-parent", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            run_git (root_path, { "checkout", "-q", "-b", "side" });
            commit_file (root_path, "side.txt", "side");
            run_git (root_path, { "checkout", "-q", "main" });
            commit_file (root_path, "main.txt", "main");
            run_git (root_path, { "merge", "-q", "--no-ff", "-m", "merge side", "side" });

            var files = GitTree.CommitFiles.run (root_path, GitTree.Log.run (root_path)[0]);

            assert (files.length == 1 && has (files, "side.txt", GitScope.ChangeKind.ADDED));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-commit-files/a-stash-lists-what-it-parked", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "parked");
            run_git (root_path, { "stash" });
            int color = 0;
            var rows = GitTree.Graph.layout (GitTree.Log.run (root_path), ref color, null, GitTree.Log.stashes (root_path));
            assert (rows[0].stash != null);

            var files = GitTree.CommitFiles.run (root_path, rows[0].commit);

            assert (files.length == 1 && has (files, "a.txt", GitScope.ChangeKind.MODIFIED));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-commit-files/the-whole-body-is-kept-on-the-commit", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "a");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "subject\n\nline one\nline two" });

            var commit = GitTree.Log.run (root_path)[0];

            assert (commit.body == "line one\nline two");
            assert (commit.message == "subject\n\nline one\nline two");
            assert (commit.date_label.length == 8);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
