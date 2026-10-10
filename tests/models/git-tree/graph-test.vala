// Same tmpdir-fixture pattern as tests/models/git-scope: a real `git init` per test.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-tree-test-XXXXXX");
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

private void run_git (string root_path, string[] args) throws Error {
    string[] argv = { "git" };
    foreach (var arg in args) {
        argv += arg;
    }
    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
    launcher.set_cwd (root_path);
    launcher.spawnv (argv).wait ();
}

private void init_repo (string root_path) throws Error {
    run_git (root_path, { "init", "-q", "-b", "main" });
    run_git (root_path, { "config", "user.email", "test@opus.dev" });
    run_git (root_path, { "config", "user.name", "Opus Test" });
}

/** A commit touching `name` — returns nothing; the log is how tests read hashes back. */
private void commit_file (string root_path, string name, string message) throws Error {
    FileUtils.set_contents (Path.build_filename (root_path, name), message);
    run_git (root_path, { "add", name });
    run_git (root_path, { "commit", "-q", "-m", message });
}

private GitTree.Row? row_of (GenericArray<GitTree.Row> rows, string subject) {
    for (uint i = 0; i < rows.length; i++) {
        if (rows[i].commit.subject == subject) {
            return rows[i];
        }
    }
    return null;
}

private bool has_segment (GitTree.Row row, int top, int bottom) {
    for (uint i = 0; i < row.segments.length; i++) {
        if (row.segments[i].top_lane == top && row.segments[i].bottom_lane == bottom) {
            return true;
        }
    }
    return false;
}

private GenericArray<GitTree.Row> layout (string root_path) {
    int color = 0;
    return GitTree.Graph.layout (GitTree.Log.run (root_path), ref color);
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-tree-graph/a-linear-history-is-one-lane", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "one");
            commit_file (root_path, "a.txt", "two");
            commit_file (root_path, "a.txt", "three");

            var rows = layout (root_path);

            assert (rows.length == 3);
            for (uint i = 0; i < rows.length; i++) {
                assert (rows[i].node_lane == 0 && rows[i].node_color == 0 && rows[i].lane_count == 1);
            }
            assert (has_segment (rows[0], GitTree.Segment.NODE, 0)); // down to "two"
            assert (rows[0].segments.length == 1); // a tip: nothing arrives from above
            assert (has_segment (rows[1], 0, GitTree.Segment.NODE) && has_segment (rows[1], GitTree.Segment.NODE, 0));
            assert (has_segment (rows[2], 0, GitTree.Segment.NODE) && rows[2].segments.length == 1); // the root: in from above, nothing below
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-graph/a-merge-opens-a-second-lane-that-closes-at-the-fork", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            run_git (root_path, { "checkout", "-q", "-b", "side" });
            commit_file (root_path, "b.txt", "on side");
            run_git (root_path, { "checkout", "-q", "main" });
            commit_file (root_path, "c.txt", "on main");
            run_git (root_path, { "merge", "-q", "--no-ff", "-m", "merge side", "side" });

            var rows = layout (root_path);

            var merge = row_of (rows, "merge side");
            assert (merge.node_lane == 0 && merge.lane_count == 2);
            assert (has_segment (merge, GitTree.Segment.NODE, 0) && has_segment (merge, GitTree.Segment.NODE, 1));
            var side = row_of (rows, "on side");
            assert (side.node_lane == 1 && side.node_color != merge.node_color);
            var main_commit = row_of (rows, "on main");
            assert (main_commit.node_lane == 0);
            var root_row = row_of (rows, "base");
            assert (root_row.node_lane == 0 && root_row.lane_count == 2);
            assert (has_segment (root_row, 1, GitTree.Segment.NODE)); // the side lane ends at the fork
            assert (has_segment (root_row, 0, GitTree.Segment.NODE)); // so does main's own
            assert (root_row.segments.length == 2 && root_row.open_lanes.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-graph/an-unmerged-branch-above-main-forks-at-their-base", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            run_git (root_path, { "checkout", "-q", "-b", "feature" });
            commit_file (root_path, "b.txt", "feature 1");
            commit_file (root_path, "b.txt", "feature 2");
            run_git (root_path, { "checkout", "-q", "main" });
            commit_file (root_path, "a.txt", "on main"); // main moved on without feature: two tips, one base

            var rows = layout (root_path);

            assert (rows.length == 4);
            var main_commit = row_of (rows, "on main");
            var f1 = row_of (rows, "feature 1");
            assert (main_commit.node_lane != f1.node_lane);
            assert (main_commit.node_color != f1.node_color);
            var root_row = row_of (rows, "base");
            assert (root_row.lane_count == 2);
            assert (has_segment (root_row, 1, GitTree.Segment.NODE));
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-graph/an-octopus-merge-opens-a-lane-per-extra-parent", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            run_git (root_path, { "checkout", "-q", "-b", "one" });
            commit_file (root_path, "b.txt", "on one");
            run_git (root_path, { "checkout", "-q", "-b", "two", "main" });
            commit_file (root_path, "c.txt", "on two");
            run_git (root_path, { "checkout", "-q", "main" });
            commit_file (root_path, "d.txt", "on main"); // keeps main from being fast-forwarded away as a parent
            run_git (root_path, { "merge", "-q", "-m", "octopus", "one", "two" });

            var rows = layout (root_path);

            var merge = row_of (rows, "octopus");
            assert (merge.commit.parents.length == 3);
            assert (merge.open_lanes.length == 3 && merge.lane_count == 3);
            assert (row_of (rows, "base").lane_count == 3);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-graph/an-orphan-root-gets-a-lane-of-its-own-that-ends-with-it", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            run_git (root_path, { "checkout", "-q", "--orphan", "docs" });
            run_git (root_path, { "rm", "-rfq", "." });
            commit_file (root_path, "d.txt", "orphan");
            run_git (root_path, { "checkout", "-q", "main" });

            var rows = layout (root_path);

            var orphan = row_of (rows, "orphan");
            assert (orphan.segments.length == 0 || orphan.commit.parents.length == 0);
            assert (orphan.node_color != row_of (rows, "base").node_color);
            assert (rows[rows.length - 1].open_lanes.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-graph/a-second-page-continues-the-lanes-of-the-first", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            run_git (root_path, { "checkout", "-q", "-b", "side" });
            commit_file (root_path, "b.txt", "on side");
            run_git (root_path, { "checkout", "-q", "main" });
            commit_file (root_path, "c.txt", "on main");
            run_git (root_path, { "merge", "-q", "--no-ff", "-m", "merge side", "side" });
            var all = GitTree.Log.run (root_path);
            int color = 0;
            var whole = GitTree.Graph.layout (all, ref color);

            int paged_color = 0;
            var first = GitTree.Graph.layout (GitTree.Log.run (root_path, 2, 0), ref paged_color);
            var second = GitTree.Graph.layout (GitTree.Log.run (root_path, 2, 2), ref paged_color, first[first.length - 1].open_lanes);

            assert (first.length == 2 && second.length == 2);
            for (int i = 0; i < 2; i++) {
                assert (second[i].node_lane == whole[2 + i].node_lane);
                assert (second[i].node_color == whole[2 + i].node_color);
                assert (second[i].segments.length == whole[2 + i].segments.length);
            }
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-graph/colors-cycle-past-the-palette", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            for (int i = 0; i < GitTree.Graph.COLOR_COUNT + 1; i++) {
                run_git (root_path, { "checkout", "-q", "-b", "b%d".printf (i), "main" });
                commit_file (root_path, "f%d.txt".printf (i), "branch %d".printf (i));
            }
            run_git (root_path, { "checkout", "-q", "main" });

            var rows = layout (root_path);

            bool wrapped = false;
            for (uint i = 0; i < rows.length; i++) {
                assert (rows[i].node_color >= 0 && rows[i].node_color < GitTree.Graph.COLOR_COUNT);
                wrapped |= rows[i].node_color == 0 && i > 0;
            }
            assert (wrapped);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-graph/no-commits-gives-no-rows", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var rows = layout (root_path);
            assert (rows.length == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-graph/a-stash-sits-right-above-its-base-in-a-lane-of-its-own", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            commit_file (root_path, "a.txt", "tip");
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "dirty");
            run_git (root_path, { "stash", "push", "-m", "parked" });
            int color = 0;

            var rows = GitTree.Graph.layout (GitTree.Log.run (root_path), ref color, null, GitTree.Log.stashes (root_path));

            assert (rows.length == 3);
            assert (rows[0].stash != null && rows[0].commit.subject == "parked");
            assert (rows[1].commit.subject == "tip" && rows[1].stash == null);
            assert (rows[0].node_lane == 0 && rows[0].lane_count == 1); // straight above the tip, in its own column
            assert (has_segment (rows[0], GitTree.Segment.NODE, 0));
            assert (rows[0].node_color == rows[1].node_color);
            assert (rows[0].open_lanes.length == 0); // a stash opens no lane: the tip row still starts fresh
            assert (has_segment (rows[1], 0, GitTree.Segment.NODE)); // but the tip draws the stash's line down to its dot
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-graph/a-stash-mid-branch-moves-right-and-curves-into-its-base", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "base");
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "dirty");
            run_git (root_path, { "stash" });
            commit_file (root_path, "a.txt", "newer");
            int color = 0;

            var rows = GitTree.Graph.layout (GitTree.Log.run (root_path), ref color, null, GitTree.Log.stashes (root_path));

            assert (rows.length == 3);
            assert (rows[0].commit.subject == "newer");
            assert (rows[1].stash != null);
            assert (has_segment (rows[1], 0, 0)); // "newer"'s lane runs through, waiting for "base"
            assert (has_segment (rows[1], GitTree.Segment.NODE, 0)); // the stash curves into it from the right
            assert (rows[1].node_lane == 1 && rows[1].lane_count == 2);
            assert (rows[1].open_lanes.length == 1); // and opens nothing of its own
            assert (rows[2].commit.subject == "base" && rows[2].node_lane == 0);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-tree-graph/a-stash-on-head-moves-right-when-the-working-tree-is-dirty", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "tip");
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "dirty");
            run_git (root_path, { "stash" });
            int color = 0;

            var rows = GitTree.Graph.layout (GitTree.Log.run (root_path), ref color, null, GitTree.Log.stashes (root_path), true);

            assert (rows[0].stash != null);
            assert (rows[0].node_lane == 1 && rows[0].lane_count == 2); // the WIP line owns lane 0 above HEAD
            assert (has_segment (rows[0], GitTree.Segment.NODE, 0));
            assert (has_segment (rows[1], 0, GitTree.Segment.NODE)); // HEAD still draws the line in
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
