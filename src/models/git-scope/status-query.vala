namespace GitScope {
  public class StatusQuery : Object {
    /**
     * `git status` for everything at or under `scope` inside the
     * repository at `root_path`: one `XY path` entry each, paths relative
     * to `root_path`; a rename/copy is followed by its old path as a bare
     * entry of its own. Null when git couldn't answer — not on PATH, not
     * a repository, or some other git-level failure. Asking about a
     * scope below the root costs git that subtree, not the repository.
     *
     * `--untracked-files=all` lists every untracked file individually
     * rather than collapsing a wholly-untracked directory to one entry.
     * `--ignored=matching` reports a directory matched by an ignore
     * pattern as one `!! dir/` entry instead of everything inside it — a
     * `node_modules/` would otherwise cost thousands of entries.
     * `-z` separates entries with NUL and prints every path verbatim —
     * without it git wraps a path containing a space (or a quote, a
     * backslash, a non-ASCII byte) in quotes and escapes it.
     * `--no-optional-locks` keeps this from rewriting `.git/index` — a
     * background status must never hold `index.lock` against the user's
     * own git in a terminal. The flag rather than GIT_OPTIONAL_LOCKS: an
     * environment variable doesn't cross HostCommand's `flatpak-spawn`.
     * `--literal-pathspecs`: a `*` or `[` in the scope's own name is not
     * a pattern.
     */
    public static GenericArray<string>? run (string root_path, string scope) {
      if (!HostCommand.has_program ("git")) {
        return null;
      }

      var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
      string[] command = {
        "git", "--no-optional-locks", "--literal-pathspecs", "-C", root_path,
        "status", "--porcelain", "-z", "--untracked-files=all", "--ignored=matching",
      };
      if (scope != root_path) {
        command += "--";
        command += scope.substring (root_path.length + 1);
      }
      string[] argv = HostCommand.argv (command);

      Subprocess process;
      Bytes? stdout_buf;
      try {
        process = launcher.spawnv (argv);
        process.communicate (null, null, out stdout_buf, null);
      } catch (Error e) {
        return null;
      }
      if (!process.get_successful () || stdout_buf == null) {
        return null;
      }
      return split_nul_terminated (stdout_buf);
    }

    /** Bytes after the last NUL are dropped: git terminates every entry, so an unterminated tail is a truncated one. */
    private static GenericArray<string> split_nul_terminated (Bytes bytes) {
      var entries = new GenericArray<string> ();
      unowned uint8[] data = bytes.get_data ();
      int start = 0;
      for (int i = 0; i < data.length; i++) {
        if (data[i] != 0) {
          continue;
        }
        entries.add ((string) data[start:i]);
        start = i + 1;
      }
      return entries;
    }
  }
}
