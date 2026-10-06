namespace EditorView.EditorPane {
  /**
   * External change watching for one Document tab's file — split out the
   * same way CodeEditorDragSelection was: this owns the Gio.FileMonitor
   * lifecycle and self-write suppression mechanically, emitting the raw
   * event for its owner to interpret. The RENAMED-vs-deleted-vs-modified
   * disambiguation needs the document's own live is_deleted state, which
   * this class has no reference to.
   */
  public class TabDocumentFileWatcher : Object {
    private FileMonitor? monitor = null;
    private string? path = null;

    // Set right before the owner's own save()/save_as() writes, consumed
    // by the very next file-monitor event — a self-save produces a real
    // filesystem event indistinguishable at the GIO level from an
    // external change (FileUtils.set_contents fires exactly one RENAMED
    // event, nothing more), so this is the only way to tell the two apart.
    private bool own_write_pending = false;

    /** The watched file changed on disk in some way the owner didn't itself just write — see mark_own_write(). */
    public signal void file_changed (FileMonitorEvent event_type, string? other_file_path);

    /** Watches `path` itself (not its containing directory) for it being deleted, moved away, or changed outside Opus; replaces whatever was watched before. */
    public void watch (string new_path) {
      unwatch ();
      path = new_path;
      try {
        monitor = File.new_for_path (new_path).monitor_file (FileMonitorFlags.WATCH_MOVES, null);
        monitor.changed.connect ((file, other_file, event_type) => {
          if (own_write_pending) {
            own_write_pending = false;
            return;
          }
          file_changed (event_type, other_file == null ? null : other_file.get_path ());
        });
      } catch (Error e) {
        warning ("failed to watch %s: %s", new_path, e.message);
      }
    }

    public void unwatch () {
      monitor?.cancel ();
      monitor = null;
      path = null;
      own_write_pending = false;
    }

    /** Call right before writing to the watched file — the very next change event is assumed to be that write, not an external change, and is swallowed instead of raising file_changed(). */
    public void mark_own_write () {
      own_write_pending = true;
    }

    /** A write that never actually happened (e.g. save() threw) leaves no event to ever consume this — clear it by hand so a later, genuinely external change isn't swallowed too. */
    public void discard_own_write () {
      own_write_pending = false;
    }

    /** Cancels the watch — call before discarding this object: an active Gio.FileMonitor's own IO source could otherwise keep it alive indefinitely via its connected signal handler's closure. */
    public void close () {
      unwatch ();
    }
  }
}
