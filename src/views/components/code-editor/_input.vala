/**
 * Turns keys and mouse gestures into CodeEditorCursors/CodeEditorClipboard
 * commands — the keymap, the click gesture (Alt+click, Shift+Alt
 * box-select, right-click, drag-a-selection detection), and the
 * right-click context menu (built with the shared ContextMenu,
 * views/components, same as EditorView.FileTree/TabBar's own). Owns
 * CodeEditorDragSelection too: this class's own click gesture is what
 * decides a press has turned into a drag-to-move at all (see that class's
 * doc comment for why gesture recognition can't be split off from it).
 *
 * Holds no cursor state and never writes the buffer itself: one branch of
 * key_pressed() is one command call. The only read-only awareness here
 * is the context menu graying out what execute_edit() would refuse
 * anyway, and is_inside_selection() never starting a drag on a
 * non-editable view.
 */
public class CodeEditorInput : Object {
  private CodeEditorSourceView text_view;
  private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }
  private CodeEditorCursors cursors;
  private CodeEditorClipboard clipboard;
  private CodeEditorDragSelection drag_selection;

  // Set by on_pressed() on a Shift+Alt+click (box-select) — -1 means
  // "not box-selecting right now". Set by on_pressed() on a plain
  // Alt+click (add a cursor) — extended into a selection by
  // on_drag_extended() on every subsequent drag update. Mutually
  // exclusive, both reset on every click.
  private int box_select_anchor_offset = -1;
  private bool alt_drag_active = false;

  // The Alt-modified press currently being dragged, if any.
  private bool dragging = false;
  // A claimed press inside the selection that may still turn into a
  // drag-to-move once it travels past GTK's own drag threshold.
  private bool possible_selection_drag = false;
  private double drag_press_x = 0;
  private double drag_press_y = 0;

  /** A Ctrl+click, or a plain double-click, landed at this offset — nothing here knows what (if anything) is clickable there; a consumer (Find Results' own filename/line hyperlinks) decides that from the buffer's own tags. Emitted on *release*, see on_pressed(). */
  public signal void link_click (int offset);

  // The press that may become a link_click once released on the same
  // line — its offset and the line that offset sits on; -1 means no
  // such press is in flight. See on_pressed()'s own comment.
  private int pending_link_offset = -1;
  private int pending_link_line = -1;

  public CodeEditorInput (CodeEditorSourceView text_view, CodeEditorCursors cursors, CodeEditorClipboard clipboard) {
    this.text_view = text_view;
    this.cursors = cursors;
    this.clipboard = clipboard;

    // CAPTURE: has to see the key before GtkTextView's own built-in bindings do.
    var key_controller = new Gtk.EventControllerKey ();
    key_controller.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
    key_controller.key_pressed.connect ((keyval, keycode, state) => key_pressed (keyval, state));
    text_view.add_controller (key_controller);

    // CAPTURE, so this gets first refusal before GtkTextView's own
    // internal click gesture — same reasoning as key_controller above.
    // Widened to any button (GtkGestureSingle reacts to the primary
    // button only by default — confirmed in gtkgesturesingle.c): a
    // right-click has to reach this same handler too, or there'd be
    // nothing here to stop gtk_text_view_do_popup()'s own native menu
    // from running underneath ours.
    var click_gesture = new Gtk.GestureClick ();
    click_gesture.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
    click_gesture.button = 0;
    click_gesture.pressed.connect ((n_press, x, y) => on_pressed (click_gesture, n_press, x, y));
    click_gesture.released.connect ((n_press, x, y) => on_released (x, y));
    click_gesture.update.connect ((sequence) => on_update (click_gesture, sequence));
    text_view.add_controller (click_gesture);

    drag_selection = new CodeEditorDragSelection (text_view);
    drag_selection.dropped.connect (cursors.move_selection);
  }

  /** No UI caller besides its own key controller above — also reachable from CodeEditor.key_pressed(), for Opus.Dev.DevServer's own KeyPress (the system-test DSL's `type`/`type_cmd`). Runs the exact same dispatch a genuine keystroke does; nothing here is test-specific. */
  public bool key_pressed (uint keyval, Gdk.ModifierType state) {
    // Reset unconditionally: a stale true from the last click must never
    // leak into a later, unrelated native mark change (e.g. a native
    // Ctrl+A after this same key falls through unclaimed below).
    cursors.keep_native_direction = false;

    bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
    bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
    bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
    uint lower_keyval = Gdk.keyval_to_lower (keyval);

    if (ctrl && !alt && lower_keyval == Gdk.Key.z) {
      if (shift) {
        cursors.redo ();
      } else {
        cursors.undo ();
      }
      return true;
    }
    if (ctrl && !alt && !shift && lower_keyval == Gdk.Key.y) {
      cursors.redo ();
      return true;
    }

    if (ctrl && !alt && !shift && lower_keyval == Gdk.Key.c) {
      clipboard.copy ();
      return true;
    }
    if (ctrl && !alt && !shift && lower_keyval == Gdk.Key.x) {
      clipboard.cut ();
      return true;
    }
    if (ctrl && !alt && !shift && lower_keyval == Gdk.Key.v) {
      clipboard.paste ();
      return true;
    }

    if (alt && shift && !ctrl && keyval == Gdk.Key.Up) {
      cursors.add_cursor_above ();
      return true;
    }
    if (alt && shift && !ctrl && keyval == Gdk.Key.Down) {
      cursors.add_cursor_below ();
      return true;
    }

    if (alt && !shift && !ctrl && (keyval == Gdk.Key.Up || keyval == Gdk.Key.Down)) {
      cursors.move_lines (keyval == Gdk.Key.Down);
      return true;
    }

    if (ctrl && !alt && !shift && lower_keyval == Gdk.Key.d) {
      cursors.add_cursor_at_next_match ();
      return true;
    }
    if (ctrl && !alt && shift && lower_keyval == Gdk.Key.l) {
      cursors.select_all_occurrences ();
      return true;
    }
    if (ctrl && !alt && (keyval == Gdk.Key.Left || keyval == Gdk.Key.Right)) {
      cursors.move (keyval == Gdk.Key.Left ? CursorMoveOp.WORD_LEFT : CursorMoveOp.WORD_RIGHT, shift);
      return true;
    }

    if (!ctrl && !alt && keyval == Gdk.Key.Escape) {
      return cursors.collapse ();
    }

    if (ctrl || alt) {
      return false; // no other Ctrl/Alt combination is claimed yet
    }

    if (!shift && keyval == Gdk.Key.Insert) {
      Session.get_default ().insert_mode = !Session.get_default ().insert_mode;
      return true;
    }

    CursorMoveOp move_op;
    if (move_op_for_keyval (keyval, out move_op)) {
      cursors.move (move_op, shift);
      return true;
    }
    RowMoveOp row_move_op;
    if (row_move_op_for_keyval (keyval, out row_move_op)) {
      cursors.move_by_row (row_move_op, shift);
      return true;
    }

    // A Tab with a selection somewhere is left to GtkSourceView's own
    // native block-indent (block-indent isn't implemented here).
    if (!shift && keyval == Gdk.Key.Tab && !cursors.cursors.has_selection) {
      cursors.tab ();
      return true;
    }

    if (keyval == Gdk.Key.BackSpace) {
      cursors.backspace ();
      return true;
    }
    if (keyval == Gdk.Key.Delete || keyval == Gdk.Key.KP_Delete) {
      cursors.delete_right ();
      return true;
    }
    if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
      cursors.enter ();
      return true;
    }

    unichar ch = (unichar) Gdk.keyval_to_unicode (keyval);
    if (ch != 0 && !ch.iscntrl ()) {
      cursors.type_char (ch);
      return true;
    }

    return false;
  }

  private static bool move_op_for_keyval (uint keyval, out CursorMoveOp op) {
    switch (keyval) {
      case Gdk.Key.Left: op = CursorMoveOp.LEFT; return true;
      case Gdk.Key.Right: op = CursorMoveOp.RIGHT; return true;
      default: op = CursorMoveOp.LEFT; return false;
    }
  }

  /** The keys whose meaning depends on how the text wraps — claimed here all the same (never left to GtkTextView's own wrap-aware bindings): with `cursor_visible = false` GTK's move_cursor handler scrolls the viewport instead of moving anything, and it only ever moves the one native cursor in any case. */
  private static bool row_move_op_for_keyval (uint keyval, out RowMoveOp op) {
    switch (keyval) {
      case Gdk.Key.Up: op = RowMoveOp.UP; return true;
      case Gdk.Key.Down: op = RowMoveOp.DOWN; return true;
      case Gdk.Key.Home: op = RowMoveOp.HOME; return true;
      case Gdk.Key.End: op = RowMoveOp.END; return true;
      default: op = RowMoveOp.UP; return false;
    }
  }

  private void on_pressed (Gtk.GestureClick click_gesture, int n_press, double x, double y) {
    var state = click_gesture.get_current_event_state ();
    bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
    bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
    uint button = click_gesture.get_current_button ();

    cursors.keep_native_direction = n_press == 1 && button == Gdk.BUTTON_PRIMARY;

    if (button == Gdk.BUTTON_SECONDARY && n_press == 1) {
      // Claimed outright, same as Alt+Click below: this is what stops
      // GTK's own native Cut/Copy/Paste/Delete menu from popping up —
      // it calls GtkTextBuffer's clipboard methods directly, the exact
      // non-EditHistory path Cut/Copy/Paste are already claimed away
      // from at the keyboard level (see key_pressed()'s Ctrl+X/C/V).
      click_gesture.set_state (Gtk.EventSequenceState.CLAIMED);
      show_context_menu (x, y);
      return;
    }

    if (button != Gdk.BUTTON_PRIMARY) {
      return; // no other button is claimed
    }

    // Observational only, never claimed — same shape as VS Code's own
    // ClickLinkGesture (checked clickLinkGesture.ts: plain onMouseDown/
    // onMouseUp subscriptions, no preventDefault/stopPropagation
    // anywhere, and the gesture *executes on mouse-up*, only if the
    // line under the pointer then is the one pressed on). A Ctrl+click
    // or a double-click *might* mean "follow whatever's here", but this
    // view has no opinion on that — it's purely up to whoever's
    // listening (Find Results' own hyperlinks); every native behavior a
    // click already had (caret placement, double-click-selects-word)
    // keeps happening exactly as before, completely unaffected by
    // whether anyone's listening at all. Recorded here, emitted from
    // on_released(): a listener that swaps this view out of its parent
    // while the button is still down would otherwise tear down the
    // gesture mid-sequence. A Ctrl+double-click counts once — its first
    // press already qualified, so the second (n_press == 2) doesn't.
    bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
    if (!alt && !shift && ((n_press == 1 && ctrl) || (n_press == 2 && !ctrl))) {
      pending_link_offset = text_view.offset_at (x, y);
      pending_link_line = line_of (pending_link_offset);
    }

    if (n_press <= 3 && alt) {
      click_gesture.set_state (Gtk.EventSequenceState.CLAIMED);
      dragging = n_press == 1;
    } else if (n_press == 1 && !alt && !shift && is_inside_selection (x, y)) {
      click_gesture.set_state (Gtk.EventSequenceState.CLAIMED);
      possible_selection_drag = true;
      drag_press_x = x;
      drag_press_y = y;
    }
    // else: unclaimed — flows to GtkTextView's native handling untouched.

    handle_click (text_view.offset_at (x, y), n_press, state);
  }

  private void on_released (double x, double y) {
    dragging = false;
    if (possible_selection_drag) {
      // Same native fallback GTK itself needs here: claiming the press
      // to *maybe* start a drag means nothing else repositions the
      // cursor if it turns out to be just a click with no real movement.
      possible_selection_drag = false;
      Gtk.TextIter iter;
      source_buffer.get_iter_at_offset (out iter, text_view.offset_at (x, y));
      source_buffer.place_cursor (iter);
    }

    if (pending_link_offset < 0) {
      return;
    }
    int pressed_offset = pending_link_offset;
    bool same_line = line_of (text_view.offset_at (x, y)) == pending_link_line;
    pending_link_offset = -1;
    pending_link_line = -1;
    if (same_line) {
      // The pressed offset, not the released one: that's the character
      // the user aimed at, and a few pixels of travel before releasing
      // shouldn't change which column a result line opens at.
      link_click (pressed_offset);
    }
  }

  private int line_of (int offset) {
    Gtk.TextIter iter;
    source_buffer.get_iter_at_offset (out iter, offset);
    return iter.get_line ();
  }

  private void on_update (Gtk.GestureClick click_gesture, Gdk.EventSequence? sequence) {
    double x;
    double y;
    if (!click_gesture.get_point (sequence, out x, out y)) {
      return;
    }

    if (possible_selection_drag) {
      if (Gtk.drag_check_threshold (text_view, (int) drag_press_x, (int) drag_press_y, (int) x, (int) y)) {
        possible_selection_drag = false;
        pending_link_offset = -1; // a press that became a drag-to-move is no click
        pending_link_line = -1;
        drag_selection.start (click_gesture.get_current_event ());
      }
      return;
    }
    if (dragging) {
      on_drag_extended (text_view.offset_at (x, y));
    }
  }

  /**
   * A plain single/double/triple primary click — only Alt-modified ones
   * are claimed above, so this only ever actually does something for
   * those; every other click still reaches here too (it's still an
   * undo-stop boundary), but returns right away once the `!alt` check
   * fails below.
   */
  private void handle_click (int offset, int n_press, Gdk.ModifierType state) {
    cursors.close_history_entry ();
    box_select_anchor_offset = -1;
    alt_drag_active = false;

    bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
    if (n_press < 1 || n_press > 3 || !alt) {
      return;
    }

    if (n_press == 2) {
      cursors.expand_last_added_cursor_to_word ();
    } else if (n_press == 3) {
      cursors.expand_last_added_cursor_to_line ();
    } else {
      bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
      if (shift) {
        box_select_anchor_offset = offset;
        cursors.box_select (offset, offset);
      } else {
        alt_drag_active = true;
        cursors.add_cursor_at (offset);
      }
    }
  }

  /** Continues whichever of box-select/add-a-cursor handle_click() just started — mutually exclusive, see their own fields' doc comments. */
  private void on_drag_extended (int offset) {
    if (box_select_anchor_offset >= 0) {
      cursors.box_select (box_select_anchor_offset, offset);
    } else if (alt_drag_active) {
      cursors.extend_last_added_cursor (offset);
    }
  }

  /** Whether a press at widget-relative (x, y) landed inside the real native selection — only the primary selection is ever draggable (a drag has exactly one pointer). False for a non-editable view: there's no move to make. */
  private bool is_inside_selection (double x, double y) {
    if (!text_view.editable) {
      return false;
    }

    Gtk.TextIter sel_start;
    Gtk.TextIter sel_end;
    if (!source_buffer.get_selection_bounds (out sel_start, out sel_end)) {
      return false;
    }
    int offset = text_view.offset_at (x, y);
    return offset >= sel_start.get_offset () && offset < sel_end.get_offset ();
  }

  /**
   * A right-click landed on the editor. Cut/Copy/Delete need a
   * selection *somewhere* (has_selection is multi-cursor-aware, unlike
   * the real native selection); Undo/Redo need a history entry to act
   * on; everything but Copy also needs an editable view. Each item runs
   * through key_pressed() with the same keyval/state a real keystroke
   * would carry, rather than duplicating what it already dispatches to.
   */
  private void show_context_menu (double x, double y) {
    bool editable = text_view.editable;
    bool has_selection = cursors.cursors.has_selection;
    bool can_edit_selection = editable && has_selection;
    bool can_undo = editable && cursors.history.can_undo;
    bool can_redo = editable && cursors.history.can_redo;

    ContextMenu.popup_at (text_view, x, y, (popover, box) => {
      box.append (ContextMenu.item (_("Cut"), () => { key_pressed (Gdk.Key.x, Gdk.ModifierType.CONTROL_MASK); }, popover, null, can_edit_selection));
      box.append (ContextMenu.item (_("Copy"), () => { key_pressed (Gdk.Key.c, Gdk.ModifierType.CONTROL_MASK); }, popover, null, has_selection));
      box.append (ContextMenu.item (_("Paste"), () => { key_pressed (Gdk.Key.v, Gdk.ModifierType.CONTROL_MASK); }, popover, null, editable));
      box.append (ContextMenu.item (_("Delete"), () => { key_pressed (Gdk.Key.Delete, 0); }, popover, null, can_edit_selection));
      box.append (ContextMenu.separator ());
      box.append (ContextMenu.item (_("Undo"), () => { key_pressed (Gdk.Key.z, Gdk.ModifierType.CONTROL_MASK); }, popover, Gtk.accelerator_get_label (Gdk.Key.z, Gdk.ModifierType.CONTROL_MASK), can_undo));
      box.append (ContextMenu.item (_("Redo"), () => { key_pressed (Gdk.Key.y, Gdk.ModifierType.CONTROL_MASK); }, popover, Gtk.accelerator_get_label (Gdk.Key.y, Gdk.ModifierType.CONTROL_MASK), can_redo));
    });
  }
}
