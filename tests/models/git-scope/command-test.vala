// Same tmpdir-fixture pattern as stage-test.vala: a real `git init` per
// test, since the thing under test is how a real git failure is reported.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-scope-command-test-XXXXXX");
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

/** Runs `step` expecting git to refuse — the FAILED error, with `needle` somewhere in git's own words. */
private delegate void GitStep () throws GitScope.CommandError;
private void assert_git_refuses (GitStep step, string needle) {
    try {
        step ();
        assert_not_reached ();
    } catch (GitScope.CommandError e) {
        assert (e is GitScope.CommandError.FAILED);
        if (!e.message.contains (needle)) {
            error ("expected \"%s\" in: %s", needle, e.message);
        }
    }
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-scope-command/runs-git-against-the-root", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            run_git (root_path, { "init", "-q", "-b", "main" });
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");

            GitScope.Command.run_on_paths (root_path, { "add", "--" }, { path });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree != null);
            assert (tree.staged.length == 1);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-command/no-paths-runs-nothing", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();

            // Not a repository at all — git would refuse, if it ran.
            GitScope.Command.run_on_paths (root_path, { "add", "--" }, {});
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-command/a-failure-carries-the-command-and-stderr", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");

            try {
                GitScope.Command.run_on_paths (root_path, { "add", "--" }, { path });
                assert_not_reached ();
            } catch (GitScope.CommandError e) {
                assert (e is GitScope.CommandError.FAILED);
                assert (e.message.has_prefix ("$ git -C %s add -- %s\n".printf (root_path, path)));
                assert (e.message.contains ("not a git repository"));
            }
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-command/run-without-paths-runs-the-command", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            run_git (root_path, { "init", "-q", "-b", "main" });

            GitScope.Command.run (root_path, { "config", "user.name", "Opus Test" });

            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
            launcher.set_cwd (root_path);
            string name;
            launcher.spawnv ({ "git", "config", "user.name" }).communicate_utf8 (null, null, out name, null);
            assert (name.strip () == "Opus Test");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-command/run-failure-is-reported-with-the-command-line", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            run_git (root_path, { "init", "-q", "-b", "main" });

            assert_git_refuses (() => GitScope.Command.run (root_path, { "no-such-subcommand" }), "no-such-subcommand");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-command/a-path-with-spaces-and-unicode-goes-through-as-one-argument", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            run_git (root_path, { "init", "-q", "-b", "main" });
            var path = Path.build_filename (root_path, "my notes ção.txt");
            FileUtils.set_contents (path, "hello");

            GitScope.Command.run_on_paths (root_path, { "add", "--" }, { path });

            var tree = GitScope.WorkingTree.run (root_path);
            assert (tree.staged.length == 1);
            assert (tree.staged[0].path == path);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-command/git-dir-is-the-repositorys-own-dot-git", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            run_git (root_path, { "init", "-q", "-b", "main" });

            var git_dir = GitScope.Command.git_dir (root_path);

            assert (git_dir != null);
            assert (FileUtils.test (Path.build_filename (git_dir, "HEAD"), FileTest.EXISTS));
            assert (Path.get_basename (git_dir) == ".git");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-command/git-dir-is-null-outside-a-repository", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            assert (GitScope.Command.git_dir (root_path) == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-command/in-thread-delivers-the-steps-failure-to-the-caller", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var loop = new MainLoop ();
            GitScope.CommandError? caught = null;
            bool finished = false;

            GitScope.Command.in_thread.begin (() => {
                throw new GitScope.CommandError.FAILED ("from the thread");
            }, (obj, res) => {
                try {
                    GitScope.Command.in_thread.end (res);
                    finished = true;
                } catch (GitScope.CommandError e) {
                    caught = e;
                }
                loop.quit ();
            });
            loop.run ();

            assert (!finished);
            assert (caught != null && caught.message == "from the thread");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
