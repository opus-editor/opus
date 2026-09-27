/**
 * Closing the active tab, with other tabs still open, must activate
 * one of them instead of leaving the editor active-tab-less (was
 * showing a blank, unfocused editor rather than any Empty State at
 * all). Falls back to the rightmost remaining tab — see TabBarView.
 * last_tab_path()'s own doc comment for why not VS Code's MRU-stack
 * approach, at least for now.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/close_tab/falls_back_to_the_rightmost_remaining_tab", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 99);
            opus.new_file (); // Untitled-1
            opus.new_file (); // Untitled-2
            opus.new_file (); // Untitled-3, active

            opus.close_tab ("Untitled-3");

            opus.assert_active_tab ("Untitled-2"); // the new rightmost tab, not empty

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/close_tab/closing_the_last_tab_leaves_none_active", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 99);
            opus.new_file (); // Untitled-1, the only tab

            opus.close_tab ("Untitled-1");

            opus.assert_active_tab ("");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
