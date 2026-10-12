namespace GitDiff {
  public enum SideKind {
    /** A blob at a revision — `rev:path`; "" as the revision is the index (`:path`). */
    REVISION,
    /** The file on disk. */
    WORKTREE,
    /** Nothing: the file didn't exist on this side (new, or deleted). */
    EMPTY;
  }

  /** One side of a file diff: where its text comes from, and the word the tab title shows for it. */
  public class Side : Object {
    public SideKind kind { get; construct; }
    /** For REVISION: the revision, "" for the index. */
    public string revision { get; construct; default = ""; }
    /** For REVISION: relative to the repository root; for WORKTREE: absolute. */
    public string path { get; construct; default = ""; }

    public Side (SideKind kind, string revision = "", string path = "") {
      Object (kind: kind, revision: revision, path: path);
    }

    /** "Index", "Working Tree", "HEAD", a short hash — "" for EMPTY. */
    public string label {
      owned get {
        switch (kind) {
          case SideKind.WORKTREE: return _("Working Tree");
          case SideKind.EMPTY: return "";
          default:
            if (revision == "") {
              return _("Index");
            }
            return revision == "HEAD" ? "HEAD" : revision.substring (0, int.min (7, revision.length));
        }
      }
    }
  }

  /**
   * Everything a diff tab needs to open: the two sides, the file's own
   * path (the new one, for a rename) and a title. Built by for_change()
   * from the same table VS Code's ResourceCommandResolver uses
   * (extensions/git/src/repository.ts): what is "before" and "after"
   * for a file in each state of the staging lists, or in a commit.
   */
  public class Request : Object {
    public string root_path { get; construct; }
    public Side left { get; construct; }
    public Side right { get; construct; }
    /** Absolute, the file as it is named on the right (new) side. */
    public string path { get; construct; }

    public Request (string root_path, Side left, Side right, string path) {
      Object (root_path: root_path, left: left, right: right, path: path);
    }

    public string relative_path {
      owned get { return path.substring (root_path.length + 1); }
    }

    /** "a.vala (Working Tree)", "a.vala (Index)", "a.vala (1a2b3c4)" — the side that is "after". */
    public string title {
      owned get {
        var after = right.kind == SideKind.EMPTY ? left : right;
        return "%s (%s)".printf (Path.get_basename (path), after.label);
      }
    }

    /** Whether a side is the working tree or the index — what a change to the repository can move. */
    public bool is_live {
      get { return left.kind == SideKind.WORKTREE || right.kind == SideKind.WORKTREE || (left.kind == SideKind.REVISION && left.revision == "") || (right.kind == SideKind.REVISION && right.revision == ""); }
    }

    /** Stable identity for the tab registry. */
    public string uri {
      owned get { return "opus://diff/%s/%s/%s".printf (side_id (left), side_id (right), path); }
    }

    private static string side_id (Side side) {
      switch (side.kind) {
        case SideKind.WORKTREE: return "worktree";
        case SideKind.EMPTY: return "empty";
        default: return side.revision == "" ? "index" : side.revision;
      }
    }

    /**
     * `section` is "unstaged" or "staged" (StagingPane's own lists).
     * Unstaged: index → worktree (untracked: nothing → worktree; deleted:
     * index → nothing). Staged: HEAD → index (added: nothing → index;
     * deleted: HEAD → nothing), a rename's left side under its old path —
     * only there: the index already holds a renamed file at its new path,
     * so the Unstaged diff of one edited after the rename reads both
     * sides at that path.
     */
    public static Request for_working_change (string root_path, GitScope.Change change, string section) {
      var relative = change.path.substring (root_path.length + 1);
      var old_relative = change.old_path != null ? change.old_path.substring (root_path.length + 1) : relative;
      if (section == "staged") {
        var left = change.kind == GitScope.ChangeKind.ADDED ? new Side (SideKind.EMPTY) : new Side (SideKind.REVISION, "HEAD", old_relative);
        var right = change.kind == GitScope.ChangeKind.DELETED ? new Side (SideKind.EMPTY) : new Side (SideKind.REVISION, "", relative);
        return new Request (root_path, left, right, change.path);
      }
      var left = change.kind == GitScope.ChangeKind.UNTRACKED ? new Side (SideKind.EMPTY) : new Side (SideKind.REVISION, "", relative);
      var right = change.kind == GitScope.ChangeKind.DELETED ? new Side (SideKind.EMPTY) : new Side (SideKind.WORKTREE, "", change.path);
      return new Request (root_path, left, right, change.path);
    }

    /** A file of `commit`: `parent:path` → `commit:path` — nothing on the left for a root commit or an added file, nothing on the right for a deleted one. */
    public static Request for_commit_change (string root_path, GitScope.Change change, string commit_hash, string? parent_hash) {
      var relative = change.path.substring (root_path.length + 1);
      var old_relative = change.old_path != null ? change.old_path.substring (root_path.length + 1) : relative;
      var left = parent_hash == null || change.kind == GitScope.ChangeKind.ADDED ? new Side (SideKind.EMPTY) : new Side (SideKind.REVISION, parent_hash, old_relative);
      var right = change.kind == GitScope.ChangeKind.DELETED ? new Side (SideKind.EMPTY) : new Side (SideKind.REVISION, commit_hash, relative);
      return new Request (root_path, left, right, change.path);
    }
  }
}
