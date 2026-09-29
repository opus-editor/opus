// Same tmpdir-fixture pattern as find-in-files-search-test.vala.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-find-in-files-replace-test-XXXXXX");
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

private string read_file_contents (string path) {
    string contents;
    try {
        FileUtils.get_contents (path, out contents);
    } catch (Error e) {
        error (e.message);
    }
    return contents;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/find-in-files-replace/replaces-a-single-match", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello world");

            var result = FindInFilesSearch.run (root_path, plain_query ("world"), 0);
            FindInFilesReplace.run (result, "opus");

            assert (read_file_contents (path) == "hello opus");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-replace/replaces-every-match-in-one-file", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "foo foo\nfoo");

            var result = FindInFilesSearch.run (root_path, plain_query ("foo"), 0);
            FindInFilesReplace.run (result, "bar");

            assert (read_file_contents (path) == "bar bar\nbar");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-replace/replaces-across-every-matched-file", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path_a = Path.build_filename (root_path, "a.txt");
            var path_b = Path.build_filename (root_path, "b.txt");
            FileUtils.set_contents (path_a, "needle one");
            FileUtils.set_contents (path_b, "needle two");

            var result = FindInFilesSearch.run (root_path, plain_query ("needle"), 0);
            FindInFilesReplace.run (result, "pin");

            assert (read_file_contents (path_a) == "pin one");
            assert (read_file_contents (path_b) == "pin two");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-replace/regex-mode-substitutes-capture-groups", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "first-last");

            var query = plain_query ("(\\w+)-(\\w+)");
            query.regex_enabled = true;
            var result = FindInFilesSearch.run (root_path, query, 0);
            FindInFilesReplace.run (result, "$2-$1");

            assert (read_file_contents (path) == "last-first");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-replace/whole-word-leaves-a-substring-match-untouched", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "foobar foo");

            var query = plain_query ("foo");
            query.whole_word_enabled = true;
            var result = FindInFilesSearch.run (root_path, query, 0);
            FindInFilesReplace.run (result, "baz");

            assert (read_file_contents (path) == "foobar baz");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-replace/skips-a-file-that-vanished-instead-of-aborting-the-batch", () => {
        var query = plain_query ("needle");
        var result = new FindInFilesResult ();
        result.query = query;
        result.searched_at = new DateTime.now_local ();
        var file = new FindInFilesFileResult ();
        file.path = "/nonexistent/path/does-not-exist.txt";
        result.files.add (file);

        try {
            var outcome = FindInFilesReplace.run (result, "pin");
            assert (outcome.skipped_paths.length == 1);
            assert (outcome.skipped_paths[0] == file.path);
        } catch (Error e) {
            error (e.message); // shouldn't throw at all — a per-file failure is recorded, not propagated
        }
    });

    Test.add_func ("/find-in-files-replace/one-vanished-file-doesnt-stop-the-others-from-being-replaced", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "needle");

            var result = FindInFilesSearch.run (root_path, plain_query ("needle"), 0);
            // Add a second, nonexistent file to the same result, as if it
            // vanished between search and replace.
            var vanished = new FindInFilesFileResult ();
            vanished.path = Path.build_filename (root_path, "gone.txt");
            result.files.add (vanished);

            var outcome = FindInFilesReplace.run (result, "pin");

            assert (outcome.skipped_paths.length == 1);
            assert (outcome.skipped_paths[0] == vanished.path);
            assert (read_file_contents (path) == "pin");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-replace/skips-a-file-modified-after-the-search-ran", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello world");

            var result = FindInFilesSearch.run (root_path, plain_query ("world"), 0);

            // Set squarely in the future relative to result.searched_at
            // (captured just before the search walked this file) —
            // deterministic, no race against real mtime granularity.
            var future = new DateTime.now_local ().add_seconds (60);
            File.new_for_path (path).set_attribute_uint64 (
                FileAttribute.TIME_MODIFIED, (uint64) future.to_unix (), FileQueryInfoFlags.NONE
            );

            var outcome = FindInFilesReplace.run (result, "opus");

            assert (outcome.skipped_paths.length == 1);
            assert (outcome.skipped_paths[0] == path);
            assert (read_file_contents (path) == "hello world");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/find-in-files-replace/reports-where-each-replacement-landed", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "foo\nbar foo");

            var result = FindInFilesSearch.run (root_path, plain_query ("foo"), 0);
            var outcome = FindInFilesReplace.run (result, "opuseditor");

            assert (outcome.skipped_paths.length == 0);
            var matches = outcome.new_matches_by_path[path];
            assert (matches.length == 2);
            assert (matches[0].line_number == 1);
            assert (matches[0].start_column == 0 && matches[0].end_column == 10);
            assert (matches[1].line_number == 2);
            assert (matches[1].start_column == 4 && matches[1].end_column == 14);

            assert (read_file_contents (path) == "opuseditor\nbar opuseditor");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
