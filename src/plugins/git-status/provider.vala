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
    // Same value/reasoning as ExplorerPaneDirWatcher.WATCH_DEBOUNCE_MS —
    // private to a different class, can't literally share the constant.
    private const uint REFRESH_DEBOUNCE_MS = 400;

    public WorkspaceContext context { get; set; }

    private FileMonitor? git_dir_monitor;
    private uint pending_refresh_id = 0;
    private bool refresh_running = false;
    private bool refresh_pending_again = false;
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
        git_dir_monitor.changed.connect ((file, other_file, event_type) => schedule_refresh ());
      } catch (Error e) {
        warning ("git-status: failed to watch %s/.git: %s", context.root_path, e.message);
      }

      // A freshly opened workspace must show correct decorations without
      // waiting for the first real change to trigger one.
      schedule_refresh ();
    }

    public void deactivate () {
      active = false;
      context.directory_changed.disconnect (on_workspace_changed);
      context.file_content_changed.disconnect (on_workspace_changed);

      if (pending_refresh_id != 0) {
        Source.remove (pending_refresh_id);
        pending_refresh_id = 0;
      }
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
      schedule_refresh ();
    }

    /** A git-status refresh is repo-wide regardless of which path triggered it — this trigger set only needs to be broad enough that *something* eventually fires soon after a real change, not exhaustive (see GIT_STATUS_PLUGIN_PLAN.md's own "Watching" section). */
    private void schedule_refresh () {
      if (pending_refresh_id != 0) {
        Source.remove (pending_refresh_id);
      }
      pending_refresh_id = Timeout.add (REFRESH_DEBOUNCE_MS, () => {
        pending_refresh_id = 0;
        run_refresh.begin ();
        return Source.REMOVE;
      });
    }

    /** Guards against overlapping runs: a trigger arriving mid-refresh schedules exactly one more afterward, never dropped. */
    private async void run_refresh () {
      if (refresh_running) {
        refresh_pending_again = true;
        return;
      }
      refresh_running = true;
      var result = yield global::GitStatus.run_async (context.root_path);
      refresh_running = false;

      if (!active) {
        return; // deactivated while this refresh was in flight — nothing more to do
      }

      snapshot = result;
      decorations_changed ();

      if (refresh_pending_again) {
        refresh_pending_again = false;
        schedule_refresh ();
      }
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
