/**
 * GitView.StagingPane end to end through the real window: a real
 * repository per test, driven the way a person would — the lists, Stage
 * All/Unstage All, a row's double-click, the "…" resolutions, the
 * commit/Merge/Abort buttons — with every dialog answered the way a
 * click would (SystemTestGit.respond()). Every list read is a wait: the
 * pane refreshes asynchronously, debounced.
 */

private const uint DISPLAY = 126;

private string make_repo () throws Error {
    var root = DirUtils.make_tmp ("opus-staging-pane-test-XXXXXX");
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

private void write_file (string root, string name, string contents) throws Error {
    FileUtils.set_contents (Path.build_filename (root, name), contents);
}

private string read_file (string root, string name) throws Error {
    string contents;
    FileUtils.get_contents (Path.build_filename (root, name), out contents);
    return contents;
}

private void commit_file (string root, string name, string contents, string message) throws Error {
    write_file (root, name, contents);
    git (root, { "add", name });
    git (root, { "commit", "-q", "-m", message });
}

/** a.txt rewritten differently on main and side, `git merge side` parked on the conflict. */
private string make_conflict_repo () throws Error {
    var root = make_repo ();
    commit_file (root, "a.txt", "base\n", "base");
    git (root, { "checkout", "-q", "-b", "side" });
    commit_file (root, "a.txt", "theirs\n", "side");
    git (root, { "checkout", "-q", "main" });
    commit_file (root, "a.txt", "ours\n", "main");
    git (root, { "merge", "side" });
    return root;
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

private SystemTestSession open (string root) throws Error {
    var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, root);
    opus.show_git ();
    return opus;
}

private delegate void Scenario (string root, SystemTestSession opus) throws Error;

/** One test's whole life: a fresh repository (parked on a merge conflict when `conflict`), a fresh Opus on its Git view, the body, then both torn down. */
private void run (bool conflict, Scenario body) {
    string root = "";
    SystemTestSession? opus = null;
    try {
        root = conflict ? make_conflict_repo () : make_repo ();
        opus = open (root);
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

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/git/an_edit_moves_between_unstaged_and_staged", () => run (false, (root, opus) => {
        commit_file (root, "a.txt", "hello\n", "add a.txt");
        write_file (root, "a.txt", "hello world\n");
        opus.wait_for_git_changes ("unstaged", { "M a.txt" });
        opus.wait_for_git_changes ("staged", {});

        opus.git_stage_all ();
        opus.wait_for_git_changes ("staged", { "M a.txt" });
        opus.wait_for_git_changes ("unstaged", {});

        opus.git_unstage_all ();
        opus.wait_for_git_changes ("unstaged", { "M a.txt" });
        opus.wait_for_git_changes ("staged", {});
    }));

    Test.add_func ("/system/git/a_rows_double_click_stages_just_that_row", () => run (false, (root, opus) => {
        commit_file (root, "a.txt", "a\n", "add a.txt");
        write_file (root, "a.txt", "a changed\n");
        write_file (root, "b.txt", "new\n");
        opus.wait_for_git_changes ("unstaged", { "M a.txt", "U b.txt" });

        opus.git_activate ("unstaged", "b.txt");

        opus.wait_for_git_changes ("staged", { "A b.txt" });
        opus.wait_for_git_changes ("unstaged", { "M a.txt" });
    }));

    Test.add_func ("/system/git/unstaging_a_rename_brings_both_paths_back", () => run (false, (root, opus) => {
        commit_file (root, "a.txt", "same contents, moved\n", "add a.txt");
        git (root, { "mv", "a.txt", "b.txt" });
        opus.wait_for_git_changes ("staged", { "R b.txt" });

        opus.git_unstage_all ();

        opus.wait_for_git_changes ("staged", {});
        opus.wait_for_git_changes ("unstaged", { "D a.txt", "U b.txt" });
    }));

    Test.add_func ("/system/git/the_commit_button_needs_something_staged_and_a_message", () => run (false, (root, opus) => {
        commit_file (root, "a.txt", "a\n", "add a.txt");
        write_file (root, "a.txt", "a changed\n");
        opus.wait_for_git_changes ("unstaged", { "M a.txt" });
        assert_cmpstr (opus.git_commit_label (), CompareOperator.EQ, "Commit to main");
        assert_false (opus.git_commit_enabled ());

        opus.git_set_commit_message ("rev: a.txt");
        assert_false (opus.git_commit_enabled ());
        opus.git_stage_all ();
        opus.wait_for_git_commit_enabled (true);

        opus.git_commit ();
        opus.wait_for_git_changes ("staged", {});
        assert_cmpstr (opus.git_commit_message (), CompareOperator.EQ, "");
        assert_cmpstr (read_file (root, "a.txt"), CompareOperator.EQ, "a changed\n");
    }));

    Test.add_func ("/system/git/discard_all_asks_first_and_cancel_keeps_everything", () => run (false, (root, opus) => {
        commit_file (root, "a.txt", "a\n", "add a.txt");
        write_file (root, "a.txt", "a changed\n");
        opus.wait_for_git_changes ("unstaged", { "M a.txt" });

        opus.git_discard_all ();
        assert_cmpstr (opus.wait_for_dialog (), CompareOperator.EQ, "Discard changes in “a.txt”?");
        opus.respond_to_dialog ("cancel");

        Thread.usleep (500 * 1000);
        assert_cmpstr (read_file (root, "a.txt"), CompareOperator.EQ, "a changed\n");
        assert_cmpstrv (opus.git_changes ("unstaged"), { "M a.txt" });
    }));

    Test.add_func ("/system/git/discard_all_confirmed_restores_the_files", () => run (false, (root, opus) => {
        commit_file (root, "a.txt", "a\n", "add a.txt");
        write_file (root, "a.txt", "a changed\n");
        write_file (root, "b.txt", "untracked\n");
        opus.wait_for_git_changes ("unstaged", { "M a.txt", "U b.txt" });

        opus.git_discard_all ();
        assert_cmpstr (opus.wait_for_dialog (), CompareOperator.EQ, "Discard changes in 2 files?");
        opus.respond_to_dialog ("confirm");

        opus.wait_for_git_changes ("unstaged", {});
        assert_cmpstr (read_file (root, "a.txt"), CompareOperator.EQ, "a\n");
        assert_false (FileUtils.test (Path.build_filename (root, "b.txt"), FileTest.EXISTS));
    }));

    Test.add_func ("/system/git/discarding_only_deleted_files_asks_to_restore_them", () => run (false, (root, opus) => {
        commit_file (root, "a.txt", "a\n", "add a.txt");
        commit_file (root, "b.txt", "b\n", "add b.txt");
        FileUtils.remove (Path.build_filename (root, "a.txt"));
        FileUtils.remove (Path.build_filename (root, "b.txt"));
        opus.wait_for_git_changes ("unstaged", { "D a.txt", "D b.txt" });

        opus.git_discard_all ();
        assert_cmpstr (opus.wait_for_dialog (), CompareOperator.EQ, "Restore all 2 files?");
        opus.respond_to_dialog ("confirm");

        opus.wait_for_git_changes ("unstaged", {});
        assert_cmpstr (read_file (root, "a.txt"), CompareOperator.EQ, "a\n");
    }));

    Test.add_func ("/system/git/discarding_only_untracked_files_asks_to_delete_them", () => run (false, (root, opus) => {
        write_file (root, "new.txt", "new\n");
        opus.wait_for_git_changes ("unstaged", { "U new.txt" });

        opus.git_discard_all ();
        assert_cmpstr (opus.wait_for_dialog (), CompareOperator.EQ, "Delete the untracked file “new.txt”?");
        opus.respond_to_dialog ("cancel");

        Thread.usleep (500 * 1000);
        assert_true (FileUtils.test (Path.build_filename (root, "new.txt"), FileTest.EXISTS));
    }));

    Test.add_func ("/system/git/a_git_failure_shows_as_a_toast_and_changes_nothing", () => run (false, (root, opus) => {
        write_file (root, "a.txt", "new\n");
        opus.wait_for_git_changes ("unstaged", { "U a.txt" });
        write_file (root, ".git/index.lock", "");

        opus.git_stage_all ();

        assert_cmpstr (opus.wait_for_git_failure (), CompareOperator.EQ, "Couldn’t stage the changes");
        assert_cmpstrv (opus.git_changes ("unstaged"), { "U a.txt" });
        assert_cmpstrv (opus.git_changes ("staged"), {});
    }));

    Test.add_func ("/system/git/a_merge_conflict_gets_its_own_list_and_the_merge_button", () => run (true, (root, opus) => {
        opus.wait_for_git_changes ("conflicts", { "UU a.txt" });
        opus.wait_for_git_changes ("unstaged", {});
        opus.wait_for_git_operation ("merge");

        assert_cmpstr (opus.git_commit_label (), CompareOperator.EQ, "Merge");
        assert_true (opus.git_commit_message ().has_prefix ("Merge branch 'side'"));
        assert_false (opus.git_commit_message ().contains ("#"));
        assert_false (opus.git_commit_enabled ());
    }));

    Test.add_func ("/system/git/accept_incoming_then_merge_closes_the_merge", () => run (true, (root, opus) => {
        opus.wait_for_git_changes ("conflicts", { "UU a.txt" });

        opus.git_accept_incoming ("a.txt");
        opus.wait_for_git_changes ("conflicts", {});
        opus.wait_for_git_changes ("staged", { "M a.txt" });
        assert_cmpstr (read_file (root, "a.txt"), CompareOperator.EQ, "theirs\n");
        opus.wait_for_git_commit_enabled (true);

        opus.git_commit ();
        opus.wait_for_git_operation ("none");
        opus.wait_for_git_changes ("staged", {});
        assert_cmpstr (opus.git_commit_label (), CompareOperator.EQ, "Commit to main");
        assert_cmpstr (opus.git_commit_message (), CompareOperator.EQ, "");
    }));

    Test.add_func ("/system/git/accept_current_leaves_nothing_staged_but_merge_still_goes", () => run (true, (root, opus) => {
        opus.wait_for_git_changes ("conflicts", { "UU a.txt" });

        opus.git_accept_current ("a.txt");
        opus.wait_for_git_changes ("conflicts", {});
        assert_cmpstr (read_file (root, "a.txt"), CompareOperator.EQ, "ours\n");
        opus.wait_for_git_commit_enabled (true);
        assert_cmpstrv (opus.git_changes ("staged"), {});

        opus.git_commit ();
        opus.wait_for_git_operation ("none");
    }));

    Test.add_func ("/system/git/staging_a_conflict_with_markers_asks_and_cancel_keeps_it", () => run (true, (root, opus) => {
        opus.wait_for_git_changes ("conflicts", { "UU a.txt" });

        opus.git_activate ("conflicts", "a.txt");
        assert_cmpstr (opus.wait_for_dialog (), CompareOperator.EQ, "Are you sure you want to stage “a.txt” with merge conflicts?");
        opus.respond_to_dialog ("cancel");

        Thread.usleep (500 * 1000);
        assert_cmpstrv (opus.git_changes ("conflicts"), { "UU a.txt" });
        assert_true (read_file (root, "a.txt").contains ("<<<<<<<"));
    }));

    Test.add_func ("/system/git/staging_a_conflict_with_markers_confirmed_stages_it_as_is", () => run (true, (root, opus) => {
        opus.wait_for_git_changes ("conflicts", { "UU a.txt" });

        opus.git_activate ("conflicts", "a.txt");
        opus.wait_for_dialog ();
        opus.respond_to_dialog ("confirm");

        opus.wait_for_git_changes ("conflicts", {});
        opus.wait_for_git_changes ("staged", { "M a.txt" });
        assert_true (read_file (root, "a.txt").contains ("<<<<<<<"));
    }));

    Test.add_func ("/system/git/a_conflict_resolved_by_hand_stages_without_a_question", () => run (true, (root, opus) => {
        opus.wait_for_git_changes ("conflicts", { "UU a.txt" });
        write_file (root, "a.txt", "ours and theirs, by hand\n");

        opus.git_activate ("conflicts", "a.txt");

        opus.wait_for_git_changes ("conflicts", {});
        opus.wait_for_git_changes ("staged", { "M a.txt" });
        assert_cmpstr (opus.dialog_heading (), CompareOperator.EQ, "");
    }));

    Test.add_func ("/system/git/a_file_they_deleted_asks_keep_or_delete", () => run (false, (root, opus) => {
        commit_file (root, "a.txt", "base\n", "base");
        git (root, { "checkout", "-q", "-b", "side" });
        git (root, { "rm", "-q", "a.txt" });
        git (root, { "commit", "-q", "-m", "side deletes" });
        git (root, { "checkout", "-q", "main" });
        commit_file (root, "a.txt", "ours\n", "main edits");
        git (root, { "merge", "side" });
        opus.wait_for_git_changes ("conflicts", { "UD a.txt" });

        opus.git_activate ("conflicts", "a.txt");
        assert_cmpstr (opus.wait_for_dialog (), CompareOperator.EQ, "Keep or delete “a.txt”?");
        opus.respond_to_dialog ("second");

        opus.wait_for_git_changes ("conflicts", {});
        opus.wait_for_git_changes ("staged", { "D a.txt" });
        assert_false (FileUtils.test (Path.build_filename (root, "a.txt"), FileTest.EXISTS));
    }));

    Test.add_func ("/system/git/abort_asks_first_and_then_drops_the_merge", () => run (true, (root, opus) => {
        opus.wait_for_git_operation ("merge");

        opus.git_abort ();
        assert_cmpstr (opus.wait_for_dialog (), CompareOperator.EQ, "Abort the merge?");
        opus.respond_to_dialog ("cancel");
        Thread.usleep (500 * 1000);
        assert_cmpstr (opus.git_operation (), CompareOperator.EQ, "merge");

        opus.git_abort ();
        opus.wait_for_dialog ();
        opus.respond_to_dialog ("confirm");

        opus.wait_for_git_operation ("none");
        opus.wait_for_git_changes ("conflicts", {});
        assert_cmpstr (opus.git_commit_message (), CompareOperator.EQ, "");
        assert_cmpstr (opus.git_commit_label (), CompareOperator.EQ, "Commit to main");
        assert_cmpstr (read_file (root, "a.txt"), CompareOperator.EQ, "ours\n");
    }));

    Test.add_func ("/system/git/a_parked_rebase_reads_continue_and_continues", () => run (true, (root, opus) => {
        git (root, { "merge", "--abort" });
        git (root, { "rebase", "side" });
        opus.wait_for_git_operation ("rebase");
        opus.wait_for_git_changes ("conflicts", { "UU a.txt" });
        assert_cmpstr (opus.git_commit_label (), CompareOperator.EQ, "Continue");
        assert_cmpstr (opus.git_commit_message (), CompareOperator.EQ, "main");

        opus.git_accept_incoming ("a.txt");
        opus.wait_for_git_changes ("conflicts", {});
        opus.wait_for_git_commit_enabled (true);
        opus.git_set_commit_message ("main, rebased");
        opus.git_commit ();

        opus.wait_for_git_operation ("none");
        var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
        launcher.set_cwd (root);
        string subject;
        launcher.spawnv ({ "git", "log", "-1", "--format=%s" }).communicate_utf8 (null, null, out subject, null);
        assert_cmpstr (subject.strip (), CompareOperator.EQ, "main, rebased");
    }));

    return Test.run ();
}
