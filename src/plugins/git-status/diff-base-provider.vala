/**
 * The git-status plugin's own GitDiff.IBaseProvider — a second,
 * independent extension point living alongside Provider (the
 * FileDecoration.IProvider one). Deliberately does not share its `.git`
 * watch/debounce with Provider: the small duplication is simpler than a
 * cross-instance-shared "repository" object, and only worth revisiting
 * once a third provider actually needs one too.
 */
namespace Opus.Plugins.GitStatus {
  public class DiffBaseProvider : Object, IWorkspaceExtension, GitDiff.IBaseProvider {
    // Same value/reasoning as Provider's own REFRESH_DEBOUNCE_MS — private
    // to a different class, can't literally share the constant.
    private const uint REFRESH_DEBOUNCE_MS = 400;

    public WorkspaceContext context { get; set; }

    private FileMonitor? git_dir_monitor;
    private uint pending_refresh_id = 0;
    private bool active = false;

    public DiffBaseProvider (WorkspaceContext context) {
      Object (context: context);
    }

    public void activate () {
      active = true;
      try {
        var git_dir = File.new_for_path (Path.build_filename (context.root_path, ".git"));
        git_dir_monitor = git_dir.monitor_directory (FileMonitorFlags.NONE, null);
        git_dir_monitor.changed.connect ((file, other_file, event_type) => schedule_bases_changed ());
      } catch (Error e) {
        warning ("git-status: diff-base provider failed to watch %s/.git: %s", context.root_path, e.message);
      }
    }

    public void deactivate () {
      active = false;
      if (pending_refresh_id != 0) {
        Source.remove (pending_refresh_id);
        pending_refresh_id = 0;
      }
      if (git_dir_monitor != null) {
        git_dir_monitor.cancel ();
        git_dir_monitor = null;
      }
    }

    public async GitDiff.Bases? bases_for (string path) {
      var prefix = context.root_path + "/";
      if (!path.has_prefix (prefix)) {
        return null; // outside the linked workspace — no information, not "known untracked"
      }

      // `./` is load-bearing: `<rev>:<path>` on its own is resolved
      // relative to the repo's real top level, not `-C root_path`'s own
      // cwd — confirmed live (`git -C src show HEAD:main.vala` exits
      // 128, `git -C src show HEAD:./main.vala` exits 0) — without it,
      // every path breaks the moment the linked workspace is a
      // subdirectory of the real repo root, not the repo root itself.
      var relative = path.substring (prefix.length);
      var head_text = yield show_async ("HEAD:./%s".printf (relative));
      var index_text = yield show_async (":./%s".printf (relative));
      return new GitDiff.Bases (head_text, index_text);
    }

    private void schedule_bases_changed () {
      if (pending_refresh_id != 0) {
        Source.remove (pending_refresh_id);
      }
      pending_refresh_id = Timeout.add (REFRESH_DEBOUNCE_MS, () => {
        pending_refresh_id = 0;
        if (active) {
          bases_changed (null);
        }
        return Source.REMOVE;
      });
    }

    /** Thread + Idle.add, same shape as GitStatus.run_async. */
    private async string? show_async (string revision_spec) {
      SourceFunc callback = show_async.callback;
      string? result = null;
      var root_path = context.root_path;

      new Thread<void> ("git-show", () => {
        result = show_sync (root_path, revision_spec);
        Idle.add ((owned) callback);
      });

      yield;
      return result;
    }

    /**
     * Plain `git show` uses ordinary exit-code semantics (0 = found,
     * non-zero = no such blob/revision) — get_successful() is the right
     * check here, unlike GitDiff.Engine's --no-index calls, which treat
     * exit 1 as "found real differences," not a failure.
     */
    private static string? show_sync (string root_path, string revision_spec) {
      if (Environment.find_program_in_path ("git") == null) {
        return null;
      }

      var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
      string[] argv = { "git", "-C", root_path, "show", revision_spec };

      Subprocess process;
      string? stdout_buf;
      try {
        process = launcher.spawnv (argv);
        process.communicate_utf8 (null, null, out stdout_buf, null);
      } catch (Error e) {
        return null;
      }

      if (!process.get_successful () || stdout_buf == null) {
        return null;
      }
      return stdout_buf;
    }
  }
}
