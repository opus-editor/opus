namespace GitTree {
  /**
   * `git log` over every branch and tag, newest first in topological
   * order — the one read the Git view's tree is built from. Same spawn
   * shape as GitScope.StatusQuery: null when git couldn't answer (not on
   * PATH, not a repository), an empty list for a repository with no
   * commits yet. Records are NUL-terminated, fields split on \x1f —
   * neither can appear in a hash, a name or a message.
   */
  public class Log : Object {
    private const string FIELD_SEPARATOR = "\x1f";
    private const string FORMAT = "%H\x1f%P\x1f%an\x1f%ae\x1f%at\x1f%D\x1f%s\x1f%b";

    /** The `limit` commits after skipping `skip`, for paging. `refs/stash` is left out: a stash is not history. */
    public static GenericArray<Commit>? run (string root_path, int limit = 500, int skip = 0) {
      if (!HostCommand.has_program ("git")) {
        return null;
      }

      var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
      string[] command = {
        "git", "--no-optional-locks", "-C", root_path,
        "log", "--exclude=refs/stash", "--all", "--topo-order", "--decorate=full", "-z",
        "--format=" + FORMAT, "-n", limit.to_string (), "--skip=" + skip.to_string (),
      };

      Subprocess process;
      Bytes? stdout_buf;
      try {
        process = launcher.spawnv (HostCommand.argv (command));
        process.communicate (null, null, out stdout_buf, null);
      } catch (Error e) {
        return null;
      }
      if (!process.get_successful () || stdout_buf == null) {
        return null;
      }
      return parse (stdout_buf);
    }

    /** Every stash, newest first — `git stash list` is `git log` over the stash reflog, so the same record shape. Null when git couldn't answer, empty with none. */
    public static GenericArray<Stash>? stashes (string root_path) {
      if (!HostCommand.has_program ("git")) {
        return null;
      }
      var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
      string[] command = {
        "git", "--no-optional-locks", "-C", root_path,
        "stash", "list", "-z", "--format=%H\x1f%P\x1f%at\x1f%gd\x1f%s",
      };
      Subprocess process;
      Bytes? stdout_buf;
      try {
        process = launcher.spawnv (HostCommand.argv (command));
        process.communicate (null, null, out stdout_buf, null);
      } catch (Error e) {
        return null;
      }
      if (!process.get_successful () || stdout_buf == null) {
        return null;
      }
      var stashes = new GenericArray<Stash> ();
      foreach (var record in split_records (stdout_buf)) {
        var fields = record.split (FIELD_SEPARATOR, 5);
        if (fields.length < 5) {
          continue;
        }
        var parents = fields[1].split (" ");
        string branch, message;
        Stash.split_subject (fields[4], out branch, out message);
        stashes.add (new Stash (fields[0], parents.length > 0 ? parents[0] : "", fields[3], branch, message, int64.parse (fields[2])));
      }
      return stashes;
    }

    public static async GenericArray<Stash>? stashes_async (string root_path) {
      SourceFunc callback = stashes_async.callback;
      GenericArray<Stash>? result = null;

      new Thread<void> ("git-tree-stashes", () => {
        result = stashes (root_path);
        Idle.add ((owned) callback);
      });

      yield;
      return result;
    }

    public static async GenericArray<Commit>? run_async (string root_path, int limit = 500, int skip = 0) {
      SourceFunc callback = run_async.callback;
      GenericArray<Commit>? result = null;

      new Thread<void> ("git-tree-log", () => {
        result = run (root_path, limit, skip);
        Idle.add ((owned) callback);
      });

      yield;
      return result;
    }

    private static GenericArray<Commit> parse (Bytes bytes) {
      var commits = new GenericArray<Commit> ();
      foreach (var record in split_records (bytes)) {
        var commit = parse_record (record);
        if (commit != null) {
          commits.add (commit);
        }
      }
      return commits;
    }

    /** Bytes after the last NUL are dropped: git terminates every record, so an unterminated tail is a truncated one. Records that aren't UTF-8 are dropped too. */
    private static GenericArray<string> split_records (Bytes bytes) {
      var records = new GenericArray<string> ();
      unowned uint8[] data = bytes.get_data ();
      int start = 0;
      for (int i = 0; i < data.length; i++) {
        if (data[i] != 0) {
          continue;
        }
        var record = (string) data[start:i];
        start = i + 1;
        if (record.validate ()) {
          records.add (record);
        }
      }
      return records;
    }

    private static Commit? parse_record (string record) {
      var fields = record.split (FIELD_SEPARATOR, 8);
      if (fields.length < 7) {
        return null;
      }
      var parents = fields[1] == "" ? new string[0] : fields[1].split (" ");
      var decorations = fields[5];
      var refs = Ref.parse (decorations);
      bool is_head = decorations == "HEAD" || decorations.has_prefix ("HEAD -> ") || decorations.has_prefix ("HEAD, ") || decorations.contains (", HEAD");
      var body = fields.length == 8 ? fields[7] : "";
      return new Commit (fields[0], parents, fields[2], fields[3], int64.parse (fields[4]), fields[6], first_line (body), refs, is_head);
    }

    private static string first_line (string body) {
      foreach (var line in body.split ("\n")) {
        var trimmed = line.strip ();
        if (trimmed != "") {
          return trimmed;
        }
      }
      return "";
    }
  }
}
