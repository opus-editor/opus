/**
 * The git-status plugin's own FileDecoration.IProvider — watches for
 * whatever might invalidate the last `git status` answer, re-runs it
 * debounced, and answers FileDecoration.Registry's pull with plain
 * FileDecoration.State values. No Gtk, no Peas (only plugin.vala touches
 * that) — just GLib.
 *
 * `global::GitStatus`/`global::GitFileStatus` throughout, not bare: this
 * class lives inside `namespace Opus.Plugins.GitStatus`, whose own last
 * segment matches the top-level `GitStatus` class's own name — the same
 * class of namespace/name collision `ExplorerPane`'s own doc comment
 * already documents for `FileTree` (see docs/DECISIONS.md).
 */
namespace Opus.Plugins.GitStatus {
  public class Provider : Object, IWorkspaceExtension, FileDecoration.IProvider {
    // How long the first change of a burst waits for its refresh, so the
    // rest of the burst rides along. Never extended by later changes — a
    // steady stream of them would otherwise postpone the refresh forever.
    private const uint REFRESH_LATENCY_MS = 400;
    // After a refresh, the next one waits this many times as long as it
    // took: unnoticeable where `git status` takes milliseconds, and a
    // repository where it takes a second isn't running it back to back.
    private const int64 COOLDOWN_FACTOR = 10;
    private const int64 MAX_COOLDOWN_US = 5 * TimeSpan.SECOND;
    private const string IGNORE_FILE = ".gitignore";

    public WorkspaceContext context { get; set; }

    private FileMonitor? git_dir_monitor;
    private uint pending_refresh_id = 0;
    private bool refresh_running = false;
    // The one path the next refresh asks git about: where a change
    // happened, widened to the common ancestor when several are waiting —
    // the same narrowing WorkspaceWatcher does for its own rescans. Null
    // when nothing is waiting.
    private string? pending_scope = null;
    private int64 next_refresh_allowed_at = 0; // monotonic time, microseconds
    private global::GitStatus? snapshot = null;

    // True only between activate() and deactivate() — run_refresh() checks
    // this after its own `yield` resumes, since a refresh started before
    // deactivate() can still be suspended (waiting on the subprocess
    // thread) at the exact moment deactivate() runs; without this guard,
    // the resumed coroutine would still overwrite `snapshot` and fire
    // decorations_changed() on a provider that's supposed to be dead.
    private bool active = false;

    public Provider (WorkspaceContext context) {
      Object (context: context);
    }

    public void activate () {
      active = true;
      context.directory_changed.connect (on_workspace_changed);
      context.file_content_changed.connect (on_workspace_changed);

      try {
        var git_dir = File.new_for_path (Path.build_filename (context.root_path, ".git"));
        git_dir_monitor = git_dir.monitor_directory (FileMonitorFlags.NONE, null);
        git_dir_monitor.changed.connect (on_git_dir_changed);
      } catch (Error e) {
        warning ("git-status: failed to watch %s/.git: %s", context.root_path, e.message);
      }

      // A freshly opened workspace must show correct decorations without
      // waiting for the first real change to trigger one.
      schedule_refresh (context.root_path);
    }

    public void deactivate () {
      active = false;
      context.directory_changed.disconnect (on_workspace_changed);
      context.file_content_changed.disconnect (on_workspace_changed);

      if (pending_refresh_id != 0) {
        Source.remove (pending_refresh_id);
        pending_refresh_id = 0;
      }
      pending_scope = null;
      if (git_dir_monitor != null) {
        git_dir_monitor.cancel ();
        git_dir_monitor = null;
      }
      snapshot = null;
    }

    public HashTable<string, FileDecoration.State> current_decorations () {
      var result = new HashTable<string, FileDecoration.State> (str_hash, str_equal);
      if (snapshot == null) {
        return result;
      }
      foreach (var path in snapshot.paths ()) {
        result[path] = decoration_for_path (path);
      }
      return result;
    }

    private void on_workspace_changed (string path) {
      // Ignore rules decide the status of everything beside and below them.
      var scope = Path.get_basename (path) == IGNORE_FILE ? Path.get_dirname (path) : path;
      schedule_refresh (scope);
    }

    private void on_git_dir_changed (File file, File? other_file, FileMonitorEvent event_type) {
      // git takes and drops `index.lock` (and other `*.lock` files) around
      // every write; the write itself is the event that matters.
      if (file.get_basename ().has_suffix (".lock")) {
        return;
      }
      // The index or HEAD moving (a stage, a commit, a checkout) can change
      // the status of any path.
      schedule_refresh (context.root_path);
    }

    private void schedule_refresh (string scope) {
      pending_scope = pending_scope == null ? scope : GitScope.Paths.common_ancestor (pending_scope, scope);
      arm_refresh_timer ();
    }

    private void arm_refresh_timer () {
      if (pending_refresh_id != 0) {
        return;
      }
      pending_refresh_id = Timeout.add (refresh_delay_ms (), () => {
        pending_refresh_id = 0;
        run_refresh.begin ();
        return Source.REMOVE;
      });
    }

    private uint refresh_delay_ms () {
      var cooldown_left_ms = (next_refresh_allowed_at - get_monotonic_time ()) / 1000;
      return (uint) int64.max (REFRESH_LATENCY_MS, cooldown_left_ms);
    }

    /** Guards against overlapping runs: a scope that arrives mid-refresh waits in pending_scope for exactly one more afterward. */
    private async void run_refresh () {
      if (refresh_running || pending_scope == null) {
        return;
      }
      // Without a snapshot of the whole there is nothing to merge a
      // narrower answer into.
      var scope = snapshot == null ? context.root_path : pending_scope;
      pending_scope = null;

      refresh_running = true;
      var started_at = get_monotonic_time ();
      var result = yield global::GitStatus.run_async (context.root_path, scope);
      var finished_at = get_monotonic_time ();
      next_refresh_allowed_at = finished_at + int64.min ((finished_at - started_at) * COOLDOWN_FACTOR, MAX_COOLDOWN_US);
      refresh_running = false;

      if (!active) {
        return; // deactivated while this refresh was in flight — nothing more to do
      }

      apply (scope, result);
      decorations_changed ();

      if (pending_scope != null) {
        arm_refresh_timer ();
      }
    }

    private void apply (string scope, global::GitStatus? result) {
      if (scope == context.root_path || result == null) {
        snapshot = result;
        return;
      }
      snapshot.replace_under (scope, result);
    }

    private FileDecoration.State decoration_for_path (string path) {
      var status = snapshot.status_for (path);
      var tooltip = snapshot.tooltip_for (path);

      if (status == global::GitFileStatus.CONFLICT) {
        return new FileDecoration.State (FileDecoration.Tone.ALERT, tooltip, _("Contains conflicts"));
      }
      if (status == global::GitFileStatus.IGNORED) {
        return new FileDecoration.State (FileDecoration.Tone.MUTED, tooltip, null, false, true);
      }
      if (status == global::GitFileStatus.NEW) {
        return new FileDecoration.State (FileDecoration.Tone.SUCCESS, tooltip, _("Contains new files"));
      }
      return new FileDecoration.State (FileDecoration.Tone.WARNING, tooltip, _("Contains modified files"));
    }
  }
}
