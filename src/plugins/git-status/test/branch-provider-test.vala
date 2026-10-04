// Tests Opus.Plugins.GitStatus.BranchProvider end to end (real git repo,
// real activate()/deactivate()) — same tmpdir + run_git idiom as
// diff-base-provider-test.vala.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-branch-provider-test-XXXXXX");
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

/** `-b main`: never the machine's own `init.defaultBranch`. */
private void init_repo (string root_path) throws Error {
    run_git (root_path, { "init", "-q", "-b", "main" });
    run_git (root_path, { "config", "user.email", "test@opus.dev" });
    run_git (root_path, { "config", "user.name", "Opus Test" });
}

private void commit_file (string root_path, string name) throws Error {
    FileUtils.set_contents (Path.build_filename (root_path, name), "hello\n");
    run_git (root_path, { "add", name });
    run_git (root_path, { "commit", "-q", "-m", name });
}

/** Waits for `provider`'s own branch_changed to fire at least once (a read's round trip) — generous timeout so a slow machine doesn't hang this test forever. */
private bool wait_for_branch_changed (Opus.Plugins.GitStatus.BranchProvider provider) {
    var loop = new MainLoop ();
    bool fired = false;
    var handler_id = provider.branch_changed.connect (() => {
        fired = true;
        loop.quit ();
    });
    var timeout_id = Timeout.add (2000, () => {
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();
    provider.disconnect (handler_id);
    if (fired) {
        Source.remove (timeout_id);
    }
    return fired;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/branch-provider/reports-the-branch-once-activated", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt");
            var provider = new Opus.Plugins.GitStatus.BranchProvider (new WorkspaceContext (root_path));

            provider.activate ();
            wait_for_branch_changed (provider);

            assert (provider.current_branch () == "main");
            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/branch-provider/a-checkout-changes-the-branch", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt");
            var provider = new Opus.Plugins.GitStatus.BranchProvider (new WorkspaceContext (root_path));
            provider.activate ();
            wait_for_branch_changed (provider);

            run_git (root_path, { "checkout", "-q", "-b", "feature" });
            var fired = wait_for_branch_changed (provider);

            assert (fired);
            assert (provider.current_branch () == "feature");
            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/branch-provider/a-repository-created-in-the-workspace-gets-its-branch-reported", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.BranchProvider (context);
            provider.activate ();

            init_repo (root_path);
            context.directory_changed (root_path);
            var fired = wait_for_branch_changed (provider);

            assert (fired);
            assert (provider.current_branch () == "main");
            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/branch-provider/reports-nothing-once-deactivated", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt");
            var provider = new Opus.Plugins.GitStatus.BranchProvider (new WorkspaceContext (root_path));
            provider.activate ();
            wait_for_branch_changed (provider);
            provider.deactivate ();

            run_git (root_path, { "checkout", "-q", "-b", "feature" });
            var fired = wait_for_branch_changed (provider);

            assert (!fired);
            assert (provider.current_branch () == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
