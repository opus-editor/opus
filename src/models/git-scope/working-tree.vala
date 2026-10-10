/**
 * A repo's live `git status`, split into what's staged and what isn't —
 * GitView.StagingPane's own data source. Deliberately separate from
 * GitStatus (the file-decoration/explorer-tree side): that one collapses
 * the index (X) and worktree (Y) columns into one verdict per path and
 * drops anything deleted, exactly right for "does this row get a dot" but
 * wrong for a staging UI, where a partially-staged file is two real rows
 * (one in each section) and a deleted file is still something to show.
 */
namespace GitScope {
  public enum ChangeKind {
    ADDED,
    MODIFIED,
    DELETED,
    RENAMED,
    COPIED,
    TYPE_CHANGED,
    UNTRACKED,
    /** Both sides touched it (`UU`/`AA`/`DD`, or added on one side only) — the file carries conflict markers until resolved. */
    CONFLICT,
    /** `UD`: deleted by the side being merged in, modified by ours — keep ours or delete, nothing to merge. */
    DELETED_BY_THEM,
    /** `DU`: deleted by ours, modified by theirs. */
    DELETED_BY_US;

    /** The three kinds that only ever appear in WorkingTree.conflicts. */
    public bool is_conflict () {
      return this == CONFLICT || this == DELETED_BY_THEM || this == DELETED_BY_US;
    }

    /** git's own status letter for a non-conflict kind (A/M/D/R/C/T, U for untracked) — a conflict shows Change.conflict_code instead. */
    public string code () {
      switch (this) {
        case ADDED: return "A";
        case DELETED: return "D";
        case RENAMED: return "R";
        case COPIED: return "C";
        case TYPE_CHANGED: return "T";
        case UNTRACKED: return "U";
        case MODIFIED: return "M";
        default: return "!";
      }
    }
  }

  /** Which multi-step git operation is parked mid-way in the repository, if any — each leaves its own marker file in `.git`, and each has its own `--continue`/`--abort` (see GitScope.Operation). */
  public enum OperationKind {
    NONE,
    MERGE,
    REBASE,
    CHERRY_PICK,
    REVERT;

    /** git's own subcommand name, for `git <this> --continue`/`--abort`. "" for NONE. */
    public string subcommand () {
      switch (this) {
        case MERGE: return "merge";
        case REBASE: return "rebase";
        case CHERRY_PICK: return "cherry-pick";
        case REVERT: return "revert";
        default: return "";
      }
    }
  }

  public class Change : Object {
    /** Absolute. */
    public string path { get; construct; }
    public ChangeKind kind { get; construct; }
    /** git's own two-letter status for a conflict ("UU", "DU", "AA", …) — what the row shows letter by letter. "" for every other kind. */
    public string conflict_code { get; construct; default = ""; }
    /** Where a RENAMED/COPIED path came from (absolute) — the index entry git dropped to make the rename, so unstaging has to name both or it leaves that deletion staged on its own (VS Code passes both URIs too). Null for every other kind. */
    public string? old_path { get; construct; default = null; }

    public Change (string path, ChangeKind kind, string conflict_code = "", string? old_path = null) {
      Object (path: path, kind: kind, conflict_code: conflict_code, old_path: old_path);
    }

    /** kind's own user-facing word — VS Code's own status tooltip text, what its "Sort Changes by Status" groups by (GitView.ChangeList's own sort_key == "status"). */
    public string label {
      owned get {
        switch (kind) {
          case ChangeKind.ADDED: return _("Added");
          case ChangeKind.DELETED: return _("Deleted");
          case ChangeKind.RENAMED: return _("Renamed");
          case ChangeKind.COPIED: return _("Copied");
          case ChangeKind.TYPE_CHANGED: return _("Type Changed");
          case ChangeKind.UNTRACKED: return _("Untracked");
          case ChangeKind.CONFLICT: return _("Conflicted");
          case ChangeKind.DELETED_BY_THEM: return _("Deleted by Them");
          case ChangeKind.DELETED_BY_US: return _("Deleted by Us");
          default: return _("Modified");
        }
      }
    }
  }

  public class WorkingTree : Object {
    public GenericArray<Change> staged = new GenericArray<Change> ();
    public GenericArray<Change> unstaged = new GenericArray<Change> ();
    /** Every unmerged path — its own list, never in `unstaged`: VS Code's own "Merge Changes" group, with its own actions (GitScope.Resolve) instead of stage/discard. */
    public GenericArray<Change> conflicts = new GenericArray<Change> ();
    public OperationKind operation = OperationKind.NONE;
    /** The commit message git itself prepared for the parked operation (`.git/MERGE_MSG`, minus its `#` comment lines) — "" with none. */
    public string prepared_message = "";

    /** Null when git couldn't answer — see GitScope.StatusQuery. */
    public static WorkingTree? run (string root_path) {
      var entries = StatusQuery.run (root_path, root_path);
      if (entries == null) {
        return null;
      }

      var result = new WorkingTree ();
      result.parse (entries, root_path);
      result.read_operation (root_path);
      return result;
    }

    /** Thread + Idle.add, same shape as GitStatus.run_async(). */
    public static async WorkingTree? run_async (string root_path) {
      SourceFunc callback = run_async.callback;
      WorkingTree? result = null;

      new Thread<void> ("git-working-tree", () => {
        result = run (root_path);
        Idle.add ((owned) callback);
      });

      yield;
      return result;
    }

    /**
     * GitScope.StatusQuery's entries: one `XY path` each. A rename/copy
     * is two entries, the new path's `XY new` followed by the bare old
     * path — kept as the Change's own old_path (unlike GitStatus's own
     * parse(), which only decorates and can drop it).
     */
    private void parse (GenericArray<string> entries, string root_path) {
      for (uint i = 0; i < entries.length; i++) {
        var entry = entries[i];
        if (entry.length < 4) {
          continue; // "XY " is always exactly 3 characters, then a path
        }

        char x = entry[0];
        char y = entry[1];
        string? old_path = null;
        if (x == 'R' || x == 'C' || y == 'R' || y == 'C') {
          i++;
          if (i < entries.length && entries[i].validate ()) {
            old_path = Path.build_filename (root_path, entries[i]);
          }
        }
        if (x == '!' && y == '!') {
          continue; // ignored — StatusQuery asks for these too, but they're not a change
        }
        if (!entry.validate ()) {
          continue; // a path that isn't UTF-8 can't match any row's own path
        }

        var relative_path = entry.substring (3);
        if (relative_path.has_suffix ("/")) {
          relative_path = relative_path.substring (0, relative_path.length - 1);
        }
        var absolute_path = Path.build_filename (root_path, relative_path);

        if (x == 'U' || y == 'U' || (x == 'A' && y == 'A') || (x == 'D' && y == 'D')) {
          conflicts.add (new Change (absolute_path, conflict_kind_for (x, y), "%c%c".printf (x, y)));
          continue;
        }
        if (x == '?' && y == '?') {
          unstaged.add (new Change (absolute_path, ChangeKind.UNTRACKED));
          continue;
        }

        if (x != ' ' && x != '?') {
          staged.add (new Change (absolute_path, kind_for (x), "", old_path));
        }
        if (y != ' ' && y != '?') {
          unstaged.add (new Change (absolute_path, kind_for (y), "", old_path));
        }
      }
    }

    private static ChangeKind conflict_kind_for (char x, char y) {
      if (x == 'U' && y == 'D') {
        return ChangeKind.DELETED_BY_THEM;
      }
      if (x == 'D' && y == 'U') {
        return ChangeKind.DELETED_BY_US;
      }
      return ChangeKind.CONFLICT;
    }

    /** Which marker file sits in `.git` decides the operation — the same files git's own status header reads. The message is MERGE_MSG for all four: the sequencer (rebase, cherry-pick, revert) writes the stopped commit's message there too, and reads it back on `--continue`. */
    private void read_operation (string root_path) {
      var git_dir = Command.git_dir (root_path);
      if (git_dir == null) {
        return;
      }
      operation = operation_in (git_dir);
      if (operation == OperationKind.NONE) {
        return;
      }
      prepared_message = read_message (Path.build_filename (git_dir, "MERGE_MSG"));
    }

    private static OperationKind operation_in (string git_dir) {
      if (FileUtils.test (Path.build_filename (git_dir, "MERGE_HEAD"), FileTest.EXISTS)) {
        return OperationKind.MERGE;
      }
      if (FileUtils.test (Path.build_filename (git_dir, "rebase-merge"), FileTest.IS_DIR)
          || FileUtils.test (Path.build_filename (git_dir, "rebase-apply"), FileTest.IS_DIR)) {
        return OperationKind.REBASE;
      }
      if (FileUtils.test (Path.build_filename (git_dir, "CHERRY_PICK_HEAD"), FileTest.EXISTS)) {
        return OperationKind.CHERRY_PICK;
      }
      if (FileUtils.test (Path.build_filename (git_dir, "REVERT_HEAD"), FileTest.EXISTS)) {
        return OperationKind.REVERT;
      }
      return OperationKind.NONE;
    }

    private static string read_message (string path) {
      string contents;
      try {
        FileUtils.get_contents (path, out contents);
      } catch (Error e) {
        return "";
      }
      var kept = new StringBuilder ();
      foreach (var line in contents.split ("\n")) {
        if (!line.has_prefix ("#")) {
          kept.append (line).append_c ('\n');
        }
      }
      return kept.str.strip ();
    }

    private static ChangeKind kind_for (char code) {
      switch (code) {
        case 'A': return ChangeKind.ADDED;
        case 'D': return ChangeKind.DELETED;
        case 'R': return ChangeKind.RENAMED;
        case 'C': return ChangeKind.COPIED;
        case 'T': return ChangeKind.TYPE_CHANGED;
        default: return ChangeKind.MODIFIED; // 'M'
      }
    }
  }
}
