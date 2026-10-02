/**
 * The one way this codebase reaches a drag's own Gtk.DragIcon. Bound
 * to the C function directly rather than through gtk4.vapi: the vapi
 * shipped with GTK 4.18 declares `gtk_drag_icon_get_for_drag` as a
 * static method, the one with GTK 4.22 as a creation method — the same
 * Vala call can't compile against both, and Opus builds against both
 * (the host toolchain and the Flatpak Sdk).
 */
public class DragIcons {
  [CCode (cname = "gtk_drag_icon_get_for_drag", cheader_filename = "gtk/gtk.h")]
  private static extern unowned Gtk.Widget get_for_drag (Gdk.Drag drag);

  /** The icon GTK already created for `drag` — set its `child` to show something under the pointer. */
  public static unowned Gtk.DragIcon for_drag (Gdk.Drag drag) {
    return (Gtk.DragIcon) get_for_drag (drag);
  }
}
