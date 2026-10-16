/**
 * The mime type every GtkWindow's built-in drop target takes
 * (gtkwindow.c, "gtk-window-rootwindow-drop"), and the one mutter
 * reads by itself for a drop on the desktop, where no surface is
 * under the pointer: it then only sends dnd_finished, never
 * drop_performed, so the read itself is the signal — the same way
 * libadwaita's AdwTabBoxRootContent learns that its tab left.
 */
public class FileDragRootWindowDrop : Gdk.ContentProvider {
  public const string MIME_TYPE = "application/x-rootwindow-drop";

  /** Someone read the drop: the compositor, for the desktop, or a window's own target. */
  public bool read { get; private set; default = false; }

  public override Gdk.ContentFormats ref_formats () {
    return new Gdk.ContentFormats ({ MIME_TYPE });
  }

  public override async bool write_mime_type_async (string mime_type, OutputStream stream, int io_priority, Cancellable? cancellable) throws Error {
    read = true;
    return true;
  }
}

