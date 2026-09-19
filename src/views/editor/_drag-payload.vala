/**
 * Payload for an in-editor drag of the primary cursor's own selection,
 * moving it to a new position — a distinct GType, not a plain string,
 * for the same reason FileDragPayload (views/drag-drop.vala) is: a
 * Gtk.DropTarget matches by GType, and a plain string would also match
 * GtkTextView's own native text-drop handling. Because nothing outside
 * EditorView's own DragSource.prepare() ever produces this type, its own
 * DropTarget can only ever receive a drop that originated from this same
 * view's own drag — a drag of plain text from elsewhere simply never
 * matches, and falls through to GtkTextView's still-intact native target
 * handling untouched.
 *
 * `text`/`source_start`/`source_end` are captured once, at prepare()
 * time, rather than re-read later at drop time — nothing about them
 * needs to change mid-drag.
 */
public class EditorDragPayload : Object {
    public string text { get; private set; }
    public int source_start { get; private set; }
    public int source_end { get; private set; }

    public EditorDragPayload (string text, int source_start, int source_end) {
        this.text = text;
        this.source_start = source_start;
        this.source_end = source_end;
    }
}
