// Same tmpdir-fixture pattern as file-tree-test.vala — each test builds
// just the files it needs under a fresh temp directory and tears it
// down afterward.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-find-in-files-test-XXXXXX");
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

private FindInFilesQuery plain_query (string text) {
    var query = new FindInFilesQuery ();
    query.text = text;
    return query;
}

/** Runs a real `git` command in `root_path` for a test fixture's own setup — never the thing under test itself (that's GitFileList). */
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

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/find-in-files-search/finds-a-single-match-with-context", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "hello\nworld\nfoo");

            var result = FindInFilesSearch.run (root_path, plain_query ("world"), 1);

            assert (result.total_match_count == 1);
            assert (result.file_count == 1);
            var file = result.files[0];
            assert (file.path == Path.build_filename (root_path, "a.txt"));
            assert (file.blocks.length == 1);
            var block = file.blocks[0];
            assert (block.start_line == 1);
            assert (block.lines.length == 3);
            assert (block.lines[0] == "hello");
            assert (block.lines[1] == "world");
            assert (block.lines[2] == "foo");
            assert (block.matches.length == 1);
            assert (block.matches[0].line_number == 2);
            assert (block.matches[0].start_column == 0);
            assert (block.matches[0].end_column == 5);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-search/finds-multiple-matches-on-one-line", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "foo foo foo");

            var result = FindInFilesSearch.run (root_path, plain_query ("foo"), 1);

            assert (result.total_match_count == 3);
            var block = result.files[0].blocks[0];
            assert (block.matches.length == 3);
            assert (block.matches[0].start_column == 0 && block.matches[0].end_column == 3);
            assert (block.matches[1].start_column == 4 && block.matches[1].end_column == 7);
            assert (block.matches[2].start_column == 8 && block.matches[2].end_column == 11);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-search/merges-touching-context-windows-into-one-block", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "a\nMATCH\nc\nMATCH\ne\nf\ng");

            var result = FindInFilesSearch.run (root_path, plain_query ("MATCH"), 1);

            var file = result.files[0];
            assert (file.blocks.length == 1);
            var block = file.blocks[0];
            assert (block.start_line == 1);
            assert (block.lines.length == 5);
            assert (block.matches.length == 2);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-search/keeps-far-apart-matches-as-separate-blocks", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "MATCH\nb\nc\nd\ne\nf\ng\nh\nMATCH");

            var result = FindInFilesSearch.run (root_path, plain_query ("MATCH"), 1);

            var file = result.files[0];
            assert (file.blocks.length == 2);
            assert (file.blocks[0].start_line == 1);
            assert (file.blocks[0].lines.length == 2);
            assert (file.blocks[1].start_line == 8);
            assert (file.blocks[1].lines.length == 2);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-search/regex-enabled-treats-the-query-as-a-pattern", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "fo\nfoo\nbaz");

            var query = plain_query ("fo+");
            query.regex_enabled = true;
            var result = FindInFilesSearch.run (root_path, query, 0);

            assert (result.total_match_count == 2);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-search/case-sensitive-restricts-to-exact-case", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "Foo\nfoo");

            var insensitive = FindInFilesSearch.run (root_path, plain_query ("foo"), 0);
            assert (insensitive.total_match_count == 2);

            var query = plain_query ("foo");
            query.case_sensitive_enabled = true;
            var sensitive = FindInFilesSearch.run (root_path, query, 0);
            assert (sensitive.total_match_count == 1);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-search/whole-word-excludes-a-substring-match", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "foobar\nfoo");

            var query = plain_query ("foo");
            query.whole_word_enabled = true;
            var result = FindInFilesSearch.run (root_path, query, 0);

            assert (result.total_match_count == 1);
            assert (result.files[0].blocks[0].matches[0].line_number == 2);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-search/skips-a-binary-file", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            uint8[] binary_data = { 'h', 'e', 'l', 'l', 'o', 0xFF, 0xFE };
            FileUtils.set_data (Path.build_filename (root_path, "binary.dat"), binary_data);

            var result = FindInFilesSearch.run (root_path, plain_query ("hello"), 0);

            assert (result.total_match_count == 0);
            assert (result.file_count == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-search/skips-the-git-directory", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            DirUtils.create (Path.build_filename (root_path, ".git"), 0755);
            FileUtils.set_contents (Path.build_filename (root_path, ".git", "config"), "needle");
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "needle");

            var result = FindInFilesSearch.run (root_path, plain_query ("needle"), 0);

            assert (result.total_match_count == 1);
            assert (result.files[0].path == Path.build_filename (root_path, "a.txt"));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-search/gitignore-enabled-skips-ignored-files-via-real-git", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            run_git (root_path, { "init", "-q" });
            FileUtils.set_contents (Path.build_filename (root_path, ".gitignore"), "ignored.txt\n");
            FileUtils.set_contents (Path.build_filename (root_path, "ignored.txt"), "needle");
            // Untracked (never `git add`ed) but not gitignored — still
            // found, same as `git ls-files --others --exclude-standard`
            // itself would list it.
            FileUtils.set_contents (Path.build_filename (root_path, "kept.txt"), "needle");

            var query = plain_query ("needle");
            query.gitignore_enabled = true;
            var result = FindInFilesSearch.run (root_path, query, 0);

            assert (result.file_count == 1);
            assert (result.files[0].path == Path.build_filename (root_path, "kept.txt"));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-search/gitignore-enabled-outside-a-repo-falls-back-to-a-plain-search", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir (); // deliberately no `git init` here
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "needle");

            var query = plain_query ("needle");
            query.gitignore_enabled = true;
            var result = FindInFilesSearch.run (root_path, query, 0);

            assert (result.total_match_count == 1);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-search/where-text-restricts-the-search-scope", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            DirUtils.create_with_parents (Path.build_filename (root_path, "src"), 0755);
            DirUtils.create_with_parents (Path.build_filename (root_path, "lib"), 0755);
            FileUtils.set_contents (Path.build_filename (root_path, "src", "a.vala"), "needle");
            FileUtils.set_contents (Path.build_filename (root_path, "lib", "b.vala"), "needle");

            var query = plain_query ("needle");
            query.where_text = "/src";
            var result = FindInFilesSearch.run (root_path, query, 0);

            assert (result.file_count == 1);
            assert (result.files[0].path == Path.build_filename (root_path, "src", "a.vala"));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-search/run-async-resolves-on-the-main-loop", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "hello world");

            var loop = new MainLoop ();
            FindInFilesResult? result = null;
            Error? async_error = null;
            FindInFilesSearch.run_async.begin (root_path, plain_query ("world"), 1, (obj, res) => {
                try {
                    result = FindInFilesSearch.run_async.end (res);
                } catch (Error e) {
                    async_error = e;
                }
                loop.quit ();
            });
            loop.run ();

            if (async_error != null) {
                error (async_error.message);
            }
            assert (result != null);
            assert (result.total_match_count == 1);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
