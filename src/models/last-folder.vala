/**
 * `window.restore_folder`: which folder a bare `opus` (no argument)
 * reopens. The record only exists while the setting is on — it follows
 * every folder linked or closed in the meantime, is taken from whatever
 * is linked at the moment the setting is turned on, and is dropped the
 * moment it is turned off.
 */
public class LastFolder : Object {
  public bool enabled { get; private set; }

  /** The record as it stands, or null — what the caller persists between runs. Not named `pathname`: Vala would generate the same C getter as get_pathname() below. */
  public string? recorded_pathname { get; private set; }

  /** `recorded_pathname` is whatever the previous run left behind; one left by a run that had the setting on is dropped if it is off now. */
  public LastFolder (bool enabled, string? recorded_pathname) {
    this.enabled = enabled;
    this.recorded_pathname = enabled ? recorded_pathname : null;
  }

  public void record (string pathname) {
    if (enabled) {
      recorded_pathname = pathname;
    }
  }

  public void clear () {
    recorded_pathname = null;
  }

  /** The setting as it reads now. `linked_pathname` is the folder linked in the window the setting was edited from, or null. */
  public void apply_setting (bool enabled, string? linked_pathname) {
    if (enabled == this.enabled) {
      return;
    }
    this.enabled = enabled;
    recorded_pathname = enabled ? linked_pathname : null;
  }

  /** The folder to reopen, or null: nothing recorded, or what was recorded is no longer a directory. */
  public string? get_pathname () {
    if (recorded_pathname == null || !FileUtils.test (recorded_pathname, FileTest.IS_DIR)) {
      return null;
    }
    return recorded_pathname;
  }
}
