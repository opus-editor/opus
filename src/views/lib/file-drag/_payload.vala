/**
 * Payload for an in-app drag of a single file/folder path — a
 * EditorView.FileTreeRow (a sidebar entry) or a EditorView.TabBarPill (an open tab), dropped onto
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
    public string path { get; private set; }

    public FileDragPayload (string path) {
        this.path = path;
    }
}
