/**
 * Find in Files opens its results in a tab of its own kind, next to the
 * file tabs: the search must open "Find Results" and make it active,
 * list it alongside the file, and closing it must hand the active slot
 * back to a file tab — the whole add/activate/remove route a non-
 * Document tab takes through EditorPaneWidget's registry.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/find_in_files_tab/opens_activates_and_closes_the_results_tab", () => {
        string? folder = null;
        try {
            folder = DirUtils.make_tmp ("opus-find-in-files-XXXXXX");
            var file_path = Path.build_filename (folder, "haystack.txt");
            FileUtils.set_contents (file_path, "one needle\ntwo\n");

            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 106, folder);
            opus.open_tab (file_path);
            opus.assert_active_tab (file_path);

            opus.find_in_files ("needle");
            opus.wait_for_active_tab ("Find Results");

            var open_tabs = opus.open_tabs ();
            assert_cmpint (open_tabs.length, CompareOperator.EQ, 2);
            assert_true (file_path in open_tabs);
            assert_true ("Find Results" in open_tabs);

            opus.close_tab ("Find Results");
            opus.assert_active_tab (file_path);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        } finally {
            if (folder != null) {
                FileUtils.remove (Path.build_filename (folder, "haystack.txt"));
                DirUtils.remove (folder);
            }
        }
    });

    return Test.run ();
}
