/**
 * A window-level overlay panel that should close on Escape from anywhere
 * in the window, not just while focus happens to be inside it — the same
 * genuinely generic behavior a real Gtk.Popover (or a Adw.Dialog like
 * GNOME Text Editor's own preferences window) already gives for free,
 * with GTK itself never needing to know what's actually inside one.
 *
 * MainWindowView's own window-wide Escape handling asks every panel
 * registered via register_global_panel() whether it's open, closing the
 * first one that is — a panel opts into that by implementing the two
 * members below; nothing else about it (or about MainWindowView) needs
 * to change for a future one (a Go to Line panel, say) to get the same
 * behavior SearchBar already has.
 */
public interface GlobalPanel : Object {
    /** Whether this panel is currently shown. */
    public abstract bool is_open { get; }

    /** Closes it — same effect as whatever its own dedicated close button/gesture already does. */
    public abstract void close ();
}
