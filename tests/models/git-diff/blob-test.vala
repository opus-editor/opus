// Same tmpdir-fixture pattern as tests/models/git-scope: a real `git init` per test.

private string make_tmp_dir () throws Error {
    return DirUtils.make_tmp ("opus-git-diff-test-XXXXXX");
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

private void commit_file (string root_path, string name, string contents, string message) throws Error {
    FileUtils.set_contents (Path.build_filename (root_path, name), contents);
    run_git (root_path, { "add", name });
    run_git (root_path, { "commit", "-q", "-m", message });
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-diff-blob/a-revision-blob-is-read", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "hello\n", "add");

            var result = GitDiff.Blob.read (root_path, new GitDiff.Side (GitDiff.SideKind.REVISION, "HEAD", "a.txt"));

            assert (result.status == GitDiff.BlobStatus.OK && result.text == "hello\n");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-diff-blob/the-index-is-the-empty-revision", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "hello\n", "add");
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "staged\n");
            run_git (root_path, { "add", "a.txt" });
            FileUtils.set_contents (Path.build_filename (root_path, "a.txt"), "dirty\n");

            var index = GitDiff.Blob.read (root_path, new GitDiff.Side (GitDiff.SideKind.REVISION, "", "a.txt"));
            var worktree = GitDiff.Blob.read (root_path, new GitDiff.Side (GitDiff.SideKind.WORKTREE, "", Path.build_filename (root_path, "a.txt")));

            assert (index.text == "staged\n" && worktree.text == "dirty\n");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-diff-blob/an-empty-side-is-empty-text", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            var result = GitDiff.Blob.read (root_path, new GitDiff.Side (GitDiff.SideKind.EMPTY));
            assert (result.status == GitDiff.BlobStatus.OK && result.text == "");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-diff-blob/a-nul-byte-means-binary", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "x", "add");
            FileUtils.set_data (Path.build_filename (root_path, "blob.bin"), { 'P', 'N', 'G', 0, 1, 2 });

            var result = GitDiff.Blob.read (root_path, new GitDiff.Side (GitDiff.SideKind.WORKTREE, "", Path.build_filename (root_path, "blob.bin")));

            assert (result.status == GitDiff.BlobStatus.BINARY);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-diff-blob/invalid-utf8-is-reported", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            FileUtils.set_data (Path.build_filename (root_path, "latin.txt"), { 'c', 'a', 'f', 0xE9, '\n' });

            var result = GitDiff.Blob.read (root_path, new GitDiff.Side (GitDiff.SideKind.WORKTREE, "", Path.build_filename (root_path, "latin.txt")));

            assert (result.status == GitDiff.BlobStatus.NOT_UTF8);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-diff-blob/a-missing-path-at-a-revision-is-missing", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "x", "add");

            var result = GitDiff.Blob.read (root_path, new GitDiff.Side (GitDiff.SideKind.REVISION, "HEAD", "nope.txt"));

            assert (result.status == GitDiff.BlobStatus.MISSING);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-diff-blob/a-symlink-is-unsupported", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            FileUtils.set_contents (Path.build_filename (root_path, "target.txt"), "x");
            FileUtils.symlink ("target.txt", Path.build_filename (root_path, "link.txt"));

            var result = GitDiff.Blob.read (root_path, new GitDiff.Side (GitDiff.SideKind.WORKTREE, "", Path.build_filename (root_path, "link.txt")));

            assert (result.status == GitDiff.BlobStatus.UNSUPPORTED);
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    Test.add_func ("/git-diff-blob/a-renames-old-path-reads-at-the-old-name", () => {
        string root_path = "";
        try {
            root_path = make_tmp_dir ();
            init_repo (root_path);
            commit_file (root_path, "a.txt", "moved\n", "add");
            run_git (root_path, { "mv", "a.txt", "b.txt" });

            var result = GitDiff.Blob.read (root_path, new GitDiff.Side (GitDiff.SideKind.REVISION, "HEAD", "a.txt"));

            assert (result.status == GitDiff.BlobStatus.OK && result.text == "moved\n");
        } catch (Error e) {
            error (e.message);
        } finally {
            remove_recursive (root_path);
        }
    });

    return Test.run ();
}
