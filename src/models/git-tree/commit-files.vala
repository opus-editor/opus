namespace GitTree {
  /**
   * What one commit changed, as GitScope.Changes — the rows the history
   * sidebar lists. Read with `git diff-tree` against the first parent
   * (what GitKraken shows for a merge too), or `--root` for a commit with
   * none. A stash is a commit whose first parent is its base, so the same
   * read shows what it parked. Null when git couldn't answer.
   */
  public class CommitFiles : Object {
    public static GenericArray<GitScope.Change>? run (string root_path, Commit commit) {
      if (!HostCommand.has_program ("git")) {
        return null;
      }
      string[] command = { "git", "--no-optional-locks", "-C", root_path, "diff-tree", "-r", "-M", "--name-status", "-z" };
      if (commit.parents.length == 0) {
        command += "--root";
        command += "--no-commit-id"; // the one-commit form prints the hash first; the two-tree form below doesn't
        command += commit.hash;
      } else {
        command += commit.parents[0];
        command += commit.hash;
      }

      var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
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
      return parse (split_nul (stdout_buf), root_path);
    }

    public static async GenericArray<GitScope.Change>? run_async (string root_path, Commit commit) {
      SourceFunc callback = run_async.callback;
      GenericArray<GitScope.Change>? result = null;

      new Thread<void> ("git-tree-commit-files", () => {
        result = run (root_path, commit);
        Idle.add ((owned) callback);
      });

      yield;
      return result;
    }

    /** `--name-status -z`: a status field then a path, except a rename/copy ("R100"/"C75") which is followed by the old path and then the new one. */
    private static GenericArray<GitScope.Change> parse (GenericArray<string> fields, string root_path) {
      var changes = new GenericArray<GitScope.Change> ();
      uint i = 0;
      while (i + 1 < fields.length) {
        var status = fields[i];
        char code = status.length > 0 ? status[0] : 'M';
        if ((code == 'R' || code == 'C') && i + 2 < fields.length) {
          var old_path = Path.build_filename (root_path, fields[i + 1]);
          var new_path = Path.build_filename (root_path, fields[i + 2]);
          changes.add (new GitScope.Change (new_path, kind_for (code), "", old_path));
          i += 3;
          continue;
        }
        changes.add (new GitScope.Change (Path.build_filename (root_path, fields[i + 1]), kind_for (code)));
        i += 2;
      }
      return changes;
    }

    private static GitScope.ChangeKind kind_for (char code) {
      switch (code) {
        case 'A': return GitScope.ChangeKind.ADDED;
        case 'D': return GitScope.ChangeKind.DELETED;
        case 'R': return GitScope.ChangeKind.RENAMED;
        case 'C': return GitScope.ChangeKind.COPIED;
        case 'T': return GitScope.ChangeKind.TYPE_CHANGED;
        default: return GitScope.ChangeKind.MODIFIED;
      }
    }

    private static GenericArray<string> split_nul (Bytes bytes) {
      var fields = new GenericArray<string> ();
      unowned uint8[] data = bytes.get_data ();
      int start = 0;
      for (int i = 0; i < data.length; i++) {
        if (data[i] != 0) {
          continue;
        }
        var field = (string) data[start:i];
        start = i + 1;
        if (field.validate ()) {
          fields.add (field);
        }
      }
      return fields;
    }
  }
}
