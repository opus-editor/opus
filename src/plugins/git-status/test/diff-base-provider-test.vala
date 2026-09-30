// Tests Opus.Plugins.GitStatus.DiffBaseProvider end to end (real git repo,
// real activate()/deactivate(), real bases_for()/bases_changed) — same
// tmpdir + run_git idiom as git-status-provider-test.vala.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-diff-base-provider-test-XXXXXX");
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
    run_git (root_path, { "init", "-q" });
    run_git (root_path, { "config", "user.email", "test@opus.dev" });
    run_git (root_path, { "config", "user.name", "Opus Test" });
}

private GitDiff.Bases wait_for_bases (Opus.Plugins.GitStatus.DiffBaseProvider provider, string path) {
    GitDiff.Bases? result = null;
    var loop = new MainLoop ();
    provider.bases_for.begin (path, (obj, res) => {
        result = provider.bases_for.end (res);
        loop.quit ();
    });
    loop.run ();
    return result;
}

/** Waits for `provider`'s own bases_changed to fire at least once (its debounce round trip) — generous timeout so a slow machine doesn't hang this test forever. */
private bool wait_for_bases_changed (Opus.Plugins.GitStatus.DiffBaseProvider provider) {
    var loop = new MainLoop ();
    bool fired = false;
    var handler_id = provider.bases_changed.connect ((path) => {
        fired = true;
        loop.quit ();
    });
    var timeout_id = Timeout.add (2000, () => {
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();
    provider.disconnect (handler_id);
    Source.remove (timeout_id);
    return fired;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/diff-base-provider/committed-file-returns-both-bases", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello\n");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "initial" });

            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.DiffBaseProvider (context);
            provider.activate ();

            var bases = wait_for_bases (provider, path);
            assert (bases.head_text == "hello\n");
            assert (bases.index_text == "hello\n");

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/diff-base-provider/untracked-file-returns-null-bases", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello\n");

            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.DiffBaseProvider (context);
            provider.activate ();

            var bases = wait_for_bases (provider, path);
            assert (bases.head_text == null);
            assert (bases.index_text == null);

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/diff-base-provider/staged-file-has-a-newer-index-than-head", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello\n");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "initial" });

            FileUtils.set_contents (path, "staged change\n");
            run_git (root_path, { "add", "a.txt" });

            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.DiffBaseProvider (context);
            provider.activate ();

            var bases = wait_for_bases (provider, path);
            assert (bases.head_text == "hello\n");
            assert (bases.index_text == "staged change\n");

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/diff-base-provider/a-commit-fires-bases-changed", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "hello\n");

            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.DiffBaseProvider (context);
            provider.activate ();

            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "initial" });
            assert (wait_for_bases_changed (provider));

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
