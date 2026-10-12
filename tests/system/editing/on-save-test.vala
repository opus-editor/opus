/**
 * editor.on_save, end to end: the listed functions rewrite the text as
 * it is saved, and the folder's .editorconfig switches its own two.
 */

private const uint DISPLAY = 116;
private const string SETTINGS = """{ "editor.on_save": ["trim-trailing-whitespace", "insert-final-newline"] }""";

private string make_folder (string? editorconfig) throws Error {
    var folder = DirUtils.make_tmp ("opus-on-save-test-XXXXXX");
    if (editorconfig != null) {
        FileUtils.set_contents (Path.build_filename (folder, ".editorconfig"), editorconfig);
    }
    return folder;
}

/** Saves `path`'s open tab and returns what is on disk once it changed. */
private string save_and_read (SystemTestSession opus, string path, string before) throws Error {
    opus.save_tab (path);
    string on_disk = before;
    int64 deadline = get_monotonic_time () + 5 * 1000 * 1000;
    while (on_disk == before && get_monotonic_time () < deadline) {
        Thread.usleep (50 * 1000);
        FileUtils.get_contents (path, out on_disk);
    }
    return on_disk;
}

private delegate void Scenario (string folder, string path, SystemTestSession opus) throws Error;
private void run (string? editorconfig, string? settings, Scenario body) {
    try {
        var folder = make_folder (editorconfig);
        var path = Path.build_filename (folder, "a.txt");
        FileUtils.set_contents (path, "a  \nb");
        var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder, settings);
        opus.open_tab (path);
        opus.editor_write ("a  \nb ");
        body (folder, path, opus);
        opus.close ();
    } catch (Error e) {
        error ("unexpected error: %s", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/on_save/the_listed_functions_rewrite_the_file_as_it_is_saved", () => run (null, SETTINGS, (folder, path, opus) => {
        var on_disk = save_and_read (opus, path, "a  \nb");

        assert_cmpstr (on_disk, CompareOperator.EQ, "a\nb\n");
        assert_cmpstr (opus.active_text (), CompareOperator.EQ, "a\nb\n");
    }));

    Test.add_func ("/system/on_save/the_folders_editorconfig_switches_a_function_off", () => run ("[*]\ntrim_trailing_whitespace = false\n", SETTINGS, (folder, path, opus) => {
        var on_disk = save_and_read (opus, path, "a  \nb");

        assert_cmpstr (on_disk, CompareOperator.EQ, "a  \nb \n");
    }));

    Test.add_func ("/system/on_save/the_folders_editorconfig_switches_a_function_on", () => run ("[*]\ninsert_final_newline = true\n", null, (folder, path, opus) => {
        var on_disk = save_and_read (opus, path, "a  \nb");

        assert_cmpstr (on_disk, CompareOperator.EQ, "a  \nb \n");
    }));

    return Test.run ();
}
