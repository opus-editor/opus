/**
 * The diff in the Git view's main area, end to end: a single click in
 * the staging lists or a double-click in a commit's files puts the
 * file's inline diff under the breadcrumb, with old/new numbers and
 * +/- markers; placeholders for what can't be diffed; a live diff
 * follows a stage; and a conflicted file opens in the editor with its
 * Accept buttons.
 */

private const uint DISPLAY = 116;

private string make_repo () throws Error {
    var root = DirUtils.make_tmp ("opus-diff-view-test-XXXXXX");
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

private void write_file (string root, string name, string contents) throws Error {
    FileUtils.set_contents (Path.build_filename (root, name), contents);
}

private void commit_file (string root, string name, string contents, string message) throws Error {
    write_file (root, name, contents);
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

/** a.txt committed as three lines, then edited on disk: one line changed, one added. */
private void edited (string root) throws Error {
    commit_file (root, "a.txt", "one\ntwo\nthree\n", "base");
    write_file (root, "a.txt", "one\nTWO\nthree\nfour\n");
}

private void conflicted (string root) throws Error {
    commit_file (root, "a.txt", "base\n", "base");
    git (root, { "checkout", "-q", "-b", "side" });
    commit_file (root, "a.txt", "theirs\n", "side");
    git (root, { "checkout", "-q", "main" });
    commit_file (root, "a.txt", "ours\n", "main");
    git (root, { "merge", "side" });
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/diff/a_click_on_an_unstaged_file_shows_its_diff_under_the_breadcrumb", () => run (edited, (root, opus) => {
        opus.wait_for_git_changes ("unstaged", { "M a.txt" });
        assert_cmpstr (opus.git_content_showing (), CompareOperator.EQ, "tree");

        opus.git_select_row ("unstaged", "a.txt");

        opus.wait_for_diff_lines ({ "1|1| |one", "2|0|-|two", "0|2|+|TWO", "3|3| |three", "0|4|+|four" });
        assert_cmpstr (opus.git_content_showing (), CompareOperator.EQ, "diff");
        assert_cmpstr (opus.diff_mode (), CompareOperator.EQ, "diff");
        assert_cmpstr (opus.git_breadcrumb (), CompareOperator.EQ, "History / WIP / a.txt");
    }));

    Test.add_func ("/system/diff/history_in_the_breadcrumb_goes_back_to_the_tree", () => run (edited, (root, opus) => {
        opus.wait_for_git_changes ("unstaged", { "M a.txt" });
        opus.git_select_row ("unstaged", "a.txt");
        opus.wait_for_diff_lines ({ "1|1| |one", "2|0|-|two", "0|2|+|TWO", "3|3| |three", "0|4|+|four" });

        opus.git_show_tree ();

        assert_cmpstr (opus.git_content_showing (), CompareOperator.EQ, "tree");
        assert_cmpstr (opus.git_breadcrumb (), CompareOperator.EQ, "History");
    }));

    Test.add_func ("/system/diff/a_staged_file_diffs_head_against_the_index", () => run ((root) => {
        commit_file (root, "a.txt", "one\n", "base");
        write_file (root, "a.txt", "one\ntwo\n");
        git (root, { "add", "a.txt" });
        write_file (root, "a.txt", "one\ntwo\nthree\n");
    }, (root, opus) => {
        opus.wait_for_git_changes ("staged", { "M a.txt" });

        opus.git_select_row ("staged", "a.txt");

        opus.wait_for_diff_lines ({ "1|1| |one", "0|2|+|two" }); // not the unstaged "three"
    }));

    Test.add_func ("/system/diff/a_file_with_one_side_shows_plainly_not_as_a_diff", () => run ((root) => {
        commit_file (root, "gone.txt", "x\ny\n", "base");
        FileUtils.remove (Path.build_filename (root, "gone.txt"));
        write_file (root, "new.txt", "n\n");
    }, (root, opus) => {
        opus.wait_for_git_changes ("unstaged", { "D gone.txt", "U new.txt" });

        opus.git_select_row ("unstaged", "new.txt");
        opus.wait_for_diff_lines ({ "1|1| |n" });
        assert_cmpstr (opus.diff_mode (), CompareOperator.EQ, "plain");

        opus.git_select_row ("unstaged", "gone.txt");
        opus.wait_for_diff_lines ({ "1|1| |x", "2|2| |y" });
        assert_cmpstr (opus.diff_mode (), CompareOperator.EQ, "plain");
    }));

    Test.add_func ("/system/diff/a_live_diff_follows_a_stage", () => run (edited, (root, opus) => {
        opus.wait_for_git_changes ("unstaged", { "M a.txt" });
        opus.git_select_row ("unstaged", "a.txt");
        opus.wait_for_diff_lines ({ "1|1| |one", "2|0|-|two", "0|2|+|TWO", "3|3| |three", "0|4|+|four" });

        opus.git_stage_all ();

        // index and worktree now agree: the same request shows only context
        opus.wait_for_diff_lines ({ "1|1| |one", "2|2| |TWO", "3|3| |three", "4|4| |four" });
    }));

    Test.add_func ("/system/diff/a_commits_file_opens_from_the_history_pane", () => run ((root) => {
        commit_file (root, "a.txt", "one\n", "first");
        commit_file (root, "a.txt", "one\ntwo\n", "second");
    }, (root, opus) => {
        opus.wait_for_tree_row_count (2);
        var second = git_read (root, { "rev-parse", "--short", "HEAD" });
        opus.tree_select (second);
        opus.wait_for_history_files ({ "M a.txt" });

        opus.history_open_file ("a.txt");

        opus.wait_for_diff_lines ({ "1|1| |one", "0|2|+|two" });
        assert_cmpstr (opus.git_breadcrumb (), CompareOperator.EQ, "History / %s / a.txt".printf (second));
    }));

    Test.add_func ("/system/diff/a_binary_file_gets_a_placeholder", () => run ((root) => {
        FileUtils.set_data (Path.build_filename (root, "pic.png"), { 'P', 'N', 'G', 0, 1, 2 });
    }, (root, opus) => {
        opus.wait_for_git_changes ("unstaged", { "U pic.png" });

        opus.git_select_row ("unstaged", "pic.png");

        assert_cmpstr (opus.wait_for_diff_placeholder (), CompareOperator.EQ, "Binary file");
        assert_cmpstr (opus.git_breadcrumb (), CompareOperator.EQ, "History / WIP / pic.png");
    }));

    Test.add_func ("/system/diff/a_conflicted_file_opens_in_the_editor_with_accept_buttons", () => run (conflicted, (root, opus) => {
        opus.wait_for_git_changes ("conflicts", { "UU a.txt" });

        opus.git_select_row ("conflicts", "a.txt");

        opus.wait_for_conflict_count (1);
        assert_cmpstr (opus.current_view (), CompareOperator.EQ, "editor");
        assert_true (opus.active_tab ().has_suffix ("/a.txt"));

        opus.accept_conflict (0, "incoming");

        assert_cmpstr (opus.active_text (), CompareOperator.EQ, "theirs\n");
        opus.wait_for_conflict_count (0);
    }));

    Test.add_func ("/system/diff/accept_both_keeps_current_then_incoming", () => run (conflicted, (root, opus) => {
        opus.wait_for_git_changes ("conflicts", { "UU a.txt" });
        opus.git_select_row ("conflicts", "a.txt");
        opus.wait_for_conflict_count (1);

        opus.accept_conflict (0, "both");

        assert_cmpstr (opus.active_text (), CompareOperator.EQ, "ours\ntheirs\n");
    }));

    Test.add_func ("/system/diff/solve_all_opens_every_conflicted_file", () => run ((root) => {
        commit_file (root, "a.txt", "base\n", "base a");
        commit_file (root, "b.txt", "base\n", "base b");
        git (root, { "checkout", "-q", "-b", "side" });
        commit_file (root, "a.txt", "theirs\n", "side a");
        commit_file (root, "b.txt", "theirs\n", "side b");
        git (root, { "checkout", "-q", "main" });
        commit_file (root, "a.txt", "ours\n", "main a");
        commit_file (root, "b.txt", "ours\n", "main b");
        git (root, { "merge", "side" });
    }, (root, opus) => {
        opus.wait_for_git_changes ("conflicts", { "UU a.txt", "UU b.txt" });

        opus.git_solve_all ();

        opus.wait_for_conflict_count (1);
        assert_cmpint (opus.open_tabs ().length, CompareOperator.EQ, 2);
    }));

    return Test.run ();
}
