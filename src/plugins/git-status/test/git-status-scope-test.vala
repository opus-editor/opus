// A GitStatus narrowed to one scope, and merging it into a snapshot of the
// whole repository (replace_under()) — as opposed to
// git-status-classify-test.vala, which covers what each working-tree state
// classify as. Same tmpdir-fixture pattern.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-status-scope-test-XXXXXX");
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

private void write_file (string path, string contents) throws Error {
    DirUtils.create_with_parents (Path.get_dirname (path), 0755);
    FileUtils.set_contents (path, contents);
}

/** A repository with `src/a.txt` and `docs/b.txt` committed. */
private string make_repository () throws Error {
    var root_path = make_tmp_dir ();
    run_git (root_path, { "init", "-q" });
    run_git (root_path, { "config", "user.email", "test@opus.dev" });
    run_git (root_path, { "config", "user.name", "Opus Test" });
    write_file (Path.build_filename (root_path, "src", "a.txt"), "a");
    write_file (Path.build_filename (root_path, "docs", "b.txt"), "b");
    run_git (root_path, { "add", "." });
    run_git (root_path, { "commit", "-q", "-m", "init" });
    return root_path;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-status-scope/a-scoped-run-reports-what-is-under-the-scope", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var src_path = Path.build_filename (root_path, "src");
            var a_path = Path.build_filename (src_path, "a.txt");
            write_file (a_path, "changed");

            var status = GitStatus.run (root_path, src_path);

            assert (status != null);
            assert (status.status_for (a_path) == GitFileStatus.MODIFIED);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-scope/a-scoped-run-leaves-out-what-is-outside-the-scope", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var b_path = Path.build_filename (root_path, "docs", "b.txt");
            write_file (b_path, "changed");

            var status = GitStatus.run (root_path, Path.build_filename (root_path, "src"));

            assert (status != null);
            assert (status.status_for (b_path) == GitFileStatus.NONE);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-scope/replacing-a-scope-adds-what-is-new-under-it", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var src_path = Path.build_filename (root_path, "src");
            var new_path = Path.build_filename (src_path, "new.txt");
            var status = GitStatus.run (root_path);
            write_file (new_path, "new");

            status.replace_under (src_path, GitStatus.run (root_path, src_path));

            assert (status.status_for (new_path) == GitFileStatus.NEW);
            assert (status.tooltip_for (new_path) == "Untracked");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-scope/replacing-a-scope-keeps-what-is-outside-it", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var src_path = Path.build_filename (root_path, "src");
            var b_path = Path.build_filename (root_path, "docs", "b.txt");
            write_file (b_path, "changed");
            var status = GitStatus.run (root_path);
            write_file (Path.build_filename (src_path, "new.txt"), "new");

            status.replace_under (src_path, GitStatus.run (root_path, src_path));

            assert (status.status_for (b_path) == GitFileStatus.MODIFIED);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-scope/replacing-a-scope-drops-a-file-that-went-back-to-clean", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var src_path = Path.build_filename (root_path, "src");
            var a_path = Path.build_filename (src_path, "a.txt");
            write_file (a_path, "changed");
            var status = GitStatus.run (root_path);
            write_file (a_path, "a");

            status.replace_under (src_path, GitStatus.run (root_path, src_path));

            assert (status.status_for (a_path) == GitFileStatus.NONE);
            assert (status.tooltip_for (a_path) == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-scope/replacing-a-scope-drops-an-untracked-file-that-is-gone", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var src_path = Path.build_filename (root_path, "src");
            var new_path = Path.build_filename (src_path, "new.txt");
            write_file (new_path, "new");
            var status = GitStatus.run (root_path);
            FileUtils.remove (new_path);

            status.replace_under (src_path, GitStatus.run (root_path, src_path));

            assert (status.status_for (new_path) == GitFileStatus.NONE);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-scope/replacing-a-file-scope-keeps-its-siblings", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var a_path = Path.build_filename (root_path, "src", "a.txt");
            var sibling_path = Path.build_filename (root_path, "src", "new.txt");
            write_file (sibling_path, "new");
            var status = GitStatus.run (root_path);
            write_file (a_path, "changed");

            status.replace_under (a_path, GitStatus.run (root_path, a_path));

            assert (status.status_for (a_path) == GitFileStatus.MODIFIED);
            assert (status.status_for (sibling_path) == GitFileStatus.NEW);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-status-scope/replacing-a-scope-does-not-touch-a-sibling-sharing-its-name-prefix", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var src_path = Path.build_filename (root_path, "src");
            var lookalike_path = Path.build_filename (root_path, "src-old", "c.txt");
            write_file (lookalike_path, "c");
            var status = GitStatus.run (root_path);

            status.replace_under (src_path, GitStatus.run (root_path, src_path));

            assert (status.status_for (lookalike_path) == GitFileStatus.NEW);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
