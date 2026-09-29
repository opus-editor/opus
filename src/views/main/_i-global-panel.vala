/**
 * A window-level overlay panel that should close on Escape from anywhere
 * in the window, not just while focus happens to be inside it — the same
 * genuinely generic behavior a real Gtk.Popover (or a Adw.Dialog like
 * GNOME Text Editor's own preferences window) already gives for free,
 * with GTK itself never needing to know what's actually inside one.
 *
 * MainWindow's own window-wide Escape handling asks every panel
 * registered via register_global_panel() whether it's open, closing the
 * first one that is — a panel opts into that by implementing the two
 * members below; nothing else about it (or about MainWindow) needs
 * to change for a future one (a Go to Line panel, say) to get the same
 * behavior EditorView.FindBar already has.
 */
public interface IGlobalPanel : Object {
  /** Whether this panel is currently shown. */
  public abstract bool is_open { get; }

  /** The panel's own real widget — MainWindow's own set_active_bottom_panel() reparents this into whichever single-child slot a panel occupies, so only the active one is ever mounted at a time. */
  public abstract Gtk.Widget widget { get; }

  /** Closes it — same effect as whatever its own dedicated close button/gesture already does. */
  public abstract void close ();
}
