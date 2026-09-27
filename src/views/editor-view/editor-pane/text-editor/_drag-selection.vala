namespace EditorView.EditorPane_ {
  /**
   * Drag-to-move-selection, split out of TextEditorCursors — matches VS
   * Code's own real split: its DragAndDropController lives in its own
   * file, contrib/dnd/browser/dnd.ts, separate from mouseHandler.ts's
   * plain click handling.
   *
   * Composed by TextEditorCursors, not a standalone top-level component:
   * click_gesture (in _cursors.vala) is what decides a press might turn
   * into this kind of drag at all — the same gesture also handles Alt+
   * Click/box-select, so splitting gesture *recognition* itself out would
   * mean either two gestures fighting over the same presses, or this
   * class reaching back into click_gesture's own state. Instead,
   * TextEditorCursors calls start() once it's already decided a drag is
   * real (its own threshold check passed); this class owns the drag/drop
   * mechanics from there, and emits `dropped` for whoever composes it to
   * turn into an actual edit — this class has no reference to the Model,
   * so it can't do that part itself.
   */
  public class TextEditorDragSelection : Object {
    private TextEditorSourceView text_view;
    private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }

    /** A drop landed with `snapshot`'s own text, at `drop_offset` — turning that into a real edit needs the Model, which this class doesn't have a reference to. */
    public signal void dropped (SelectionSnapshot snapshot, int drop_offset);

    public TextEditorDragSelection (TextEditorSourceView text_view) {
      this.text_view = text_view;

      // Our own reimplementation of "drag a selection to move it" — GTK's
      // native one can't be used here (cursor_visible = false permanently
      // hides its own drop indicator — see TextEditorSourceView's own doc
      // comment). Only the drop *target* side; the drag itself starts by
      // hand, in start() below, once TextEditorCursors' own click_gesture
      // says a claimed press has turned into a real drag.
      var drop_target = new Gtk.DropTarget (typeof (SelectionSnapshot), Gdk.DragAction.MOVE);
      drop_target.motion.connect (on_drop_motion);
      drop_target.leave.connect (on_drop_leave);
      drop_target.drop.connect (on_drop);
      text_view.add_controller (drop_target);
    }

    /** Nothing to unregister — same reasoning as TextEditor.close(), see its own comment. Kept for the same always-there teardown shape. */
    public void close () {
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

      if (drag != null) {
        ((Gtk.DragIcon) Gtk.DragIcon.get_for_drag (drag)).child = new Gtk.Label (snapshot.text);
      }
    }

    private Gdk.DragAction on_drop_motion (double x, double y) {
      text_view.set_drop_indicator (offset_at_widget_position (x, y));
      return Gdk.DragAction.MOVE;
    }

    private void on_drop_leave () {
      text_view.set_drop_indicator (null);
    }

    private bool on_drop (Value value, double x, double y) {
      text_view.set_drop_indicator (null); // drop completing isn't guaranteed to also fire leave()
      var snapshot = value.get_object () as SelectionSnapshot;
      if (snapshot == null) {
        return false;
      }

      dropped (snapshot, offset_at_widget_position (x, y));
      return true;
    }

    private int offset_at_widget_position (double widget_x, double widget_y) {
      int buffer_x;
      int buffer_y;
      text_view.window_to_buffer_coords (Gtk.TextWindowType.WIDGET, (int) widget_x, (int) widget_y, out buffer_x, out buffer_y);

      Gtk.TextIter iter;
      text_view.get_iter_at_location (out iter, buffer_x, buffer_y);
      return iter.get_offset ();
    }
  }
}
