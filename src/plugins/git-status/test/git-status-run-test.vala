// Infra: GitStatus.run()/run_async()'s own plumbing (no git repo at all,
// and the async wrapper actually resolving on the main loop) — as
// opposed to git-status-classify-test.vala, which covers what a real repo's
// various states classify as. Same tmpdir-fixture pattern as
// find-in-files-search-test.vala.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-status-run-test-XXXXXX");
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
private void init_repo (string root_path) throws Error {
    run_git (root_path, { "init", "-q" });
    run_git (root_path, { "config", "user.email", "test@opus.dev" });
    run_git (root_path, { "config", "user.name", "Opus Test" });
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-status/outside-a-repo-returns-null", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "hello");

            var status = GitStatus.run (root_path);

            assert (status == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status/run-async-resolves-on-the-main-loop", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");

            var loop = new MainLoop ();
            GitStatus? result = null;
            GitStatus.run_async.begin (root_path, null, (obj, res) => {
                result = GitStatus.run_async.end (res);
                loop.quit ();
            });
            loop.run ();

            assert (result != null);
            assert (result.status_for (path) == GitFileStatus.NEW);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
