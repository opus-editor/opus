/**
 * Payload for an in-app drag of one or more file/folder paths — a
 * EditorView.ExplorerPaneTreeRow (a sidebar entry) or a EditorView.TabBarPill (an open tab), dropped onto
 * a EditorView.FileTree folder row or another EditorView.TabBarPill (to reorder). A distinct
 * GType, not a plain string: Gtk.DropTarget matches by GType, and a plain
 * string would also match GtkTextView's own built-in text-drop handling
 * — libadwaita's own AdwTabBox (checked its real source, adw-tab-box.c)
 * hits the exact same concern and solves it the same way, unioning a
 * GType-typed content provider for its own AdwTabPage alongside its
 * plain text one. Nothing else in GTK declares interest in this type,
 * so this drag stays contained to whichever DropTarget is actually
 * built for it.
 */
public class FileDragPayload : Object {
  /** The first path — the one dragged for a single row or a tab. */
  public string path { get; private set; }
  /** Every path dragged: the explorer's whole selection when the dragged row is part of one. */
  public string[] paths { get; private set; }

  /** Whether this drag asks to know about a drop outside every window of ours (FileDrag.make_source()) — MainWindow's catch-all target takes exactly these, so a drop inside one of ours is told apart from one outside. */
  public bool window_drop { get; set; default = false; }

  /** Set by whichever of the app's own drop targets took the drop — an in-app drag hands every target this very object. Left false, a drop that still "performed" landed outside every window of ours (see FileDrag.make_source()). */
  public bool accepted { get; set; default = false; }

  public FileDragPayload (string[] paths) {
    this.paths = paths;
    this.path = paths[0];
  }
}
