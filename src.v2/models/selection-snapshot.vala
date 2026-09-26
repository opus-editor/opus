/**
* A frozen copy of a text range — `text`/`start`/`end` captured once at
* some point in time, rather than a live reference recomputed later.
* "Snapshot" matches CursorCollection.snapshot()'s own existing use in
* this codebase for the same idea (a frozen copy of otherwise-live
* cursor state); "Selection" ties it to Cursor.selection_start/
* selection_end, the live version of the same range this freezes.
*
* First use: TextEditorDragSelection's own start(), captured at drag-start
* so a later drop always sees the text as it was when the drag began, not
* whatever the buffer happens to hold by then. Also why this
* is its own GObject type rather than three loose values passed around:
* GTK's Gdk.DropTarget matches by GType, not by a same-process field
* check, and a plain string payload would also match GtkTextView's own
* native text-drop handling — same reasoning FileDragPayload
* (src/views/lib/file-drag/) has for the same kind of problem.
*/
public class SelectionSnapshot : Object {
  public string text { get; private set; }
  public int start_offset { get; private set; }
  public int end_offset { get; private set; }

  public SelectionSnapshot (string text, int start_offset, int end_offset) {
    this.text = text;
    this.start_offset = start_offset;
    this.end_offset = end_offset;
  }
}
