/**
 * GitView.TreePane end to end through the real window: the rows a
 * repository's history turns into — lanes, refs, the WIP and stash rows
 * — and that they follow the repository as it changes under the window,
 * keep the selection through a refresh, and page past the first 500.
 */

private const uint DISPLAY = 115;

private string make_repo () throws Error {
    var root = DirUtils.make_tmp ("opus-tree-pane-test-XXXXXX");
    git (root, { "init", "-q", "-b", "main" });
    git (root, { "config", "user.email", "test@opus.dev" });
    git (root, { "config", "user.name", "Opus Test" });
    return root;
}

private void git (string root, string[] args) throws Error {
    string[] argv = { "git" };
    foreach (var arg in args) {
        argv += arg;
    }
    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
    launcher.set_cwd (root);
    launcher.spawnv (argv).wait ();
}

private string git_read (string root, string[] args) throws Error {
    string[] argv = { "git" };
    foreach (var arg in args) {
        argv += arg;
    }
    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
    launcher.set_cwd (root);
    string output;
    launcher.spawnv (argv).communicate_utf8 (null, null, out output, null);
    return output.strip ();
}

private void commit_file (string root, string name, string contents, string message) throws Error {
    FileUtils.set_contents (Path.build_filename (root, name), contents);
    git (root, { "add", name });
    git (root, { "commit", "-q", "-m", message });
}

private void remove_recursive (string path) {
    if (FileUtils.test (path, FileTest.IS_DIR) && !FileUtils.test (path, FileTest.IS_SYMLINK)) {
        try {
            var dir = Dir.open (path);
            string? entry;
            while ((entry = dir.read_name ()) != null) {
                remove_recursive (Path.build_filename (path, entry));
            }
        } catch (Error e) {
            return;
        }
        DirUtils.remove (path);
    } else {
        FileUtils.remove (path);
    }
}

private delegate void Prepare (string root) throws Error;
private delegate void Scenario (string root, SystemTestSession opus) throws Error;

/** A fresh repository shaped by `prepare`, a fresh Opus on its Git view, the body, then both torn down. */
private void run (Prepare prepare, Scenario body) {
    string root = "";
    SystemTestSession? opus = null;
    try {
        root = make_repo ();
        prepare (root);
        opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, root);
        opus.show_git ();
        body (root, opus);
    } catch (Error e) {
        error ("unexpected error: %s", e.message);
    } finally {
        if (opus != null) {
            opus.close ();
        }
        remove_recursive (root);
    }
}

private void linear (string root) throws Error {
    commit_file (root, "a.txt", "1\n", "one");
    commit_file (root, "a.txt", "2\n", "two");
    commit_file (root, "a.txt", "3\n", "three");
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/tree/a_linear_history_is_one_lane_newest_first", () => run (linear, (root, opus) => {
        opus.wait_for_tree_rows ({ "COMMIT|0|*main|three", "COMMIT|0||two", "COMMIT|0||one" });
    }));

    Test.add_func ("/system/tree/a_merge_puts_the_side_branch_in_its_own_lane", () => run ((root) => {
        commit_file (root, "a.txt", "base\n", "base");
        git (root, { "checkout", "-q", "-b", "side" });
        commit_file (root, "b.txt", "side\n", "on side");
        git (root, { "checkout", "-q", "main" });
        commit_file (root, "c.txt", "main\n", "on main");
        git (root, { "merge", "-q", "--no-ff", "-m", "merge side", "side" });
    }, (root, opus) => {
        opus.wait_for_tree_rows ({ "COMMIT|0|*main|merge side", "COMMIT|1|side|on side", "COMMIT|0||on main", "COMMIT|0||base" });
    }));

    Test.add_func ("/system/tree/the_working_tree_shows_as_a_wip_row_until_committed", () => run (linear, (root, opus) => {
        opus.wait_for_tree_row_count (3);
        FileUtils.set_contents (Path.build_filename (root, "a.txt"), "edited\n");
        opus.wait_for_tree_rows ({ "WIP|0||+1", "COMMIT|0|*main|three", "COMMIT|0||two", "COMMIT|0||one" });

        opus.git_stage_all ();
        opus.wait_for_git_changes ("staged", { "M a.txt" });
        opus.git_set_commit_message ("four");
        opus.git_commit ();

        opus.wait_for_tree_rows ({ "COMMIT|0|*main|four", "COMMIT|0||three", "COMMIT|0||two", "COMMIT|0||one" });
    }));

    Test.add_func ("/system/tree/a_commit_made_outside_shows_up_on_its_own", () => run (linear, (root, opus) => {
        opus.wait_for_tree_row_count (3);

        commit_file (root, "b.txt", "new\n", "from the terminal");

        opus.wait_for_tree_rows ({ "COMMIT|0|*main|from the terminal", "COMMIT|0||three", "COMMIT|0||two", "COMMIT|0||one" });
    }));

    Test.add_func ("/system/tree/a_stash_gets_a_row_above_its_base", () => run (linear, (root, opus) => {
        opus.wait_for_tree_row_count (3);

        FileUtils.set_contents (Path.build_filename (root, "a.txt"), "parked\n");
        git (root, { "stash", "push", "-m", "parked work" });

        opus.wait_for_tree_rows ({ "STASH|0||parked work", "COMMIT|0|*main|three", "COMMIT|0||two", "COMMIT|0||one" });
    }));

    Test.add_func ("/system/tree/the_selection_survives_a_refresh", () => run (linear, (root, opus) => {
        opus.wait_for_tree_row_count (3);
        var two = git_read (root, { "rev-parse", "--short", "HEAD~1" });
        opus.tree_select (two);
        assert_cmpstr (opus.tree_selected (), CompareOperator.EQ, two);

        commit_file (root, "b.txt", "new\n", "four");
        opus.wait_for_tree_row_count (4);

        assert_cmpstr (opus.tree_selected (), CompareOperator.EQ, two);
    }));

    Test.add_func ("/system/tree/refs_show_the_head_branch_first_then_the_rest_folded", () => run ((root) => {
        commit_file (root, "a.txt", "1\n", "one");
        git (root, { "tag", "v1" });
        git (root, { "branch", "other" });
    }, (root, opus) => {
        opus.wait_for_tree_rows ({ "COMMIT|0|*main,other,v1|one" });
    }));

    Test.add_func ("/system/tree/history_past_the_first_page_loads_on_demand", () => run ((root) => {
        commit_file (root, "a.txt", "0\n", "c0");
        var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
        launcher.set_cwd (root);
        launcher.spawnv ({ "sh", "-c", "for i in $(seq 1 519); do git commit -q --allow-empty -m \"c$i\"; done" }).wait ();
    }, (root, opus) => {
        opus.wait_for_tree_row_count (500);
        assert_cmpint (opus.tree_loaded (), CompareOperator.EQ, 500);
        assert_true (opus.tree_rows_without_hash ()[0] == "COMMIT|0|*main|c519");

        opus.tree_load_more ();

        opus.wait_for_tree_row_count (520);
        assert_true (opus.tree_rows_without_hash ()[519] == "COMMIT|0||c0");
    }));

    Test.add_func ("/system/tree/selecting_a_commit_swaps_the_sidebar_for_its_history", () => run ((root) => {
        commit_file (root, "a.txt", "1\n", "one");
        FileUtils.set_contents (Path.build_filename (root, "a.txt"), "2\n");
        FileUtils.set_contents (Path.build_filename (root, "b.txt"), "b\n");
        git (root, { "add", "-A" });
        git (root, { "commit", "-q", "-m", "two" });
    }, (root, opus) => {
        opus.wait_for_tree_row_count (2);
        assert_cmpstr (opus.git_sidebar_pane (), CompareOperator.EQ, "staging");
        var two = git_read (root, { "rev-parse", "--short", "HEAD" });

        opus.tree_select (two);

        opus.wait_for_git_sidebar_pane ("history");
        assert_cmpstr (opus.history_header (), CompareOperator.EQ, "Commit: " + two);
        opus.wait_for_history_files ({ "M a.txt", "A b.txt" });

        opus.history_back ();
        opus.wait_for_git_sidebar_pane ("staging");
    }));

    Test.add_func ("/system/tree/selecting_the_wip_row_brings_the_staging_sidebar_back", () => run (linear, (root, opus) => {
        opus.wait_for_tree_row_count (3);
        var head = git_read (root, { "rev-parse", "--short", "HEAD" });
        opus.tree_select (head);
        opus.wait_for_git_sidebar_pane ("history");
        FileUtils.set_contents (Path.build_filename (root, "a.txt"), "edited\n");
        opus.wait_for_tree_row_count (4);

        opus.tree_select_wip ();

        opus.wait_for_git_sidebar_pane ("staging");
    }));

    return Test.run ();
}
