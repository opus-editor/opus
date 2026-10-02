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
  CONFLICT;
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
   * `-c core.quotePath=false` stops git from quoting/escaping non-ASCII
   * path bytes in its own porcelain output; a path containing a literal
   * `"` or `\` is still always escaped regardless and this parser doesn't
   * unescape it — an accepted limitation, same class as GitFileList's
   * own newline-separated-paths one.
   */
  public static GitStatus? run (string root_path) {
    if (Environment.find_program_in_path ("git") == null) {
      return null;
    }

    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
    string[] argv = {
      "git", "-c", "core.quotePath=false", "-C", root_path,
      "status", "--porcelain", "--untracked-files=all",
    };

    Subprocess process;
    string? stdout_buf;
    try {
      process = launcher.spawnv (argv);
      process.communicate_utf8 (null, null, out stdout_buf, null);
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
   * Plain newline-separated `git status --porcelain` output, one entry per
   * line — not `-z`/NUL-separated: same reason GitFileList's own doc
   * comment already gives (Vala has no way to spell a literal NUL as a
   * string.split() delimiter). A rename/copy line reads `XY old -> new`;
   * only the new path is kept (the old one, if it still existed as a
   * separate live path, would show its own NONE — nothing to attach a
   * status to).
   */
  private void parse (string porcelain_output, string root_path) {
    foreach (var line in porcelain_output.split ("\n")) {
      if (line == "") {
        continue;
      }

      string label;
      var status = classify (line[0], line[1], out label);
      if (status == GitFileStatus.NONE) {
        continue; // deleted, or otherwise nothing to attach to a live path
      }

      var rest = line.substring (3); // "XY " is always exactly 3 characters
      var arrow = rest.index_of (" -> ");
      var relative_path = arrow < 0 ? rest : rest.substring (arrow + 4);

      var absolute_path = Path.build_filename (root_path, relative_path);
      file_status[absolute_path] = status;
      file_status_label[absolute_path] = label;
    }
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
