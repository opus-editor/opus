// GitDiff.Engine.compute_hunks needs a real `git` binary but not a real
// repo: `git diff --no-index` works on any two files regardless of git
// context, so this fixture is just a tmpdir holding plain base files —
// no init_repo()/run_git() machinery needed, unlike git-status's own
// fixtures.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-diff-engine-test-XXXXXX");
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

private string write_file (string root_path, string name, string content) throws Error {
    var path = Path.build_filename (root_path, name);
    FileUtils.set_contents (path, content);
    return path;
}

int main (string[] args) {
    Test.init (ref args);

    // Genuinely untracked (no HEAD blob, nothing staged either) — or
    // outside the repo/workspace entirely — shows nothing, matching VS
    // Code's own choice for an untracked file's gutter.
    Test.add_func ("/git-diff-engine/no-bases-at-all-is-no-hunks", () => {
        var hunks = GitDiff.Engine.compute_hunks (null, null, "a\nb\nc\n");
        assert (hunks.length == 0);
    });

    Test.add_func ("/git-diff-engine/no-head-base-and-empty-buffer-is-no-hunks", () => {
        var hunks = GitDiff.Engine.compute_hunks (null, null, "");
        assert (hunks.length == 0);
    });

    // A brand-new file that's been `git add`ed has no HEAD blob but does
    // have an index one — with no HEAD diff possible at all, the index
    // diff is the whole answer (confirmed against VS Code's own real
    // behavior: a staged-new file with no further edits shows nothing,
    // same as an untracked one — only what still differs from the index
    // shows at all).
    Test.add_func ("/git-diff-engine/staged-new-file-matching-the-index-shows-nothing", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var index = write_file (root_path, "index", "a\nb\nc\n");

            var hunks = GitDiff.Engine.compute_hunks (null, index, "a\nb\nc\n");
            assert (hunks.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-diff-engine/staged-new-file-edited-further-shows-just-the-edit", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var index = write_file (root_path, "index", "a\nb\nc\n");

            var hunks = GitDiff.Engine.compute_hunks (null, index, "a\nCHANGED\nc\n");
            assert (hunks.length == 1);
            assert (hunks[0].kind == GitDiff.HunkKind.CHANGED);
            assert (hunks[0].current_start == 1);
            assert (hunks[0].solid == true);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-diff-engine/identical-to-head-is-no-hunks", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var head = write_file (root_path, "head", "a\nb\nc\n");

            var hunks = GitDiff.Engine.compute_hunks (head, head, "a\nb\nc\n");
            assert (hunks.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-diff-engine/nothing-staged-every-hunk-is-solid", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var head = write_file (root_path, "head", "line1\nline2\nline3\n");

            // Nothing staged: index == head, passed as the same path.
            var hunks = GitDiff.Engine.compute_hunks (head, head, "line1\nCHANGED\nline3\n");
            assert (hunks.length == 1);
            assert (hunks[0].kind == GitDiff.HunkKind.CHANGED);
            assert (hunks[0].current_start == 1);
            assert (hunks[0].solid == true);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    // A hunk fully captured by what's staged dims (survives as a
    // secondary/HEAD hunk, since it doesn't touch anything in the
    // primary/index diff); a hunk with further unstaged work on top
    // stays solid (it *is* the primary/index hunk).
    Test.add_func ("/git-diff-engine/staged-hunk-dims-unstaged-hunk-stays-solid", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var head = write_file (root_path, "head", "line1\nline2\nline3\nline4\n");
            var index = write_file (root_path, "index", "line1\nSTAGED\nline3\nline4\n");
            var current_text = "line1\nSTAGED\nline3\nUNSTAGED\n";

            var hunks = GitDiff.Engine.compute_hunks (head, index, current_text);
            assert (hunks.length == 2);

            var staged_hunk = find_hunk_at (hunks, 1);
            var unstaged_hunk = find_hunk_at (hunks, 3);
            assert (staged_hunk != null && !staged_hunk.solid);
            assert (unstaged_hunk != null && unstaged_hunk.solid);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    // Regression: a secondary (HEAD) hunk used to only have its *solid*
    // flag recomputed by an overlap check, keeping its own full original
    // range — so a HEAD-hunk spanning an already-staged line plus a
    // further-unstaged one right next to it rendered the whole thing
    // solid, staged line included. VS Code's own real rule
    // (quickDiffDecorator.ts) drops a secondary hunk *entirely* — not
    // just the overlapping part — the moment it touches a primary one;
    // the already-staged line should show nothing at all here, not a
    // dimmed mark either, since it's not its own separate secondary hunk
    // once merged with the adjacent unstaged line by the no-context
    // HEAD diff.
    Test.add_func ("/git-diff-engine/a-secondary-hunk-touching-primary-is-dropped-entirely", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            var head = write_file (root_path, "head", "line1\nline2\nline3\nline4\nline5\n");
            var index = write_file (root_path, "index", "line1\nline2 (staged)\nline3\nline4 (staged)\nline5\n");
            var current_text = "line1\nline2 (staged)\nline3 (unstaged)\nline4 (edited again)\nline5\n";

            var hunks = GitDiff.Engine.compute_hunks (head, index, current_text);
            assert (hunks.length == 1);
            assert (hunks[0].current_start == 2);
            assert (hunks[0].current_count == 2);
            assert (hunks[0].solid == true);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}

private GitDiff.Hunk? find_hunk_at (GitDiff.Hunk[] hunks, int current_start) {
    foreach (var h in hunks) {
        if (h.current_start == current_start) {
            return h;
        }
    }
    return null;
}
