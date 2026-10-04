/**
 * A repo's live `git status`, parsed once per refresh — the data half of
 * the `git-status` plugin (see GIT_STATUS_PLUGIN_PLAN.md), kept
 * deliberately free of anything plugin/UI-shaped: no Peas, no
 * FileDecoration.*, just "what does git say about this path right now."
 * `Provider` (not built yet — needs the FileDecoration.* contract and the
 * libpeas engine, neither exist in this increment) is the thing that will
 * wrap this in `FileDecoration.State`s; this class only needs to answer
 * `status_for`/`tooltip_for` for whichever paths `git status` actually
 * reported.
 *
 * No folder aggregation here (`GIT_STATUS_PLAN.md`'s original draft had
 * one) — that's core's job once `FileDecoration.Registry` exists, per
 * GIT_STATUS_PLUGIN_PLAN.md's own design: bubbling a folder's status up
 * from its descendants is generic across every future provider, not
 * something each provider should reimplement.
 */
public enum GitFileStatus {
  NONE,
  NEW,
  MODIFIED,
  CONFLICT,
  IGNORED;
}

public class GitStatus : Object {
  private HashTable<string, GitFileStatus> file_status = new HashTable<string, GitFileStatus> (str_hash, str_equal);
  private HashTable<string, string> file_status_label = new HashTable<string, string> (str_hash, str_equal);

  /** `path` absolute. `HashTable.lookup` on a missing key returns GitFileStatus's own zero value (NONE), so this needs no extra null-check. */
  public GitFileStatus status_for (string path) {
    return file_status[path];
  }

  /** The specific status word ("Modified"/"Untracked"/"Renamed"/…) for `path`'s tooltip, or null when there's nothing to show. */
  public string? tooltip_for (string path) {
    return file_status_label[path];
  }

  /** Every path this snapshot has an opinion about — every one of these has a non-NONE status_for() (a NONE entry is never inserted, see parse()). Provider.current_decorations() walks this to build its own full-set answer. */
  public List<unowned string> paths () {
    return file_status.get_keys ();
  }

  /**
   * Synchronous core — same subprocess idiom as GitFileList (SubprocessLauncher
   * + spawnv, swallowed to a null sentinel on any failure). Unlike
   * FindInFilesSearch.run(), this never throws: there's no user-initiated
   * action here to show an error dialog for, only a background watcher
   * that should just quietly have nothing to report — the same contract
   * ExplorerPane.on_directory_changed() already accepts for its own
   * background rescans.
   *
   * `--untracked-files=all` lists every untracked file individually rather
   * than collapsing a wholly-untracked directory to one entry — needed so
   * a file deep inside a new, unadded folder still gets its own status.
   * `--ignored=matching` reports an ignored folder as one entry instead
   * of listing everything inside it — a `node_modules/` would otherwise
   * cost thousands of lines per refresh.
   * `-z` separates entries with NUL and prints every path verbatim —
   * without it git wraps a path containing a space (or a quote, a
   * backslash, a non-ASCII byte) in quotes and escapes it.
   */
  public static GitStatus? run (string root_path) {
    if (!HostCommand.has_program ("git")) {
      return null;
    }

    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
    string[] argv = HostCommand.argv ({
      "git", "-C", root_path,
      "status", "--porcelain", "-z", "--untracked-files=all", "--ignored=matching",
    });

    Subprocess process;
    Bytes? stdout_buf;
    try {
      process = launcher.spawnv (argv);
      process.communicate (null, null, out stdout_buf, null);
    } catch (Error e) {
      return null;
    }

    if (!process.get_successful () || stdout_buf == null) {
      return null; // not a git repository, or some other git-level failure
    }

    var status = new GitStatus ();
    status.parse (stdout_buf, root_path);
    return status;
  }

  /** Thread + Idle.add, same shape as FindInFilesSearch.run_async — the second consumer of that pattern in this codebase. */
  public static async GitStatus? run_async (string root_path) {
    SourceFunc callback = run_async.callback;
    GitStatus? result = null;

    new Thread<void> ("git-status", () => {
      result = run (root_path);
      Idle.add ((owned) callback);
    });

    yield;
    return result;
  }

  /**
   * `git status --porcelain -z` output: one `XY path` entry per NUL. A
   * rename/copy is two entries, the new path's `XY new` followed by the
   * bare old path; only the new one is kept (the old one, if it still
   * existed as a separate live path, would show its own NONE — nothing
   * to attach a status to).
   */
  private void parse (Bytes porcelain_output, string root_path) {
    var entries = split_nul_terminated (porcelain_output);
    for (uint i = 0; i < entries.length; i++) {
      var entry = entries[i];
      if (entry.length < 4) {
        continue; // "XY " is always exactly 3 characters, then a path
      }
      if (is_rename_or_copy (entry[0], entry[1])) {
        i++;
      }
      if (!entry.validate ()) {
        continue; // a path that isn't UTF-8 can't match any row's own path
      }

      string label;
      var status = classify (entry[0], entry[1], out label);
      if (status == GitFileStatus.NONE) {
        continue; // deleted, or otherwise nothing to attach to a live path
      }

      var relative_path = entry.substring (3);
      // git marks a directory entry (an ignored folder) with a trailing
      // slash; every lookup here is by the plain path.
      if (relative_path.has_suffix ("/")) {
        relative_path = relative_path.substring (0, relative_path.length - 1);
      }

      var absolute_path = Path.build_filename (root_path, relative_path);
      file_status[absolute_path] = status;
      file_status_label[absolute_path] = label;
    }
  }

  private static bool is_rename_or_copy (char x, char y) {
    return x == 'R' || x == 'C' || y == 'R' || y == 'C';
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

  /**
   * `x`/`y` are the two porcelain status columns (X = index/staged, Y =
   * worktree). Conflict codes (`U` in either column, plus the
   * both-added/both-deleted `AA`/`DD` pair, neither of which has a `U`)
   * are checked first — a conflict is the most urgent thing to surface
   * regardless of what the rest of the code might otherwise suggest.
   * `R`(ename) is deliberately bucketed as MODIFIED, not NEW — confirmed
   * product decision (GIT_STATUS_PLUGIN_PLAN.md) — but keeps its own
   * "Renamed" label rather than reading as a generic "Modified", so the
   * two-color simplification doesn't lose that distinction in the
   * tooltip.
   */
  private static GitFileStatus classify (char x, char y, out string label) {
    if (x == 'U' || y == 'U' || (x == 'A' && y == 'A') || (x == 'D' && y == 'D')) {
      label = _("Conflicted");
      return GitFileStatus.CONFLICT;
    }
    // Checked before the untracked/added-only rules below: an "AD" entry
    // (staged as added, then deleted from the worktree before commit) is
    // still nothing to attach a live decoration to — the file is gone —
    // regardless of what its X column says. Confirmed live: `git init &&
    // echo hi > f.txt && git add f.txt && rm f.txt && git status
    // --porcelain --untracked-files=all` prints exactly "AD f.txt".
    if (x == 'D' || y == 'D') {
      label = "";
      return GitFileStatus.NONE;
    }
    if (x == '!') {
      label = _("Ignored");
      return GitFileStatus.IGNORED;
    }
    if (x == '?' || y == '?') {
      label = _("Untracked");
      return GitFileStatus.NEW;
    }
    if (x == 'A') {
      label = _("Added");
      return GitFileStatus.NEW;
    }
    if (x == 'R') {
      label = _("Renamed");
      return GitFileStatus.MODIFIED;
    }
    if (x == 'C') {
      label = _("Copied");
      return GitFileStatus.MODIFIED;
    }
    if (x == 'T' || y == 'T') {
      label = _("Type Changed");
      return GitFileStatus.MODIFIED;
    }
    label = _("Modified");
    return GitFileStatus.MODIFIED;
  }
}
