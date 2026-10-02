// Same tmpdir-fixture pattern as tests/models/file-tree-test.vala. Layout:
//
//   <root>/
//     .git/
//       HEAD
//     src/
//       App.vala
//       models/
//         file-tree.vala
//     node_modules/
//       dep.js
//     README.md
//     link-to-readme -> README.md
private string make_fixture () throws Error {
    var root_path = DirUtils.make_tmp ("opus-walker-test-XXXXXX");

    DirUtils.create (Path.build_filename (root_path, ".git"), 0755);
    FileUtils.set_contents (Path.build_filename (root_path, ".git", "HEAD"), "");

    DirUtils.create (Path.build_filename (root_path, "src"), 0755);
    FileUtils.set_contents (Path.build_filename (root_path, "src", "App.vala"), "");
    DirUtils.create (Path.build_filename (root_path, "src", "models"), 0755);
    FileUtils.set_contents (Path.build_filename (root_path, "src", "models", "file-tree.vala"), "");

    DirUtils.create (Path.build_filename (root_path, "node_modules"), 0755);
    FileUtils.set_contents (Path.build_filename (root_path, "node_modules", "dep.js"), "");

    FileUtils.set_contents (Path.build_filename (root_path, "README.md"), "");
    FileUtils.symlink ("README.md", Path.build_filename (root_path, "link-to-readme"));

    return root_path;
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

/** Runs `walker` to completion on a main loop, collecting every batch. Returns whether it reported being cancelled. */
private bool run_walk (Opus.FuzzyFinder.DirectoryWalker walker, Cancellable cancellable, GenericArray<string> collected, out uint batch_count) {
    var loop = new MainLoop ();
    bool cancelled = false;
    uint batches = 0;
    walker.batch.connect ((paths) => {
        batches++;
        foreach (var path in paths) {
            collected.add (path);
        }
    });
    walker.finished.connect ((was_cancelled) => {
        cancelled = was_cancelled;
        loop.quit ();
    });
    walker.start (cancellable);
    loop.run ();
    batch_count = batches;
    return cancelled;
}

private bool contains (GenericArray<string> paths, string wanted) {
    for (uint i = 0; i < paths.length; i++) {
        if (paths[i] == wanted) {
            return true;
        }
    }
    return false;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/fuzzy-finder/walker/lists-every-regular-file-root-relative", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var walker = new Opus.FuzzyFinder.DirectoryWalker (root_path);
            var collected = new GenericArray<string> ();
            uint batch_count;

            run_walk (walker, new Cancellable (), collected, out batch_count);

            assert_true (contains (collected, "README.md"));
            assert_true (contains (collected, "src/App.vala"));
            assert_true (contains (collected, "src/models/file-tree.vala"));
            assert_true (contains (collected, "node_modules/dep.js"));
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/fuzzy-finder/walker/prunes-excluded-directories-and-skips-symlinks", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var walker = new Opus.FuzzyFinder.DirectoryWalker (root_path);
            walker.excluded_names = { ".git", "node_modules" };
            var collected = new GenericArray<string> ();
            uint batch_count;

            run_walk (walker, new Cancellable (), collected, out batch_count);

            assert_false (contains (collected, ".git/HEAD"));
            assert_false (contains (collected, "node_modules/dep.js"));
            assert_false (contains (collected, "link-to-readme"));
            assert_cmpuint (collected.length, CompareOperator.EQ, 3);
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/fuzzy-finder/walker/streams-in-batches-of-the-configured-size", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var walker = new Opus.FuzzyFinder.DirectoryWalker (root_path);
            walker.batch_size = 3;
            var collected = new GenericArray<string> ();
            uint batch_count;

            run_walk (walker, new Cancellable (), collected, out batch_count);

            assert_cmpuint (collected.length, CompareOperator.EQ, 4);
            assert_cmpuint (batch_count, CompareOperator.EQ, 2);
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/fuzzy-finder/walker/empty-root-finishes-with-no-batches", () => {
        string root_path = "";
        try {
            root_path = DirUtils.make_tmp ("opus-walker-test-XXXXXX");
            var walker = new Opus.FuzzyFinder.DirectoryWalker (root_path);
            var collected = new GenericArray<string> ();
            uint batch_count;

            bool cancelled = run_walk (walker, new Cancellable (), collected, out batch_count);

            assert_false (cancelled);
            assert_cmpuint (collected.length, CompareOperator.EQ, 0);
            assert_cmpuint (batch_count, CompareOperator.EQ, 0);
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/fuzzy-finder/walker/cancelled-before-start-reports-cancelled-and-lists-nothing", () => {
        string root_path = "";
        try {
            root_path = make_fixture ();
            var walker = new Opus.FuzzyFinder.DirectoryWalker (root_path);
            var cancellable = new Cancellable ();
            cancellable.cancel ();
            var collected = new GenericArray<string> ();
            uint batch_count;

            bool cancelled = run_walk (walker, cancellable, collected, out batch_count);

            assert_true (cancelled);
            assert_cmpuint (collected.length, CompareOperator.EQ, 0);
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/fuzzy-finder/walker/unreadable-root-finishes-cleanly", () => {
        var walker = new Opus.FuzzyFinder.DirectoryWalker ("/nonexistent/opus-walker-test");
        var collected = new GenericArray<string> ();
        uint batch_count;

        bool cancelled = run_walk (walker, new Cancellable (), collected, out batch_count);

        assert_false (cancelled);
        assert_cmpuint (collected.length, CompareOperator.EQ, 0);
    });

    return Test.run ();
}
