/**
 * The git-status plugin's own GitBranch.IProvider. Watches the
 * directory git keeps `HEAD` in rather than `<root>/.git` like its two
 * siblings: that is somewhere else for a linked worktree and for a
 * workspace below the repository's top level.
 */
namespace Opus.Plugins.GitStatus {
  public class BranchProvider : Object, IWorkspaceExtension, GitBranch.IProvider {
    // How long the first change of a burst waits for its read, so the
    // rest of the burst (a checkout rewrites several files) rides along.
    private const uint REFRESH_LATENCY_MS = 400;

    public WorkspaceContext context { get; set; }

    private string? git_dir = null;
    private FileMonitor? git_dir_monitor = null;
    private string? branch = null;
    private uint pending_refresh_id = 0;
    private bool refresh_running = false;
    private bool refresh_wanted = false;
    // Checked after run_refresh()'s own `yield` resumes — same reasoning
    // as Provider.active.
    private bool active = false;

    public BranchProvider (WorkspaceContext context) {
      Object (context: context);
    }

    public void activate () {
      active = true;
      context.directory_changed.connect (on_directory_changed);
      run_refresh.begin ();
    }

    public void deactivate () {
      active = false;
      context.directory_changed.disconnect (on_directory_changed);
      if (pending_refresh_id != 0) {
        Source.remove (pending_refresh_id);
        pending_refresh_id = 0;
      }
      refresh_wanted = false;
      watch (null);
      branch = null;
    }

    public string? current_branch () {
      return branch;
    }

    private void on_directory_changed (string path) {
      // The root is where a repository appears (`git init`) or goes away.
      if (path == context.root_path) {
        schedule_refresh ();
      }
    }

    private void on_git_dir_changed (File file, File? other_file, FileMonitorEvent event_type) {
      // git takes and drops `*.lock` files around every write; the write
      // itself is the event that matters.
      if (file.get_basename ().has_suffix (".lock")) {
        return;
      }
      schedule_refresh ();
    }

    private void schedule_refresh () {
      if (pending_refresh_id != 0) {
        return;
      }
      pending_refresh_id = Timeout.add (REFRESH_LATENCY_MS, () => {
        pending_refresh_id = 0;
        run_refresh.begin ();
        return Source.REMOVE;
      });
    }

    /** Thread + Idle.add, same shape as DiffBaseProvider.show_async. A change that arrives mid-read gets exactly one more read afterward. */
    private async void run_refresh () {
      if (refresh_running) {
        refresh_wanted = true;
        return;
      }
      refresh_running = true;

      SourceFunc callback = run_refresh.callback;
      string? new_git_dir = null;
      string? new_branch = null;
      var root_path = context.root_path;

      new Thread<void> ("git-head", () => {
        new_git_dir = GitHead.git_dir (root_path);
        if (new_git_dir != null) {
          new_branch = GitHead.label (root_path);
        }
        Idle.add ((owned) callback);
      });
      yield;
      refresh_running = false;

      if (!active) {
        return;
      }

      watch (new_git_dir);
      if (new_branch != branch) {
        branch = new_branch;
        branch_changed ();
      }

      if (refresh_wanted) {
        refresh_wanted = false;
        schedule_refresh ();
      }
    }

    private void watch (string? new_git_dir) {
      if (new_git_dir == git_dir) {
        return;
      }
      if (git_dir_monitor != null) {
        git_dir_monitor.cancel ();
        git_dir_monitor = null;
      }
      git_dir = new_git_dir;
      if (git_dir == null) {
        return;
      }
      try {
        git_dir_monitor = File.new_for_path (git_dir).monitor_directory (FileMonitorFlags.NONE, null);
        git_dir_monitor.changed.connect (on_git_dir_changed);
      } catch (Error e) {
        warning ("git-status: branch provider failed to watch %s: %s", git_dir, e.message);
      }
    }
  }
}
