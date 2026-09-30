namespace EditorView {
  /**
   * External file-change watching for open tabs — split out of
   * EditorController's old job the same way CodeEditorDragSelection was:
   * this owns the Gio.FileMonitor lifecycle and self-write suppression
   * mechanically, emitting the raw event for EditorPane to interpret.
   * The RENAMED-vs-deleted-vs-modified disambiguation needs a document's
   * own live is_deleted state, which this class has no reference to —
   * same reason CodeEditorDragSelection can't turn a drop into an edit
   * itself.
   */
  public class EditorPaneFileWatcher : Object {
    private HashTable<string, FileMonitor> watches = new HashTable<string, FileMonitor> (str_hash, str_equal);

    // Set right before EditorPane's own save()/save_as() writes to a path,
    // consumed by the very next file-monitor event for it — a self-save
    // produces a real filesystem event indistinguishable at the GIO level
    // from an external change (FileUtils.set_contents fires exactly one
    // RENAMED event, nothing more), so this is the only way to tell the
    // two apart.
    private HashTable<string, bool> own_writes = new HashTable<string, bool> (str_hash, str_equal);

    /** `path` changed on disk in some way EditorPane didn't itself just write — see mark_own_write(). */
    public signal void file_changed (string path, FileMonitorEvent event_type, string? other_file_path);

    /** Watches `path` itself (not its containing directory) for it being deleted, moved away, or changed outside Opus. Untitled documents never call this — there's nothing on disk yet to watch. */
    public void start_watching (string path) {
      try {
        var monitor = File.new_for_path (path).monitor_file (FileMonitorFlags.WATCH_MOVES, null);
        monitor.changed.connect ((file, other_file, event_type) => {
          if (own_writes.remove (path)) {
            return;
          }
          file_changed (path, event_type, other_file == null ? null : other_file.get_path ());
        });
        watches[path] = monitor;
      } catch (Error e) {
        warning ("failed to watch %s: %s", path, e.message);
      }
    }

    public void stop_watching (string path) {
      var monitor = watches[path];
      if (monitor == null) {
        return;
      }
      monitor.cancel ();
      watches.remove (path);
      own_writes.remove (path);
    }

    /** Call right before writing to `path` — the very next change event for it is assumed to be that write, not an external change, and is swallowed instead of raising file_changed(). */
    public void mark_own_write (string path) {
      own_writes[path] = true;
    }

    /** A write that never actually happened (e.g. save() threw) leaves no event to ever consume this — clear it by hand so a later, genuinely external change to the same path isn't swallowed too. */
    public void discard_own_write (string path) {
      own_writes.remove (path);
    }

    /** Cancels every watch — call before discarding this object: an active Gio.FileMonitor's own IO source could otherwise keep it alive indefinitely via its connected signal handler's closure. */
    public void close () {
      foreach (var monitor in watches.get_values ()) {
        monitor.cancel ();
      }
      watches.remove_all ();
    }
  }
}
