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
    uint timeout_id = 0;
    timeout_id = Timeout.add (2000, () => {
        timeout_id = 0;
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();
    provider.disconnect (handler_id);
    if (timeout_id != 0) {
        Source.remove (timeout_id);
    }
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

    Test.add_func ("/git-status-provider/an-ignored-folder-is-muted-and-covers-its-contents", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            FileUtils.set_contents (Path.build_filename (root_path, ".gitignore"), "out/\n");
            var dir = Path.build_filename (root_path, "out");
            DirUtils.create (dir, 0755);
            FileUtils.set_contents (Path.build_filename (dir, "a.o"), "hello");

            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();

            assert (wait_for_decorations_changed (provider));

            var state = provider.current_decorations ()[dir];
            assert (state != null);
            assert (state.tone == FileDecoration.Tone.MUTED);
            assert (state.tooltip == "Ignored");
            assert (!state.propagate);
            assert (state.covers_descendants);

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-provider/a-change-in-one-directory-decorates-what-is-new-there", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var src_path = Path.build_filename (root_path, "src");
            DirUtils.create (src_path, 0755);
            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();
            assert (wait_for_decorations_changed (provider));
            var path = Path.build_filename (src_path, "a.txt");
            FileUtils.set_contents (path, "hello");

            context.directory_changed (src_path);

            assert (wait_for_decorations_changed (provider));
            assert (provider.current_decorations ()[path] != null);

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-provider/a-change-in-one-directory-keeps-another-directory-s-decorations", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var src_path = Path.build_filename (root_path, "src");
            var docs_path = Path.build_filename (root_path, "docs");
            DirUtils.create (src_path, 0755);
            DirUtils.create (docs_path, 0755);
            var docs_file_path = Path.build_filename (docs_path, "b.txt");
            FileUtils.set_contents (docs_file_path, "hello");
            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();
            assert (wait_for_decorations_changed (provider));
            FileUtils.set_contents (Path.build_filename (src_path, "a.txt"), "hello");

            context.directory_changed (src_path);

            assert (wait_for_decorations_changed (provider));
            assert (provider.current_decorations ()[docs_file_path] != null);

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-provider/a-change-in-one-directory-does-not-re-read-another", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var src_path = Path.build_filename (root_path, "src");
            var docs_path = Path.build_filename (root_path, "docs");
            DirUtils.create (src_path, 0755);
            DirUtils.create (docs_path, 0755);
            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();
            assert (wait_for_decorations_changed (provider));
            var unreported_path = Path.build_filename (docs_path, "b.txt");
            FileUtils.set_contents (unreported_path, "hello");

            context.directory_changed (src_path);

            assert (wait_for_decorations_changed (provider));
            assert (provider.current_decorations ()[unreported_path] == null);

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-provider/changes-in-two-directories-decorate-both", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var src_path = Path.build_filename (root_path, "src");
            var docs_path = Path.build_filename (root_path, "docs");
            DirUtils.create (src_path, 0755);
            DirUtils.create (docs_path, 0755);
            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();
            assert (wait_for_decorations_changed (provider));
            var src_file_path = Path.build_filename (src_path, "a.txt");
            var docs_file_path = Path.build_filename (docs_path, "b.txt");
            FileUtils.set_contents (src_file_path, "hello");
            FileUtils.set_contents (docs_file_path, "hello");

            context.directory_changed (src_path);
            context.directory_changed (docs_path);

            assert (wait_for_decorations_changed (provider));
            var decorations = provider.current_decorations ();
            assert (decorations[src_file_path] != null);
            assert (decorations[docs_file_path] != null);

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-provider/a-file-written-back-to-its-committed-contents-loses-its-decoration", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "init" });
            FileUtils.set_contents (path, "changed");
            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();
            assert (wait_for_decorations_changed (provider));
            FileUtils.set_contents (path, "hello");

            context.file_content_changed (path);

            assert (wait_for_decorations_changed (provider));
            assert (provider.current_decorations ()[path] == null);

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-provider/rewritten-ignore-rules-re-read-the-directory-they-sit-in", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var src_path = Path.build_filename (root_path, "src");
            DirUtils.create (src_path, 0755);
            var ignore_path = Path.build_filename (src_path, ".gitignore");
            var hidden_path = Path.build_filename (src_path, "generated.txt");
            FileUtils.set_contents (ignore_path, "");
            FileUtils.set_contents (hidden_path, "hello");
            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();
            assert (wait_for_decorations_changed (provider));
            FileUtils.set_contents (ignore_path, "generated.txt\n");

            context.file_content_changed (ignore_path);

            assert (wait_for_decorations_changed (provider));
            assert (provider.current_decorations ()[hidden_path].tone == FileDecoration.Tone.MUTED);

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-provider/a-change-inside-the-git-directory-re-reads-everything", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var docs_path = Path.build_filename (root_path, "docs");
            DirUtils.create (docs_path, 0755);
            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();
            assert (wait_for_decorations_changed (provider));
            var unreported_path = Path.build_filename (docs_path, "b.txt");
            FileUtils.set_contents (unreported_path, "hello");

            FileUtils.set_contents (Path.build_filename (root_path, ".git", "ORIG_HEAD"), "");

            assert (wait_for_decorations_changed (provider));
            assert (provider.current_decorations ()[unreported_path] != null);

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-provider/a-change-inside-an-ignored-directory-does-not-refresh", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            FileUtils.set_contents (Path.build_filename (root_path, ".gitignore"), "out/\n");
            var out_path = Path.build_filename (root_path, "out");
            DirUtils.create (out_path, 0755);
            FileUtils.set_contents (Path.build_filename (out_path, "a.o"), "hello");
            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();
            assert (wait_for_decorations_changed (provider));
            FileUtils.set_contents (Path.build_filename (out_path, "b.o"), "hello");

            context.directory_changed (out_path);

            assert (!wait_for_decorations_changed (provider));

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-provider/a-tracked-file-inside-an-ignored-directory-still-refreshes", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            FileUtils.set_contents (Path.build_filename (root_path, ".gitignore"), "out/\n");
            var out_path = Path.build_filename (root_path, "out");
            DirUtils.create (out_path, 0755);
            var path = Path.build_filename (out_path, "tracked.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "-f", "out/tracked.txt" });
            run_git (root_path, { "commit", "-q", "-m", "init" });
            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();
            assert (wait_for_decorations_changed (provider));
            FileUtils.set_contents (path, "changed");

            context.file_content_changed (path);

            assert (wait_for_decorations_changed (provider));
            assert (provider.current_decorations ()[path].tone == FileDecoration.Tone.WARNING);

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-provider/a-steady-stream-of-changes-still-refreshes", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();
            assert (wait_for_decorations_changed (provider));
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");

            // A change every 100 ms for 1.5 s: never a quiet moment longer
            // than that until the stream ends.
            var loop = new MainLoop ();
            bool refreshed_mid_stream = false;
            var handler_id = provider.decorations_changed.connect (() => {
                refreshed_mid_stream = true;
            });
            int ticks = 0;
            Timeout.add (100, () => {
                context.directory_changed (root_path);
                ticks++;
                if (ticks < 15) {
                    return Source.CONTINUE;
                }
                loop.quit ();
                return Source.REMOVE;
            });
            loop.run ();
            provider.disconnect (handler_id);

            assert (refreshed_mid_stream);
            assert (provider.current_decorations ()[path] != null);

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-provider/a-lock-file-inside-the-git-directory-does-not-refresh", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var context = new WorkspaceContext (root_path);
            var provider = new Opus.Plugins.GitStatus.Provider (context);
            provider.activate ();
            assert (wait_for_decorations_changed (provider));

            FileStream.open (Path.build_filename (root_path, ".git", "index.lock"), "w").puts ("");

            assert (!wait_for_decorations_changed (provider));

            provider.deactivate ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
