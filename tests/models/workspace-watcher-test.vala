// Same tmpdir-fixture pattern as git-file-list-test.vala: a real
// `git init` per test, and real Gio.FileMonitor events on a main loop —
// the thing under test is which directories end up reporting changes.

// Long enough for an inotify event to be delivered and dispatched; what a
// "nothing was reported" test waits before concluding nothing will be.
private const uint QUIET_MS = 400;
private const uint GIVE_UP_MS = 5000;

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-workspace-watcher-test-XXXXXX");
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

private void write_file (string path, string contents = "") throws Error {
    DirUtils.create_with_parents (Path.get_dirname (path), 0755);
    FileUtils.set_contents (path, contents);
}

/** A repository with `src/` (holding `a.txt`) and a `.gitignore` hiding `build/` (holding `a.o`). */
private string make_repository () throws Error {
    var root_path = make_tmp_dir ();
    run_git (root_path, { "init", "-q" });
    write_file (Path.build_filename (root_path, ".gitignore"), "build/\n");
    write_file (Path.build_filename (root_path, "src", "a.txt"));
    write_file (Path.build_filename (root_path, "build", "a.o"));
    return root_path;
}

/** Same layout as make_repository(), with no repository in it. */
private string make_plain_folder () throws Error {
    var root_path = make_tmp_dir ();
    write_file (Path.build_filename (root_path, "src", "a.txt"));
    return root_path;
}

private void wait_for_rescan (WorkspaceWatcher watcher) {
    var loop = new MainLoop ();
    var handler_id = watcher.rescanned.connect (() => loop.quit ());
    var timeout_id = Timeout.add (GIVE_UP_MS, () => {
        Test.fail_printf ("no rescan within %u ms", GIVE_UP_MS);
        loop.quit ();
        return Source.CONTINUE;
    });
    loop.run ();
    Source.remove (timeout_id);
    watcher.disconnect (handler_id);
}

/** Every path `watcher` reports through directory_changed/content_changed over the next QUIET_MS. */
private GenericArray<string> collect_reports (WorkspaceWatcher watcher) {
    var reports = new GenericArray<string> ();
    var directory_handler_id = watcher.directory_changed.connect ((path) => reports.add ("directory " + path));
    var content_handler_id = watcher.content_changed.connect ((path) => reports.add ("content " + path));

    var loop = new MainLoop ();
    Timeout.add (QUIET_MS, () => {
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();

    watcher.disconnect (directory_handler_id);
    watcher.disconnect (content_handler_id);
    return reports;
}

private uint count_reported (GenericArray<string> reports, string report) {
    uint count = 0;
    for (uint i = 0; i < reports.length; i++) {
        if (reports[i] == report) {
            count++;
        }
    }
    return count;
}

private bool reported (GenericArray<string> reports, string report) {
    return count_reported (reports, report) > 0;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/workspace-watcher/reports-a-file-created-in-an-unignored-directory", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var src_path = Path.build_filename (root_path, "src");
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);

            write_file (Path.build_filename (src_path, "new.txt"));
            var reports = collect_reports (watcher);

            assert (reported (reports, "directory " + src_path));
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/reports-a-burst-in-one-directory-once", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var src_path = Path.build_filename (root_path, "src");
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);

            for (int i = 0; i < 20; i++) {
                write_file (Path.build_filename (src_path, "new-%d.txt".printf (i)));
            }
            var reports = collect_reports (watcher);

            assert (count_reported (reports, "directory " + src_path) == 1);
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/reports-a-file-rewritten-in-an-unignored-directory", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var file_path = Path.build_filename (root_path, "src", "a.txt");
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);

            // In place — FileUtils.set_contents() replaces the file through a
            // rename, which is a change to the directory instead.
            FileStream.open (file_path, "w").puts ("rewritten");
            var reports = collect_reports (watcher);

            assert (reported (reports, "content " + file_path));
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/stays-silent-about-an-ignored-directory", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);

            write_file (Path.build_filename (root_path, "build", "b.o"));
            var reports = collect_reports (watcher);

            assert (reports.length == 0);
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/reports-an-ignored-directory-once-requested", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var build_path = Path.build_filename (root_path, "build");
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);
            watcher.request (build_path);

            write_file (Path.build_filename (build_path, "b.o"));
            var reports = collect_reports (watcher);

            assert (reported (reports, "directory " + build_path));
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/stays-silent-about-an-ignored-directory-once-released", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var build_path = Path.build_filename (root_path, "build");
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);
            watcher.request (build_path);
            watcher.release (build_path);

            write_file (Path.build_filename (build_path, "b.o"));
            var reports = collect_reports (watcher);

            assert (reports.length == 0);
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/keeps-reporting-an-unignored-directory-once-released", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var src_path = Path.build_filename (root_path, "src");
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);
            watcher.request (src_path);
            watcher.release (src_path);

            write_file (Path.build_filename (src_path, "new.txt"));
            var reports = collect_reports (watcher);

            assert (reported (reports, "directory " + src_path));
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/reports-a-directory-created-after-opening", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var docs_path = Path.build_filename (root_path, "docs");
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);
            DirUtils.create (docs_path, 0755);
            wait_for_rescan (watcher);

            write_file (Path.build_filename (docs_path, "new.md"));
            var reports = collect_reports (watcher);

            assert (reported (reports, "directory " + docs_path));
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/reports-a-directory-created-inside-a-subdirectory", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var deep_path = Path.build_filename (root_path, "src", "deep");
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);
            DirUtils.create (deep_path, 0755);
            wait_for_rescan (watcher);

            write_file (Path.build_filename (deep_path, "new.txt"));
            var reports = collect_reports (watcher);

            assert (reported (reports, "directory " + deep_path));
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/keeps-reporting-other-directories-after-one-subdirectory-changes", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var docs_path = Path.build_filename (root_path, "docs");
            write_file (Path.build_filename (docs_path, "a.md"));
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);
            DirUtils.create (Path.build_filename (root_path, "src", "deep"), 0755);
            wait_for_rescan (watcher);

            write_file (Path.build_filename (docs_path, "new.md"));
            var reports = collect_reports (watcher);

            assert (reported (reports, "directory " + docs_path));
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/stays-silent-about-a-directory-a-subdirectory-s-own-ignore-rules-hide", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var generated_path = Path.build_filename (root_path, "src", "generated");
            write_file (Path.build_filename (generated_path, "a.c"));
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);
            write_file (Path.build_filename (root_path, "src", ".gitignore"), "generated/\n");
            wait_for_rescan (watcher);

            write_file (Path.build_filename (generated_path, "b.c"));
            var reports = collect_reports (watcher);

            assert (reports.length == 0);
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/stays-silent-about-a-directory-created-inside-a-requested-ignored-one", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var build_path = Path.build_filename (root_path, "build");
            var nested_path = Path.build_filename (build_path, "objects");
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);
            watcher.request (build_path);
            DirUtils.create (nested_path, 0755);
            collect_reports (watcher);

            write_file (Path.build_filename (nested_path, "a.o"));
            var reports = collect_reports (watcher);

            assert (reports.length == 0);
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/reports-a-directory-the-ignore-rules-stop-hiding", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var build_path = Path.build_filename (root_path, "build");
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);
            write_file (Path.build_filename (root_path, ".gitignore"), "");
            wait_for_rescan (watcher);

            write_file (Path.build_filename (build_path, "b.o"));
            var reports = collect_reports (watcher);

            assert (reported (reports, "directory " + build_path));
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/stays-silent-about-a-directory-the-ignore-rules-start-hiding", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);
            write_file (Path.build_filename (root_path, ".gitignore"), "build/\nsrc/\n");
            wait_for_rescan (watcher);

            write_file (Path.build_filename (root_path, "src", "new.txt"));
            var reports = collect_reports (watcher);

            assert (reports.length == 0);
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/outside-a-repository-reports-the-root", () => {
        string root_path = "";
        try {
            root_path = make_plain_folder ();
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);

            write_file (Path.build_filename (root_path, "new.txt"));
            var reports = collect_reports (watcher);

            assert (reported (reports, "directory " + root_path));
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/outside-a-repository-stays-silent-about-an-unrequested-directory", () => {
        string root_path = "";
        try {
            root_path = make_plain_folder ();
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);

            write_file (Path.build_filename (root_path, "src", "new.txt"));
            var reports = collect_reports (watcher);

            assert (reports.length == 0);
            watcher.close ();
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/workspace-watcher/stays-silent-once-closed", () => {
        string root_path = "";
        try {
            root_path = make_repository ();
            var watcher = new WorkspaceWatcher (root_path);
            wait_for_rescan (watcher);
            watcher.close ();

            write_file (Path.build_filename (root_path, "src", "new.txt"));
            var reports = collect_reports (watcher);

            assert (reports.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
