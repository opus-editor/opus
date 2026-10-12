/**
 * Line endings, end to end: a CRLF file stays CRLF through an edit and
 * a save, and a folder's `end_of_line` rewrites a file's on save.
 */

private const uint DISPLAY = 119;

private string make_folder (string? editorconfig) throws Error {
    var folder = DirUtils.make_tmp ("opus-line-endings-test-XXXXXX");
    if (editorconfig != null) {
        FileUtils.set_contents (Path.build_filename (folder, ".editorconfig"), editorconfig);
    }
    return folder;
}

/** Edits `path`'s open tab to `text` and saves it, then returns what is on disk. */
private string edit_and_save (SystemTestSession opus, string path, string text) throws Error {
    opus.editor_write (text);
    opus.save_tab (path);
    string on_disk = "";
    int64 deadline = get_monotonic_time () + 5 * 1000 * 1000;
    while (get_monotonic_time () < deadline) {
        FileUtils.get_contents (path, out on_disk);
        if (on_disk.replace ("\r\n", "\n") == text) {
            break;
        }
        Thread.usleep (50 * 1000);
    }
    return on_disk;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/line_endings/a_crlf_file_is_saved_back_as_crlf", () => {
        try {
            var folder = make_folder (null);
            var path = Path.build_filename (folder, "a.txt");
            FileUtils.set_contents (path, "one\r\ntwo\r\n");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_tab (path);

            var on_disk = edit_and_save (opus, path, "one\ntwo\nthree\n");

            assert_cmpstr (on_disk, CompareOperator.EQ, "one\r\ntwo\r\nthree\r\n");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/line_endings/the_folders_end_of_line_rewrites_a_file_on_save", () => {
        try {
            var folder = make_folder ("[*]\nend_of_line = crlf\n");
            var path = Path.build_filename (folder, "a.txt");
            FileUtils.set_contents (path, "one\ntwo\n");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_tab (path);

            var on_disk = edit_and_save (opus, path, "one\ntwo\nthree\n");

            assert_cmpstr (on_disk, CompareOperator.EQ, "one\r\ntwo\r\nthree\r\n");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
