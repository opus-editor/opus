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

private GitTree.Row? row_of (GenericArray<GitTree.Row> rows, string subject) {
    for (uint i = 0; i < rows.length; i++) {
        if (rows[i].commit.subject == subject) {
            return rows[i];
        }
    }
    return null;
}

private GenericArray<GitTree.Row> layout (string root_path) {
    int color = 0;
    return GitTree.Graph.layout (GitTree.Log.run (root_path), ref color);
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-tree-working-row/counts-every-kind-of-change-on-heads-lane", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "edited");
            FileUtils.set_contents (Path.build_filename (root_path, "b.txt"), "new");
            FileUtils.set_contents (Path.build_filename (root_path, "c.txt"), "staged");
            run_git (root_path, { "add", "c.txt" });
            var rows = layout (root_path);

            var working = GitTree.WorkingRow.create (GitScope.WorkingTree.run (root_path), rows);

            assert (working != null);
            assert (working.change_count == 3);
            assert (working.head_lane == rows[0].node_lane && working.head_color == rows[0].node_color);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-working-row/a-clean-tree-has-no-row", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");

            assert (GitTree.WorkingRow.create (GitScope.WorkingTree.run (root_path), layout (root_path)) == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-working-row/hangs-off-head-even-when-head-is-not-the-newest-row", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            commit_file (root_path, "a.txt", "on main");
            run_git (root_path, { "checkout", "-q", "-b", "feature" });
            commit_file (root_path, "b.txt", "feature 1");
            run_git (root_path, { "checkout", "-q", "main" });
            FileUtils.set_contents (Path.build_filename (root_path, "z.txt"), "wip");
            var rows = layout (root_path);

            var working = GitTree.WorkingRow.create (GitScope.WorkingTree.run (root_path), rows);

            assert (working.head_lane == row_of (rows, "on main").node_lane);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-working-row/no-commits-means-no-row-even-with-changes", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "new");

            assert (GitTree.WorkingRow.create (GitScope.WorkingTree.run (root_path), layout (root_path)) == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
