// Tests Opus.Plugins.GitStatus.Provider end to end (real git repo, real
// activate()/deactivate(), real debounced async refresh) — as opposed to
// git-status-classify-test.vala, which only exercises the plain GitStatus
// model directly, with no Provider/WorkspaceContext/FileDecoration.*
// involved at all. Same tmpdir-fixture pattern as those.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-status-provider-test-XXXXXX");
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

/** Waits for `provider`'s own decorations_changed to fire at least once (its schedule_refresh() debounce + the async subprocess round trip) — a generous timeout so a slow machine doesn't hang this test forever. */
private bool wait_for_decorations_changed (Opus.Plugins.GitStatus.Provider provider) {
    var loop = new MainLoop ();
    bool fired = false;
    var handler_id = provider.decorations_changed.connect (() => {
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

    Test.add_func ("/git-status-provider/activate-reports-an-untracked-file-as-new", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");

            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();

            assert (wait_for_decorations_changed (provider));

            var decorations = provider.current_decorations ();
            var state = decorations[path];
            assert (state != null);
            assert (state.tone == FileDecoration.Tone.SUCCESS);
            assert (state.tooltip == "Untracked");
            assert (state.bubble_tooltip == "Contains new files");

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-provider/outside-a-repo-yields-an-empty-set", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "hello");

            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();

            assert (wait_for_decorations_changed (provider));
            assert (provider.current_decorations ().size () == 0);

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-provider/deactivate-drops-the-snapshot", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");

            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();
            assert (wait_for_decorations_changed (provider));
            assert (provider.current_decorations ().size () == 1);

            provider.deactivate ();

            assert (provider.current_decorations ().size () == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
