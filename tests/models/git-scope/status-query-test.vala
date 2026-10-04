// Same tmpdir-fixture pattern as git-file-list-test.vala: a real
// `git init` per test, since the thing under test is git's own answer.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-scope-status-query-test-XXXXXX");
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

private void write_file (string root_path, string relative_path) throws Error {
    var path = Path.build_filename (root_path, relative_path);
    DirUtils.create_with_parents (Path.get_dirname (path), 0755);
    FileUtils.set_contents (path, "");
}

private bool has_entry (GenericArray<string> entries, string entry) {
    for (uint i = 0; i < entries.length; i++) {
        if (entries[i] == entry) {
            return true;
        }
    }
    return false;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-scope-status-query/the-root-scope-lists-the-whole-repository", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            run_git (root_path, { "init", "-q" });
            write_file (root_path, "src/a.txt");
            write_file (root_path, "docs/b.txt");

            var entries = GitScope.StatusQuery.run (root_path, root_path);

            assert (entries != null);
            assert (entries.length == 2);
            assert (has_entry (entries, "?? src/a.txt"));
            assert (has_entry (entries, "?? docs/b.txt"));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-status-query/a-directory-scope-lists-only-its-subtree", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            run_git (root_path, { "init", "-q" });
            write_file (root_path, "src/a.txt");
            write_file (root_path, "src/deep/c.txt");
            write_file (root_path, "docs/b.txt");

            var entries = GitScope.StatusQuery.run (root_path, Path.build_filename (root_path, "src"));

            assert (entries != null);
            assert (entries.length == 2);
            assert (has_entry (entries, "?? src/a.txt"));
            assert (has_entry (entries, "?? src/deep/c.txt"));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-status-query/a-file-scope-lists-only-that-file", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            run_git (root_path, { "init", "-q" });
            write_file (root_path, "src/a.txt");
            write_file (root_path, "src/b.txt");

            var entries = GitScope.StatusQuery.run (root_path, Path.build_filename (root_path, "src", "a.txt"));

            assert (entries != null);
            assert (entries.length == 1);
            assert (entries[0] == "?? src/a.txt");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-status-query/a-clean-scope-lists-nothing", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            run_git (root_path, { "init", "-q" });
            write_file (root_path, "src/a.txt");
            DirUtils.create (Path.build_filename (root_path, "docs"), 0755);

            var entries = GitScope.StatusQuery.run (root_path, Path.build_filename (root_path, "docs"));

            assert (entries != null);
            assert (entries.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-status-query/an-ignored-directory-is-one-entry", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            run_git (root_path, { "init", "-q" });
            write_file (root_path, "build/a.o");
            write_file (root_path, "build/deep/b.o");
            FileUtils.set_contents (Path.build_filename (root_path, ".gitignore"), "build/\n");

            var entries = GitScope.StatusQuery.run (root_path, root_path);

            assert (entries != null);
            assert (has_entry (entries, "!! build/"));
            assert (!has_entry (entries, "!! build/a.o"));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-status-query/a-path-with-a-space-is-listed-verbatim", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            run_git (root_path, { "init", "-q" });
            write_file (root_path, "Empty File");

            var entries = GitScope.StatusQuery.run (root_path, root_path);

            assert (entries != null);
            assert (has_entry (entries, "?? Empty File"));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-status-query/a-pattern-character-in-the-scope-s-name-is-literal", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            run_git (root_path, { "init", "-q" });
            write_file (root_path, "a*/x.txt");
            write_file (root_path, "ab/y.txt");

            var entries = GitScope.StatusQuery.run (root_path, Path.build_filename (root_path, "a*"));

            assert (entries != null);
            assert (entries.length == 1);
            assert (entries[0] == "?? a*/x.txt");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-status-query/outside-a-repository-is-null", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            write_file (root_path, "a.txt");

            var entries = GitScope.StatusQuery.run (root_path, root_path);

            assert (entries == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
