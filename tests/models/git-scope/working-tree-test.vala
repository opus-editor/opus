// What StagingPane actually needs GitScope.WorkingTree for: splitting a
// repo's live status into staged vs unstaged, keeping a deleted file
// instead of dropping it the way GitStatus (file-decoration) does.
// GitStatus's own git-status-classify-test.vala already covers the
// X/Y-column-to-label mapping in depth; this only covers the bucketing
// GitStatus doesn't have to do at all.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-scope-working-tree-test-XXXXXX");
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

/** Runs a real `git` command in `root_path` for a test fixture's own setup — never the thing under test itself (that's GitScope.WorkingTree's own run()). */
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

/** A fresh repo with committer identity set — needed here (unlike status-query-test.vala) since several fixtures below actually commit. */
private void init_repo (string root_path) throws Error {
    run_git (root_path, { "init", "-q", "-b", "main" });
    run_git (root_path, { "config", "user.email", "test@opus.dev" });
    run_git (root_path, { "config", "user.name", "Opus Test" });
}

private bool has_change (GenericArray<GitScope.Change> changes, string path, GitScope.ChangeKind kind) {
    for (uint i = 0; i < changes.length; i++) {
        if (changes[i].path == path && changes[i].kind == kind) {
            return true;
        }
    }
    return false;
}

/** A real merge conflict on a.txt: "base" committed on main, then both main and side rewrite its one line. The merge stops with MERGE_HEAD parked. */
private void init_conflict (string root_path) throws Error {
    init_repo (root_path);
    FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "base\n");
    run_git (root_path, { "add", "a.txt" });
    run_git (root_path, { "commit", "-q", "-m", "base" });
    run_git (root_path, { "checkout", "-q", "-b", "side" });
    FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "theirs\n");
    run_git (root_path, { "commit", "-q", "-am", "side" });
    run_git (root_path, { "checkout", "-q", "main" });
    FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "ours\n");
    run_git (root_path, { "commit", "-q", "-am", "main" });
    run_git (root_path, { "merge", "side" });
}

private void commit_file (string root_path, string name, string contents, string message) throws Error {
    FileUtils.set_contents (Path.build_filename (root_path, name), contents);
    run_git (root_path, { "add", name });
    run_git (root_path, { "commit", "-q", "-m", message });
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-scope-working-tree/an-untracked-file-is-unstaged-only", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree != null);
            assert (has_change (tree.unstaged, path, GitScope.ChangeKind.UNTRACKED));
            assert (tree.staged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/a-newly-staged-file-is-staged-only", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree != null);
            assert (has_change (tree.staged, path, GitScope.ChangeKind.ADDED));
            assert (tree.unstaged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/an-unstaged-edit-to-a-tracked-file-is-unstaged-only", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "add a.txt" });
            FileUtils.set_contents (path, "hello world");

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree != null);
            assert (has_change (tree.unstaged, path, GitScope.ChangeKind.MODIFIED));
            assert (tree.staged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/a-fully-staged-edit-is-staged-only", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "add a.txt" });
            FileUtils.set_contents (path, "hello world");
            run_git (root_path, { "add", "a.txt" });

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree != null);
            assert (has_change (tree.staged, path, GitScope.ChangeKind.MODIFIED));
            assert (tree.unstaged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/a-partially-staged-edit-is-both-staged-and-unstaged", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "add a.txt" });
            FileUtils.set_contents (path, "hello world");
            run_git (root_path, { "add", "a.txt" });
            FileUtils.set_contents (path, "hello world again");

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree != null);
            assert (has_change (tree.staged, path, GitScope.ChangeKind.MODIFIED));
            assert (has_change (tree.unstaged, path, GitScope.ChangeKind.MODIFIED));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/an-unstaged-delete-is-kept-as-deleted", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "add a.txt" });
            FileUtils.remove (path);

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree != null);
            assert (has_change (tree.unstaged, path, GitScope.ChangeKind.DELETED));
            assert (tree.staged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/a-staged-delete-is-staged-only", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "hello");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "add a.txt" });
            run_git (root_path, { "rm", "-q", "a.txt" });

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree != null);
            assert (has_change (tree.staged, path, GitScope.ChangeKind.DELETED));
            assert (tree.unstaged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/outside-a-repository-is-null", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree == null);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/label-matches-each-kind", () => {
        assert (new GitScope.Change ("a", GitScope.ChangeKind.ADDED).label == "Added");
        assert (new GitScope.Change ("a", GitScope.ChangeKind.MODIFIED).label == "Modified");
        assert (new GitScope.Change ("a", GitScope.ChangeKind.DELETED).label == "Deleted");
        assert (new GitScope.Change ("a", GitScope.ChangeKind.RENAMED).label == "Renamed");
        assert (new GitScope.Change ("a", GitScope.ChangeKind.COPIED).label == "Copied");
        assert (new GitScope.Change ("a", GitScope.ChangeKind.TYPE_CHANGED).label == "Type Changed");
        assert (new GitScope.Change ("a", GitScope.ChangeKind.UNTRACKED).label == "Untracked");
        assert (new GitScope.Change ("a", GitScope.ChangeKind.CONFLICT).label == "Conflicted");
    });

    Test.add_func ("/git-scope-working-tree/a-conflicted-file-is-in-conflicts-only-with-the-merge-parked", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            var path = Path.build_filename (root_path, "a.txt");

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree != null);
            assert (has_change (tree.conflicts, path, GitScope.ChangeKind.CONFLICT));
            assert (tree.unstaged.length == 0);
            assert (tree.staged.length == 0);
            assert (tree.operation == GitScope.OperationKind.MERGE);
            assert (tree.prepared_message.has_prefix ("Merge branch 'side'"));
            assert (!tree.prepared_message.contains ("#"));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/a-file-deleted-by-them-is-its-own-conflict-kind", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "base\n");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "base" });
            run_git (root_path, { "checkout", "-q", "-b", "side" });
            run_git (root_path, { "rm", "-q", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "side deletes" });
            run_git (root_path, { "checkout", "-q", "main" });
            FileUtils.set_contents (path, "ours\n");
            run_git (root_path, { "commit", "-q", "-am", "main edits" });
            run_git (root_path, { "merge", "side" });

            var tree = GitScope.WorkingTree.run (root_path);

            assert (has_change (tree.conflicts, path, GitScope.ChangeKind.DELETED_BY_THEM));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/no-operation-outside-a-merge", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree.operation == GitScope.OperationKind.NONE);
            assert (tree.prepared_message == "");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/a-staged-rename-keeps-its-old-path", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var old_path = Path.build_filename (root_path, "a.txt");
            var new_path = Path.build_filename (root_path, "b.txt");
            FileUtils.set_contents (old_path, "same contents, moved");
            run_git (root_path, { "add", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "add a.txt" });
            run_git (root_path, { "mv", "a.txt", "b.txt" });

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree.staged.length == 1);
            assert (tree.staged[0].path == new_path);
            assert (tree.staged[0].kind == GitScope.ChangeKind.RENAMED);
            assert (tree.staged[0].old_path == old_path);
            assert (tree.unstaged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/conflicts-staged-and-unstaged-coexist-during-one-merge", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base\n", "base a");
            commit_file (root_path, "b.txt", "base\n", "base b");
            run_git (root_path, { "checkout", "-q", "-b", "side" });
            commit_file (root_path, "a.txt", "theirs\n", "side a");
            commit_file (root_path, "b.txt", "side b\n", "side b");
            run_git (root_path, { "checkout", "-q", "main" });
            commit_file (root_path, "a.txt", "ours\n", "main a");
            run_git (root_path, { "merge", "side" });
            var c = Path.build_filename (root_path, "c.txt");
            FileUtils.set_contents (c, "typed during the merge");

            var tree = GitScope.WorkingTree.run (root_path);

            assert (has_change (tree.conflicts, Path.build_filename (root_path, "a.txt"), GitScope.ChangeKind.CONFLICT));
            assert (has_change (tree.staged, Path.build_filename (root_path, "b.txt"), GitScope.ChangeKind.MODIFIED)); // auto-merged, staged by git
            assert (has_change (tree.unstaged, c, GitScope.ChangeKind.UNTRACKED));
            assert (tree.operation == GitScope.OperationKind.MERGE);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/both-added-is-a-conflict-with-code-aa", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "base.txt", "x", "base");
            run_git (root_path, { "checkout", "-q", "-b", "side" });
            commit_file (root_path, "new.txt", "theirs", "side adds");
            run_git (root_path, { "checkout", "-q", "main" });
            commit_file (root_path, "new.txt", "ours", "main adds");
            run_git (root_path, { "merge", "side" });

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree.conflicts.length == 1);
            assert (tree.conflicts[0].kind == GitScope.ChangeKind.CONFLICT);
            assert (tree.conflicts[0].conflict_code == "AA");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/a-file-deleted-by-us-is-its-own-conflict-kind", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base\n", "base");
            run_git (root_path, { "checkout", "-q", "-b", "side" });
            commit_file (root_path, "a.txt", "theirs\n", "side edits");
            run_git (root_path, { "checkout", "-q", "main" });
            run_git (root_path, { "rm", "-q", "a.txt" });
            run_git (root_path, { "commit", "-q", "-m", "main deletes" });
            run_git (root_path, { "merge", "side" });

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree.conflicts.length == 1);
            assert (tree.conflicts[0].kind == GitScope.ChangeKind.DELETED_BY_US);
            assert (tree.conflicts[0].conflict_code == "DU");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/a-parked-rebase-is-detected-with-the-stopped-commits-message", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            run_git (root_path, { "merge", "--abort" });
            run_git (root_path, { "rebase", "side" }); // main's "main" commit replays onto side and clashes

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree.operation == GitScope.OperationKind.REBASE);
            assert (tree.conflicts.length == 1);
            assert (tree.prepared_message == "main");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/a-parked-revert-is-detected", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_conflict (root_path);
            run_git (root_path, { "merge", "--abort" });
            run_git (root_path, { "revert", "--no-edit", "HEAD~1" }); // undoing "base" clashes with "main"'s edit

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree.operation == GitScope.OperationKind.REVERT);
            assert (tree.conflicts.length == 1);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/an-ignored-file-is-not-a-change", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            FileUtils.set_contents (Path.build_filename (root_path, ".gitignore"), "*.log\n");
            run_git (root_path, { "add", ".gitignore" });
            run_git (root_path, { "commit", "-q", "-m", "ignore logs" });
            FileUtils.set_contents (Path.build_filename (root_path, "debug.log"), "noise");

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree.unstaged.length == 0);
            assert (tree.staged.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/a-repository-with-no-commits-yet-still-answers", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var path = Path.build_filename (root_path, "a.txt");
            FileUtils.set_contents (path, "first");

            var tree = GitScope.WorkingTree.run (root_path);

            assert (tree != null);
            assert (has_change (tree.unstaged, path, GitScope.ChangeKind.UNTRACKED));
            assert (tree.operation == GitScope.OperationKind.NONE);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-scope-working-tree/is-conflict-covers-exactly-the-three-conflict-kinds", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            assert (GitScope.ChangeKind.CONFLICT.is_conflict ());
            assert (GitScope.ChangeKind.DELETED_BY_THEM.is_conflict ());
            assert (GitScope.ChangeKind.DELETED_BY_US.is_conflict ());
            assert (!GitScope.ChangeKind.DELETED.is_conflict ());
            assert (!GitScope.ChangeKind.MODIFIED.is_conflict ());
            assert (!GitScope.ChangeKind.UNTRACKED.is_conflict ());
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
