/**
 * Whether a directory currently holds a WorkspaceWatcher request, and/or
 * a pending debounce timeout about to make or drop one — see
 * ExplorerPaneDirWatcher.on_directory_expanded_changed() for why both
 * exist and are never both meaningful at once (a directory is either
 * mid-transition or settled, never both).
 */
private class DirectoryWatch : Object {
  public bool requested = false;
  public uint pending_timeout_id = 0;
}

namespace EditorView {
  /**
   * Keeps whichever directories are actually expanded watched, by asking
   * the workspace's own WorkspaceWatcher for them. A directory git
   * doesn't ignore is watched anyway; this is what covers an ignored one
   * (or any directory outside a repository) for as long as its children
   * are on screen.
   */
  public class ExplorerPaneDirWatcher : Object {
    // Long enough to absorb someone rapidly toggling a row open/closed
    // (thinking out loud, or just clicking around) without ever actually
    // touching the filesystem for it; short enough that deliberately
    // opening a folder to look at it still starts tracking it almost
    // immediately.
    private const uint WATCH_DEBOUNCE_MS = 400;

    private WorkspaceWatcher watcher;

    // One entry per directory that's ever been expanded (or is mid-way
    // through becoming watched/unwatched) — never the whole tree at once.
    private HashTable<string, DirectoryWatch> watches = new HashTable<string, DirectoryWatch> (str_hash, str_equal);

    public ExplorerPaneDirWatcher (ExplorerPaneTree tree, WorkspaceWatcher watcher) {
      this.watcher = watcher;
      tree.directory_expanded_changed.connect (on_directory_expanded_changed);
    }

    /**
     * Debounces a directory's expand/collapse into making or dropping its
     * request — at most one pending timeout per directory, always
     * reflecting the *latest* toggle: expanding cancels any pending
     * release (and, if nothing's requested yet, starts a fresh request
     * timer); collapsing does the reverse. Toggling back and forth fast
     * enough never lets either timer fire at all — without it, rapidly
     * clicking an ignored directory's row open/closed would start and
     * stop a real Gio.FileMonitor (a kernel inotify watch, a genuinely
     * limited resource) many times over for nothing.
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

      if (watch.requested == expanded) {
        return; // toggled back before its own debounce fired
      }

      watch.pending_timeout_id = Timeout.add (WATCH_DEBOUNCE_MS, () => {
        watch.pending_timeout_id = 0;
        watch.requested = expanded;
        if (expanded) {
          watcher.request (path);
        } else {
          watcher.release (path);
        }
        return Source.REMOVE;
      });
    }

    /** Cancels every pending debounce timer — call before discarding this object, so no scheduled GLib.Timeout closure keeps it alive or fires into a WorkspaceWatcher that is already closed. */
    public void close () {
      foreach (var watch in watches.get_values ()) {
        if (watch.pending_timeout_id != 0) {
          Source.remove (watch.pending_timeout_id);
        }
      }
      watches.remove_all ();
    }
  }
}
