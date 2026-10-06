/**
 * `window.save_session`: keeps the last session on disk, at `path`,
 * while the setting is on. Writes are gathered — a burst of tab
 * changes becomes one write, WRITE_DELAY_MSEC after the last — except
 * {@link flush}, for a window closing, which writes at once. Turning
 * the setting on takes the session of the window it was turned on
 * from; turning it off removes the file.
 */
public class SessionStore : Object {
  public const uint WRITE_DELAY_MSEC = 300;

  public bool enabled { get; private set; }
  public string path { get; private set; }

  private SavedSession? pending = null;
  private uint write_id = 0;

  public SessionStore (bool enabled, string path) {
    this.enabled = enabled;
    this.path = path;
    if (!enabled) {
      remove_file ();
    }
  }

  /** The session on disk, as far as it can be brought back now — null with the setting off, no file, a file that doesn't parse, or a folder that is gone. */
  public SavedSession? load () {
    if (!enabled || !FileUtils.test (path, FileTest.IS_REGULAR)) {
      return null;
    }
    try {
      string json;
      FileUtils.get_contents (path, out json);
      return SavedSession.parse (json).restorable ();
    } catch (Error e) {
      Logger.warn ("session %s: %s".printf (path, e.message));
      return null;
    }
  }

  /** `session` is the one to keep from now on; written shortly, with whatever follows it meanwhile. Ignored while off. */
  public void record (SavedSession session) {
    if (!enabled) {
      return;
    }
    pending = session;
    if (write_id == 0) {
      write_id = Timeout.add (WRITE_DELAY_MSEC, () => {
        write_id = 0;
        write_pending ();
        return Source.REMOVE;
      });
    }
  }

  /** Writes what {@link record} was given right away — the window is closing and won't be around for the delay. */
  public void flush () {
    if (write_id != 0) {
      Source.remove (write_id);
      write_id = 0;
    }
    write_pending ();
  }

  /** There is no session any more — the folder was closed. */
  public void clear () {
    if (write_id != 0) {
      Source.remove (write_id);
      write_id = 0;
    }
    pending = null;
    remove_file ();
  }

  /** The setting as it reads now. `current` is the session of the window the setting was edited from, or null with no folder linked there. */
  public void apply_setting (bool enabled, SavedSession? current) {
    if (enabled == this.enabled) {
      return;
    }
    this.enabled = enabled;
    if (!enabled) {
      clear ();
      return;
    }
    if (current != null) {
      record (current);
      flush ();
    }
  }

  private void write_pending () {
    if (pending == null) {
      return;
    }
    try {
      DirUtils.create_with_parents (Path.get_dirname (path), 0755);
      FileUtils.set_contents (path, pending.to_json ());
    } catch (FileError e) {
      Logger.warn ("couldn't save the session to %s: %s".printf (path, e.message));
    }
    pending = null;
  }

  private void remove_file () {
    if (FileUtils.test (path, FileTest.EXISTS)) {
      FileUtils.remove (path);
    }
  }
}
