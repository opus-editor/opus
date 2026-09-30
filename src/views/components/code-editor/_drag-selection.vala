/**
 * Drag-to-move-selection, split out of CodeEditorCursors — matches VS
 * Code's own real split: its DragAndDropController lives in its own
 * file, contrib/dnd/browser/dnd.ts, separate from mouseHandler.ts's
 * plain click handling.
 *
 * Composed by CodeEditorCursors, not a standalone top-level component:
 * click_gesture (in _cursors.vala) is what decides a press might turn
 * into this kind of drag at all — the same gesture also handles Alt+
 * Click/box-select, so splitting gesture *recognition* itself out would
 * mean either two gestures fighting over the same presses, or this
 * class reaching back into click_gesture's own state. Instead,
 * CodeEditorCursors calls start() once it's already decided a drag is
 * real (its own threshold check passed); this class owns the drag/drop
 * mechanics from there, and emits `dropped` for whoever composes it to
 * turn into an actual edit — this class has no reference to the Model,
 * so it can't do that part itself.
 */
public class CodeEditorDragSelection : Object {
  private CodeEditorSourceView text_view;
  private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }
  private Gtk.DropTarget drop_target;

  // The drag start() began, while it's in flight — what on_drop()
  // checks an incoming drop against: a SelectionSnapshot's offsets only
  // mean anything in the buffer it was captured from, so a drop coming
  // from another CodeEditor's own drag (the file editor's selection
  // dragged onto Find Results, say) has to be refused here rather than
  // applied as a delete/insert on the wrong buffer.
  private Gdk.Drag? active_drag = null;

  /** A drop landed with `snapshot`'s own text, at `drop_offset` — turning that into a real edit needs the Model, which this class doesn't have a reference to. */
  public signal void dropped (SelectionSnapshot snapshot, int drop_offset);

  public CodeEditorDragSelection (CodeEditorSourceView text_view) {
    this.text_view = text_view;

    // Our own reimplementation of "drag a selection to move it" — GTK's
    // native one can't be used here (cursor_visible = false permanently
    // hides its own drop indicator — see CodeEditorSourceView's own doc
    // comment). Only the drop *target* side; the drag itself starts by
    // hand, in start() below, once CodeEditorCursors' own click_gesture
    // says a claimed press has turned into a real drag.
    drop_target = new Gtk.DropTarget (typeof (SelectionSnapshot), Gdk.DragAction.MOVE);
    drop_target.motion.connect (on_drop_motion);
    drop_target.leave.connect (on_drop_leave);
    drop_target.drop.connect (on_drop);
    text_view.add_controller (drop_target);
  }

  /** Actually starts the drag, once the caller's own threshold check says a claimed press has turned into a real drag. */
  public void start (Gdk.Event? event) {
    if (event == null) {
      return;
    }
    var surface = event.get_surface ();
    var device = event.get_device ();
    if (surface == null || device == null) {
      return;
    }

    Gtk.TextIter sel_start;
    Gtk.TextIter sel_end;
    if (!source_buffer.get_selection_bounds (out sel_start, out sel_end)) {
      return;
    }

    var snapshot = new SelectionSnapshot (
      source_buffer.get_text (sel_start, sel_end, false),
      sel_start.get_offset (), sel_end.get_offset ()
    );
    var value = Value (typeof (SelectionSnapshot));
    value.set_object (snapshot);
    var content = new Gdk.ContentProvider.for_value (value);

    double sx;
    double sy;
    event.get_position (out sx, out sy);
    var drag = Gdk.Drag.begin (surface, device, content, Gdk.DragAction.MOVE, sx, sy);
    active_drag = drag;

    if (drag != null) {
      ((Gtk.DragIcon) Gtk.DragIcon.get_for_drag (drag)).child = new Gtk.Label (snapshot.text);
    }
  }

  /** Whether the drop currently over this view is the one start() began — see active_drag. */
  private bool is_own_drop () {
    var drop = drop_target.get_current_drop ();
    return drop != null && active_drag != null && drop.get_drag () == active_drag;
  }

  private Gdk.DragAction on_drop_motion (double x, double y) {
    if (!is_own_drop ()) {
      return 0;
    }
    text_view.set_drop_indicator (text_view.offset_at (x, y));
    return Gdk.DragAction.MOVE;
  }

  private void on_drop_leave () {
    text_view.set_drop_indicator (null);
  }

  private bool on_drop (Value value, double x, double y) {
    text_view.set_drop_indicator (null); // drop completing isn't guaranteed to also fire leave()
    var snapshot = value.get_object () as SelectionSnapshot;
    if (snapshot == null || !is_own_drop ()) {
      return false;
    }
    active_drag = null;

    dropped (snapshot, text_view.offset_at (x, y));
    return true;
  }
}
