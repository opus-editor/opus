/**
 * A directory's live-tracking state: an active Gio.FileMonitor once
 * actually watching, and/or a pending debounce timeout about to start or
 * stop one — see ExplorerPaneDirWatcher.on_directory_expanded_changed()
 * for why both exist and are never both meaningful at once (a directory is
 * either mid-transition or settled, never both).
 */
private class DirectoryWatch : Object {
  public FileMonitor? monitor = null;
  public uint pending_timeout_id = 0;
}

namespace EditorView {
  /**
   * Live-tracks external changes (another app creating/deleting/renaming/
   * rewriting something) for whichever directories are actually expanded —
   * split out of the real FileTreeController, which mixed this into the
   * same class as CRUD/clipboard/context-menu handling. Reports either that
   * a directory's own children changed (directory_changed — ExplorerPane
   * owns the FileTree model needed to actually rescan it and refresh the
   * row) or that a file's own contents were rewritten in place
   * (content_changed — nothing to rescan, but plugins like git-status care).
   */
  public class ExplorerPaneDirWatcher : Object {
    // Long enough to absorb someone rapidly toggling a row open/closed
    // (thinking out loud, or just clicking around) without ever actually
    // touching the filesystem for it; short enough that deliberately
    // opening a folder to look at it still starts tracking it almost
    // immediately.
    private const uint WATCH_DEBOUNCE_MS = 400;

    private ExplorerPaneTree tree;

    // One entry per directory that's ever been expanded (or is mid-way
    // through becoming watched/unwatched) — never the whole tree at once.
    // The root's own entry starts watching immediately at construction
    // (its children are always visible, no "expand" ever needed for it)
    // rather than through this debounce path.
    private HashTable<string, DirectoryWatch> watches = new HashTable<string, DirectoryWatch> (str_hash, str_equal);

    /** `path`'s own children changed on disk in a way that affects what its row should show — the caller is expected to rescan and call ExplorerPaneTree.refresh_children(). */
    public signal void directory_changed (string path);

    /** A file's own contents changed within a watched (expanded) directory — e.g. saved outside Opus, or a build tool rewriting it in place — without affecting `path`'s own children list (that's directory_changed's job). Exists for ExplorerPaneGitStatusWatcher-shaped consumers (currently the git-status plugin's own Provider, via WorkspaceContext): this is the single most common trigger for a stale decoration (a tracked file edited and saved without staging). */
    public signal void content_changed (string path);

    public ExplorerPaneDirWatcher (ExplorerPaneTree tree, string root_path) {
      this.tree = tree;
      tree.directory_expanded_changed.connect (on_directory_expanded_changed);

      var root_watch = new DirectoryWatch ();
      watches[root_path] = root_watch;
      start_watching (root_path, root_watch);
    }

    /**
     * Debounces a directory's expand/collapse into starting or stopping a
     * Gio.FileMonitor for it — at most one pending timeout per directory,
     * always reflecting the *latest* toggle: expanding cancels any pending
     * "stop watching" (and, if nothing's watching yet, starts a fresh
     * "start watching" timer); collapsing does the reverse. Toggling back
     * and forth fast enough never lets either timer fire at all, so a real
     * watch/unwatch only ever happens once the state's actually settled —
     * a deliberate, preventive design: without it, rapidly clicking a row
     * open/closed would start and stop real Gio.FileMonitors — each one a
     * kernel inotify watch, a genuinely limited resource — many times over
     * for nothing.
     */
    private void on_directory_expanded_changed (string path, bool expanded) {
      var watch = watches[path];
      if (watch == null) {
        watch = new DirectoryWatch ();
        watches[path] = watch;
      }

      if (watch.pending_timeout_id != 0) {
        Source.remove (watch.pending_timeout_id);
        watch.pending_timeout_id = 0;
      }

      if (expanded) {
        if (watch.monitor != null) {
          return; // already watching — re-expanded before its own "stop" debounce fired
        }
        watch.pending_timeout_id = Timeout.add (WATCH_DEBOUNCE_MS, () => {
          watch.pending_timeout_id = 0;
          start_watching (path, watch);
          return Source.REMOVE;
        });
      } else {
        if (watch.monitor == null) {
          return; // never actually started — collapsed before its own "start" debounce fired
        }
        watch.pending_timeout_id = Timeout.add (WATCH_DEBOUNCE_MS, () => {
          watch.pending_timeout_id = 0;
          stop_watching (watch);
          return Source.REMOVE;
        });
      }
    }

    private void start_watching (string path, DirectoryWatch watch) {
      try {
        watch.monitor = File.new_for_path (path).monitor_directory (FileMonitorFlags.WATCH_MOVES, null);
        watch.monitor.changed.connect ((file, other_file, event_type) => on_directory_event (path, file, event_type));
      } catch (Error e) {
        warning ("failed to watch %s: %s", path, e.message);
      }
    }

    private void stop_watching (DirectoryWatch watch) {
      if (watch.monitor == null) {
        return;
      }
      watch.monitor.cancel ();
      watch.monitor = null;
    }

    /** `path` is the watched *directory* — right for directory_changed's own contract ("path's own children changed"). CHANGED is different: it's always about one specific *file* inside `path`, so content_changed reports `file`'s own path, not the directory's. */
    private void on_directory_event (string path, File file, FileMonitorEvent event_type) {
      switch (event_type) {
        case FileMonitorEvent.CREATED:
        case FileMonitorEvent.DELETED:
        case FileMonitorEvent.RENAMED:
        case FileMonitorEvent.MOVED_IN:
        case FileMonitorEvent.MOVED_OUT:
          directory_changed (path);
          break;
        case FileMonitorEvent.CHANGED:
          content_changed (file.get_path ());
          break;
        default:
          break;
      }
    }

    /** Cancels every pending debounce timer and active filesystem watch — call before discarding this object (e.g. "Close Folder", or replacing it with a freshly-opened one), so nothing keeps firing — or keeping it alive via a scheduled GLib.Timeout closure — after it's no longer wanted. */
    public void close () {
      foreach (var watch in watches.get_values ()) {
        if (watch.pending_timeout_id != 0) {
          Source.remove (watch.pending_timeout_id);
        }
        if (watch.monitor != null) {
          watch.monitor.cancel ();
        }
      }
      watches.remove_all ();
    }
  }
}
