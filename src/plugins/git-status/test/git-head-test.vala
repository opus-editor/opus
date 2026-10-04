// Tests GitHead against real git repositories — same tmpdir + run_git
// idiom as diff-base-provider-test.vala.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-head-test-XXXXXX");
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

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-head/label-is-the-current-branch", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt");

            var label = GitHead.label (root_path);

            assert (label == "main");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-head/label-follows-a-checkout", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt");
            run_git (root_path, { "checkout", "-q", "-b", "feature/x" });

            var label = GitHead.label (root_path);

            assert (label == "feature/x");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-head/label-of-a-branch-with-no-commit-yet", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);

            var label = GitHead.label (root_path);

            assert (label == "main");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-head/label-of-a-detached-head-is-a-short-commit", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt");
            string commit;
            FileUtils.get_contents (Path.build_filename (root_path, ".git", "refs", "heads", "main"), out commit);
            run_git (root_path, { "checkout", "-q", "--detach" });

            var label = GitHead.label (root_path);

            assert (label.length >= 7);
            assert (commit.has_prefix (label));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-head/label-inside-a-subdirectory-of-a-repository", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var subdirectory = Path.build_filename (root_path, "src");
            DirUtils.create (subdirectory, 0755);

            var label = GitHead.label (subdirectory);

            assert (label == "main");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-head/label-of-a-linked-worktree-is-its-own-branch", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var repository = Path.build_filename (root_path, "repository");
            var worktree = Path.build_filename (root_path, "worktree");
            DirUtils.create (repository, 0755);
            init_repo (repository);
            commit_file (repository, "a.txt");
            run_git (repository, { "worktree", "add", "-q", "-b", "side", worktree });

            var label = GitHead.label (worktree);

            assert (label == "side");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-head/label-outside-a-repository-is-null", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();

            var label = GitHead.label (root_path);

            assert (label == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-head/git-dir-of-a-repository-root", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);

            var git_dir = GitHead.git_dir (root_path);

            assert (git_dir == Path.build_filename (root_path, ".git"));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-head/git-dir-of-a-linked-worktree-is-its-private-directory", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var repository = Path.build_filename (root_path, "repository");
            var worktree = Path.build_filename (root_path, "worktree");
            DirUtils.create (repository, 0755);
            init_repo (repository);
            commit_file (repository, "a.txt");
            run_git (repository, { "worktree", "add", "-q", "-b", "side", worktree });

            var git_dir = GitHead.git_dir (worktree);

            assert (git_dir == Path.build_filename (repository, ".git", "worktrees", "worktree"));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-head/git-dir-outside-a-repository-is-null", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();

            var git_dir = GitHead.git_dir (root_path);

            assert (git_dir == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
