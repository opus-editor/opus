/**
 * Process-wide state shared by every open window/editor, never persisted
 * to disk — reached the same way this codebase reaches every other
 * shared singleton (Adw.StyleManager.get_default(), Gtk.Settings.
 * get_default()). New session-wide flags land here as another property
 * instead of their own one-off Model class.
 */
public class Session : Object {
  private static Session? instance = null;

  public bool insert_mode { get; set; default = false; }

  public static Session get_default () {
    if (instance == null) {
      instance = new Session ();
    }
    return instance;
  }
}
