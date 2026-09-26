namespace EditorView {
  /**
  * TextEditor's own cursor sub-component — every key/edit/clipboard/
  * undo command that acts on the current cursor(s), plus keeping the
  * Model's cursor state in sync with native GTK actions (double-click,
  * Ctrl+A, GtkSourceView's own native Tab-indent) this class doesn't
  * itself claim. Ported from the real CursorController, folded together
  * with the buffer-hook plumbing that used to live on TextEditor
  * (mark_set/insert_text/delete_range) — there's no signal boundary
  * between them any more, so what was "TextEditor notices a native
  * change, emits a signal, CursorController listens and updates the
  * Model" is now just one method calling another directly.
  *
  * Plural, matching VS Code's own real ViewCursors (checked its source,
  * browser/viewParts/viewCursors/): the manager for however many
  * cursors currently exist, not one instance per cursor — see the
  * conversation this came out of for why there's no singular
  * counterpart here the way VS Code has ViewCursor (that split is about
  * each DOM node needing its own on-screen position computed; GTK's
  * shared canvas draw has nothing per-cursor left over to be its own
  * object once render_cursors()'s loop already does that math).
  *
  * Still a slice: right-click's own context menu isn't claimed (it needs
  * actual menu-building code, out of scope here) — everything else,
  * keyboard and mouse, is.
  */
  public class TextEditorCursors : Object {
    private delegate void CursorCommand ();

    private const string SELECTION_TAG_NAME = "cursor-selection";

    private TextEditorSourceView text_view;
    private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }
    private Gtk.TextTag selection_tag;
    private Document? active_document = null;

    private int indent_size = 4;
    private bool insert_spaces = false;

    /** Suppresses on_insert_text_native/on_delete_range_native/on_mark_set while apply_edits() is itself mutating the buffer — otherwise our own edits would be misread as untracked native ones. */
    private bool updating_programmatically = false;

    /** Suppresses on_mark_set while render_cursors()'s own select_range() call is moving the marks — otherwise that would resync straight back from what render_cursors() was just asked to show. */
    private bool setting_cursors_programmatically = false;

    // See write_selection_to_clipboard()/distributed_paste_pieces() — ties
    // a same-session Paste's per-cursor pieces to whether the clipboard's
    // content still matches what was last copied from here.
    private string? last_clipboard_text = null;
    private string[]? last_clipboard_pieces = null;

    // See typing_kind() — the only way to tell a first space in a run
    // apart from a consecutive one, since that depends on what came
    // immediately before it.
    private bool previous_typed_was_space = false;

    // Set by the click_gesture's own pressed handler for a plain single
    // primary click, so on_mark_set() knows whether to preserve the
    // direction whatever comes next (that click, or a drag-select
    // following it) leaves the marks in, instead of always normalizing
    // to caret >= anchor.
    private bool preserve_native_direction = false;

    // Set by handle_click() on a Shift+Alt+click (box-select) — -1 means
    // "not box-selecting right now". Set by handle_click() on a plain
    // Alt+click (add a cursor) — extended into a selection by
    // handle_drag_extended() on every subsequent drag update. Mutually
    // exclusive, both reset on every click.
    private int box_select_anchor_offset = -1;
    private bool alt_drag_active = false;

    private TextEditorDragSelection drag_selection;

    private Gdk.RGBA focused_selection_background;
    private Gdk.RGBA backdrop_selection_background;

    /** The buffer's full content just changed via apply_edits() — bubbles up through TextEditor the same way EditorController's own dirty-tracking listens to the real TextEditor today. */
    public signal void text_changed (string new_text);

    public TextEditorCursors (TextEditorSourceView text_view) {
      this.text_view = text_view;

      // Off in favor of the EditHistory-backed pipeline below — the
      // two would otherwise compete for the same Ctrl+Z.
      source_buffer.enable_undo = false;

      // CAPTURE: has to see the key before GtkTextView's own built-in bindings do.
      var key_controller = new Gtk.EventControllerKey ();
      key_controller.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
      key_controller.key_pressed.connect ((keyval, keycode, state) => key_pressed (keyval, state));
      text_view.add_controller (key_controller);

      source_buffer.mark_set.connect (on_mark_set);
      // Plain .connect() (not _after) runs before the mutation actually
      // lands, so pos/start/end still describe what's *about to*
      // happen — see on_insert_text_native/on_delete_range_native.
      source_buffer.insert_text.connect (on_insert_text_native);
      source_buffer.delete_range.connect (on_delete_range_native);
      // _after counterparts purely to resync the tracked cursor once
      // the mutation has actually landed — see
      // resync_native_cursor_after_native_edit()'s own doc comment.
      source_buffer.insert_text.connect_after ((ref pos, new_text, len) => resync_native_cursor_after_native_edit ());
      source_buffer.delete_range.connect_after ((start, end) => resync_native_cursor_after_native_edit ());

      selection_tag = new Gtk.TextTag (SELECTION_TAG_NAME);
      selection_tag.background_set = true;
      source_buffer.tag_table.add (selection_tag);

      // GTK's own native selection grays out whenever the window is
      // inactive (state_flags_changed fires on text_view itself; BACKDROP
      // propagates down from the toplevel window) — reproduced here for
      // our own tag the same way.
      text_view.state_flags_changed.connect ((previous_state) => update_selection_background ());

      var style_manager = Adw.StyleManager.get_default ();
      style_manager.notify["dark"].connect (() => apply_theme_colors ());
      apply_theme_colors ();

      // Local, not fields: only these closures need them, same as the
      // real TextEditor's own constructor.
      bool dragging = false;
      bool possible_selection_drag = false;
      double drag_press_x = 0;
      double drag_press_y = 0;

      // CAPTURE, so this gets first refusal before GtkTextView's own
      // internal click gesture — same reasoning as key_controller above.
      // Left at its default button (primary only): right-click isn't
      // claimed in this slice (see the class's own doc comment), so there's
      // nothing here that needs to see it.
      var click_gesture = new Gtk.GestureClick ();
      click_gesture.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
      click_gesture.pressed.connect ((n_press, x, y) => {
        var state = click_gesture.get_current_event_state ();
        bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
        bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;

        preserve_native_direction = n_press == 1;

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

        handle_click (offset_at_widget_position (x, y), n_press, state);
      });
      click_gesture.released.connect ((n_press, x, y) => {
        dragging = false;
        if (possible_selection_drag) {
          // Same native fallback GTK itself needs here: claiming the press
          // to *maybe* start a drag means nothing else repositions the
          // cursor if it turns out to be just a click with no real movement.
          possible_selection_drag = false;
          Gtk.TextIter iter;
          source_buffer.get_iter_at_offset (out iter, offset_at_widget_position (x, y));
          source_buffer.place_cursor (iter);
        }
      });
      click_gesture.update.connect ((sequence) => {
        if (possible_selection_drag) {
          double x;
          double y;
          if (click_gesture.get_point (sequence, out x, out y) &&
              Gtk.drag_check_threshold (text_view, (int) drag_press_x, (int) drag_press_y, (int) x, (int) y)) {
            possible_selection_drag = false;
            drag_selection.start (click_gesture.get_current_event ());
          }
          return;
        }
        if (!dragging) {
          return;
        }
        double x;
        double y;
        if (click_gesture.get_point (sequence, out x, out y)) {
          handle_drag_extended (offset_at_widget_position (x, y), click_gesture.get_current_event_state ());
        }
      });
      text_view.add_controller (click_gesture);

      drag_selection = new TextEditorDragSelection (text_view);
      drag_selection.dropped.connect (on_drag_selection_dropped);
    }

    /** Cascades to the drag-selection sub-component's own close() — nothing of this class's own needs unregistering (same reasoning as TextEditor.close(), see its own comment). */
    public void close () {
      drag_selection.close ();
    }

    public void set_active_document (Document? document) {
      active_document = document;
      if (active_document != null) {
        render_cursors (active_document.cursors.snapshot ());
      }
    }

    /**
     * Replaces the buffer's whole content — TextEditor's own set_text()/
     * set_placeholder() call this instead of writing text_view.buffer
     * directly, since only this class holds updating_programmatically:
     * without it, on_insert_text_native()/on_delete_range_native() would
     * misread loading a brand-new document as an untracked user edit and
     * push it onto EditHistory.
     */
    public void load_text (string text) {
      updating_programmatically = true;
      text_view.buffer.text = text;
      updating_programmatically = false;
    }

    /** Columns per indent level, and whether Tab inserts that many spaces instead of a literal tab character — a "prop" this component can't derive on its own (comes from the linked folder's .editorconfig, out of scope here). */
    public void set_indent_config (int indent_size, bool insert_spaces) {
      this.indent_size = indent_size;
      this.insert_spaces = insert_spaces;
    }

    /** No UI caller today besides its own key controller above — also reachable from EditorView.TextEditor.key_pressed(), for Opus.Dev.DevServer's own KeyPress (the system-test DSL's `type`/`type_cmd`). Runs the exact same dispatch a genuine keystroke does; nothing here is test-specific. */
    public bool key_pressed (uint keyval, Gdk.ModifierType state) {
      // Reset unconditionally, even with no active_document: a stale true
      // from the last click must never leak into a later, unrelated native
      // mark change (e.g. a native Ctrl+A after this same key falls
      // through unclaimed below).
      preserve_native_direction = false;

      if (active_document == null) {
        return false;
      }

      bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
      bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
      bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
      uint lower_keyval = Gdk.keyval_to_lower (keyval);

      if (ctrl && !alt && lower_keyval == Gdk.Key.z) {
        previous_typed_was_space = false;
        apply_history_step (shift);
        return true;
      }
      if (ctrl && !alt && !shift && lower_keyval == Gdk.Key.y) {
        previous_typed_was_space = false;
        apply_history_step (true);
        return true;
      }

      if (ctrl && !alt && !shift && lower_keyval == Gdk.Key.c) {
        write_selection_to_clipboard (false);
        return true;
      }
      if (ctrl && !alt && !shift && lower_keyval == Gdk.Key.x) {
        write_selection_to_clipboard (true);
        return true;
      }
      if (ctrl && !alt && !shift && lower_keyval == Gdk.Key.v) {
        paste_from_clipboard.begin (active_document);
        return true;
      }

      if (alt && shift && !ctrl && keyval == Gdk.Key.Up) {
        apply_cursor_command (() => active_document.cursors.add_cursor_above (get_text ()));
        return true;
      }
      if (alt && shift && !ctrl && keyval == Gdk.Key.Down) {
        apply_cursor_command (() => active_document.cursors.add_cursor_below (get_text ()));
        return true;
      }

      if (alt && !shift && !ctrl && (keyval == Gdk.Key.Up || keyval == Gdk.Key.Down)) {
        previous_typed_was_space = false;
        apply_move_lines (keyval == Gdk.Key.Down);
        return true;
      }

      if (ctrl && !alt && !shift && lower_keyval == Gdk.Key.d) {
        apply_cursor_command (() => active_document.cursors.add_cursor_at_next_match (get_text ()));
        return true;
      }
      if (ctrl && !alt && shift && lower_keyval == Gdk.Key.l) {
        apply_cursor_command (() => active_document.cursors.select_all_occurrences (get_text ()));
        return true;
      }
      if (ctrl && !alt && (keyval == Gdk.Key.Left || keyval == Gdk.Key.Right)) {
        var move_op = keyval == Gdk.Key.Left ? CursorMoveOp.WORD_LEFT : CursorMoveOp.WORD_RIGHT;
        apply_cursor_command (() => active_document.cursors.move (move_op, shift, get_text ()));
        return true;
      }

      if (!ctrl && !alt && keyval == Gdk.Key.Escape) {
        if (active_document.cursors.count > 1) {
          apply_cursor_command (() => {
            var primary = active_document.cursors.primary.clone ();
            active_document.cursors.set_cursors ({ primary });
          });
          return true;
        }
        if (!active_document.cursors.primary.is_empty) {
          apply_cursor_command (() => {
            var primary = active_document.cursors.primary.clone ();
            primary.anchor_offset = primary.position_offset;
            active_document.cursors.set_cursors ({ primary });
          });
          return true;
        }
        return false;
      }

      if (ctrl || alt) {
        return false; // no other Ctrl/Alt combination is claimed yet
      }

      CursorMoveOp move_op;
      if (move_op_for_keyval (keyval, out move_op)) {
        apply_cursor_command (() => active_document.cursors.move (move_op, shift, get_text ()));
        return true;
      }

      if (!shift && keyval == Gdk.Key.Tab && !active_document.cursors.has_selection) {
        previous_typed_was_space = false;
        apply_tab ();
        return true;
      }

      if (keyval == Gdk.Key.BackSpace) {
        previous_typed_was_space = false;
        apply_backspace ();
        return true;
      }
      if (keyval == Gdk.Key.Delete || keyval == Gdk.Key.KP_Delete) {
        previous_typed_was_space = false;
        apply_edit (EditIntent.DELETE_RIGHT, "", EditKind.DELETING_RIGHT);
        return true;
      }
      if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
        previous_typed_was_space = false;
        apply_enter ();
        return true;
      }

      unichar ch = (unichar) Gdk.keyval_to_unicode (keyval);
      if (ch != 0 && !ch.iscntrl ()) {
        apply_edit (EditIntent.INSERT, ch.to_string (), typing_kind (ch));
        return true;
      }

      return false;
    }

    private string get_text () {
      return text_view.buffer.text;
    }

    private void write_selection_to_clipboard (bool remove_after) {
      if (active_document.cursors.primary.is_empty) {
        return;
      }

      var pieces = active_document.cursors.selected_texts (get_text ());
      string joined = string.joinv ("\n", pieces);
      text_view.get_clipboard ().set_text (joined);
      last_clipboard_text = joined;
      last_clipboard_pieces = pieces.length > 1 ? pieces : null;

      if (remove_after) {
        apply_edit (EditIntent.INSERT, "", EditKind.OTHER);
      }
    }

    private string[]? distributed_paste_pieces (string pasted_text, int cursor_count) {
      if (cursor_count == 1) {
        return null;
      }
      if (last_clipboard_pieces != null && pasted_text == last_clipboard_text && last_clipboard_pieces.length == cursor_count) {
        return last_clipboard_pieces;
      }

      string trimmed = pasted_text;
      if (trimmed.has_suffix ("\r\n")) {
        trimmed = trimmed.substring (0, trimmed.length - 2);
      } else if (trimmed.has_suffix ("\n") || trimmed.has_suffix ("\r")) {
        trimmed = trimmed.substring (0, trimmed.length - 1);
      }
      string[] lines = trimmed.split ("\n");
      return lines.length == cursor_count ? lines : null;
    }

    private async void paste_from_clipboard (Document document) {
      string? text = null;
      try {
        text = yield text_view.get_clipboard ().read_text_async (null);
      } catch (Error e) {
        return;
      }
      if (text == null || text == "" || active_document != document) {
        return;
      }

      string[]? pieces = distributed_paste_pieces (text, document.cursors.count);
      if (pieces == null) {
        apply_edit (EditIntent.INSERT, text, EditKind.OTHER);
      } else {
        apply_distributed_paste (pieces);
      }
    }

    private void apply_cursor_command (CursorCommand command) {
      previous_typed_was_space = false;
      command ();
      active_document.history.close_current_entry ();
      render ();
    }

    private void apply_edit (EditIntent intent, string typed_text, EditKind kind) {
      Cursor[] cursors_to_remove;
      var tagged_edits = active_document.cursors.compute_edits (intent, typed_text, get_text (), out cursors_to_remove);
      apply_tagged_edits (tagged_edits, cursors_to_remove, kind);
    }

    private void apply_distributed_paste (string[] texts) {
      Cursor[] cursors_to_remove;
      var tagged_edits = active_document.cursors.compute_distributed_paste_edits (texts, get_text (), out cursors_to_remove);
      apply_tagged_edits (tagged_edits, cursors_to_remove, EditKind.OTHER);
    }

    private void apply_enter () {
      Cursor[] cursors_to_remove;
      var tagged_edits = active_document.cursors.compute_enter_edits (insert_spaces, indent_size, get_text (), out cursors_to_remove);
      apply_tagged_edits (tagged_edits, cursors_to_remove, EditKind.OTHER);
    }

    private void apply_tab () {
      Cursor[] cursors_to_remove;
      var tagged_edits = active_document.cursors.compute_tab_edits (insert_spaces, indent_size, get_text (), out cursors_to_remove);
      apply_tagged_edits (tagged_edits, cursors_to_remove, EditKind.OTHER);
    }

    private void apply_backspace () {
      Cursor[] cursors_to_remove;
      var tagged_edits = active_document.cursors.compute_backspace_edits (indent_size, get_text (), out cursors_to_remove);
      apply_tagged_edits (tagged_edits, cursors_to_remove, EditKind.DELETING_LEFT);
    }

    private void apply_move_lines (bool down) {
      Cursor[] resulting_cursors;
      var edits = active_document.cursors.compute_move_lines_edits (down, get_text (), out resulting_cursors);
      if (edits.length == 0) {
        return;
      }

      var before_cursors = active_document.cursors.snapshot ();
      apply_edits (edits);
      active_document.cursors.set_cursors (resulting_cursors);
      active_document.history.push (edits, before_cursors, active_document.cursors.snapshot (), EditKind.OTHER);
      render ();
    }

    /** Applies `edits` as one atomic, non-coalescing history step not produced by any live cursor (Replace/Replace All results) — every cursor shifts to stay at its own logical position instead of being collapsed onto any of `edits`. */
    public void apply_external_edit (TextEdit[] edits) {
      if (active_document == null || edits.length == 0) {
        return;
      }

      var before_cursors = active_document.cursors.snapshot ();
      apply_edits (edits);
      active_document.cursors.shift_for_external_edits (edits);
      active_document.history.push (edits, before_cursors, active_document.cursors.snapshot (), EditKind.OTHER);
      render ();
    }

    private void apply_tagged_edits (TaggedTextEdit[] tagged_edits, Cursor[] cursors_to_remove, EditKind kind) {
      if (tagged_edits.length == 0) {
        return;
      }

      var document = active_document;
      var before_cursors = document.cursors.snapshot ();

      var edits = new TextEdit[tagged_edits.length];
      for (int i = 0; i < tagged_edits.length; i++) {
        edits[i] = tagged_edits[i].edit;
      }

      apply_edits (edits);
      document.cursors.apply_edit_results (tagged_edits, cursors_to_remove);
      document.history.push (edits, before_cursors, document.cursors.snapshot (), kind);

      render ();
    }

    private void apply_history_step (bool redo) {
      var entry = redo ? active_document.history.redo () : active_document.history.undo ();
      if (entry == null) {
        return;
      }

      if (redo) {
        for (uint i = 0; i < entry.pushes.length; i++) {
          apply_edits (entry.pushes[i].edits);
        }
      } else {
        for (int i = (int) entry.pushes.length - 1; i >= 0; i--) {
          apply_edits (entry.pushes[i].inverse_edits);
        }
      }

      var restored = redo ? entry.after_cursors : entry.before_cursors;
      var cloned = new Cursor[restored.length];
      for (int i = 0; i < restored.length; i++) {
        cloned[i] = restored[i].clone ();
      }
      active_document.cursors.set_cursors (cloned);

      render ();
    }

    /**
    * Mechanically replaces every [start_offset, end_offset) in `edits`
    * with its new_text, descending by start_offset so an edit's own
    * range is never invalidated by one applied after it. Internal —
    * nothing outside this class needs to mutate the buffer directly.
    */
    private void apply_edits (TextEdit[] edits) {
      if (edits.length == 0) {
        return;
      }

      var sorted = new TextEdit[edits.length];
      for (int i = 0; i < edits.length; i++) {
        sorted[i] = edits[i];
      }
      stable_sort_edits_descending (sorted);

      source_buffer.begin_user_action ();
      updating_programmatically = true;
      foreach (var edit in sorted) {
        Gtk.TextIter start_iter;
        Gtk.TextIter end_iter;
        source_buffer.get_iter_at_offset (out start_iter, edit.start_offset);
        source_buffer.get_iter_at_offset (out end_iter, edit.end_offset);
        source_buffer.delete (ref start_iter, ref end_iter);
        source_buffer.insert (ref start_iter, edit.new_text, -1);
      }
      updating_programmatically = false;
      source_buffer.end_user_action ();

      text_changed (get_text ());
    }

    private static void stable_sort_edits_descending (TextEdit[] edits) {
      for (int i = 1; i < edits.length; i++) {
        var key = edits[i];
        int j = i - 1;
        while (j >= 0 && edits[j].start_offset < key.start_offset) {
          edits[j + 1] = edits[j];
          j--;
        }
        edits[j + 1] = key;
      }
    }

    private EditKind typing_kind (unichar ch) {
      EditKind kind = ch == ' '
      ? (previous_typed_was_space ? EditKind.TYPING_CONSECUTIVE_SPACE : EditKind.TYPING_FIRST_SPACE)
      : EditKind.TYPING_OTHER;
      previous_typed_was_space = (ch == ' ');
      return kind;
    }

    private static bool move_op_for_keyval (uint keyval, out CursorMoveOp op) {
      switch (keyval) {
        case Gdk.Key.Left: op = CursorMoveOp.LEFT; return true;
        case Gdk.Key.Right: op = CursorMoveOp.RIGHT; return true;
        case Gdk.Key.Up: op = CursorMoveOp.UP; return true;
        case Gdk.Key.Down: op = CursorMoveOp.DOWN; return true;
        case Gdk.Key.Home: op = CursorMoveOp.HOME; return true;
        case Gdk.Key.End: op = CursorMoveOp.END; return true;
        default: op = CursorMoveOp.LEFT; return false;
      }
    }

    /**
     * A plain single/double/triple primary click — only Alt-modified ones
     * are claimed by click_gesture (see the constructor), so this only
     * ever actually does something for those; every other click still
     * reaches here too, but returns right away once the `!alt` check
     * fails below.
     */
    private void handle_click (int offset, int n_press, Gdk.ModifierType state) {
      if (active_document == null) {
        return;
      }

      previous_typed_was_space = false;
      active_document.history.close_current_entry ();
      box_select_anchor_offset = -1;
      alt_drag_active = false;

      bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
      if (n_press < 1 || n_press > 3 || !alt) {
        return;
      }

      if (n_press == 2) {
        active_document.cursors.expand_last_added_cursor_to_word (get_text ());
      } else if (n_press == 3) {
        active_document.cursors.expand_last_added_cursor_to_line (get_text ());
      } else {
        bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
        if (shift) {
          box_select_anchor_offset = offset;
          active_document.cursors.box_select (offset, offset, get_text ());
        } else {
          alt_drag_active = true;
          active_document.cursors.add_cursor_at_click (offset);
        }
      }
      render ();
    }

    /** Continues whichever of box-select/add-a-cursor handle_click() just started — mutually exclusive, see their own fields' doc comments. */
    private void handle_drag_extended (int offset, Gdk.ModifierType state) {
      if (active_document == null) {
        return;
      }

      if (box_select_anchor_offset >= 0) {
        active_document.cursors.box_select (box_select_anchor_offset, offset, get_text ());
        render ();
      } else if (alt_drag_active) {
        active_document.cursors.extend_last_added_cursor (offset);
        render ();
      }
    }

    /** Whether a press at widget-relative (x, y) landed inside the real native selection — only the primary selection is ever draggable (a drag has exactly one pointer). False for a non-editable buffer. */
    private bool is_inside_selection (double x, double y) {
      if (!text_view.editable) {
        return false;
      }

      Gtk.TextIter sel_start;
      Gtk.TextIter sel_end;
      if (!source_buffer.get_selection_bounds (out sel_start, out sel_end)) {
        return false;
      }
      int offset = offset_at_widget_position (x, y);
      return offset >= sel_start.get_offset () && offset < sel_end.get_offset ();
    }

    private int offset_at_widget_position (double widget_x, double widget_y) {
      int buffer_x;
      int buffer_y;
      text_view.window_to_buffer_coords (Gtk.TextWindowType.WIDGET, (int) widget_x, (int) widget_y, out buffer_x, out buffer_y);

      Gtk.TextIter iter;
      text_view.get_iter_at_location (out iter, buffer_x, buffer_y);
      return iter.get_offset ();
    }

    /** drag_selection's own drop landed. A no-op if dropped back inside (or at either edge of) its own original range. Needs the Model (active_document) — why this stays here rather than in TextEditorDragSelection itself, which has no reference to it. */
    private void on_drag_selection_dropped (SelectionSnapshot snapshot, int drop_offset) {
      if (active_document == null) {
        return;
      }
      int source_start = snapshot.start_offset;
      int source_end = snapshot.end_offset;
      string text = snapshot.text;
      if (drop_offset >= source_start && drop_offset <= source_end) {
        return;
      }

      previous_typed_was_space = false;
      active_document.history.close_current_entry ();

      var before_cursors = active_document.cursors.snapshot ();
      var delete_edit = new TextEdit () {
        start_offset = source_start, end_offset = source_end, old_text = text, new_text = ""
      };
      var insert_edit = new TextEdit () {
        start_offset = drop_offset, end_offset = drop_offset, old_text = "", new_text = text
      };

      // Order-independent: apply_edits() sorts its own edits highest-offset-first internally.
      apply_edits ({ delete_edit, insert_edit });

      int landed_start = drop_offset > source_end ? drop_offset - (source_end - source_start) : drop_offset;
      int landed_end = landed_start + text.char_count ();
      var new_cursor = new Cursor (landed_start);
      new_cursor.position_offset = landed_end; // anchor at the start, caret at the end
      active_document.cursors.set_cursors ({ new_cursor });

      TextEdit[] edits_ascending = source_start < drop_offset
        ? new TextEdit[] { delete_edit, insert_edit }
        : new TextEdit[] { insert_edit, delete_edit };
      active_document.history.push (edits_ascending, before_cursors, active_document.cursors.snapshot (), EditKind.OTHER);

      render ();
    }

    /**
     * The real insert/selection_bound marks moved for a reason this class
     * didn't itself drive (a native double/triple-click's word/line-select,
     * Ctrl+A, or any other native keybinding left unclaimed) — resyncs the
     * Model's own primary cursor to match and repaints, since the native
     * caret is never actually painted (only its marks move). Also fires
     * (harmlessly) right after render_cursors() sets those same marks
     * itself — suppressed via setting_cursors_programmatically above.
     *
     * preserve_native_direction (set by click_gesture's own pressed
     * handler) is the only case with a real "direction" worth keeping as-is
     * — a plain click, or the drag-select that can follow it. Every other
     * unclaimed native action has no such direction, so this normalizes to
     * caret >= anchor instead, regardless of which of GTK's own insert/
     * selection_bound its internal implementation happens to place where.
     */
    private void on_mark_set (Gtk.TextIter location, Gtk.TextMark mark) {
      if (setting_cursors_programmatically || active_document == null) {
        return;
      }
      if (mark.name != "insert" && mark.name != "selection_bound") {
        return;
      }

      int anchor = get_anchor_offset ();
      int position = get_position_offset ();

      if (preserve_native_direction) {
        resync_from_native (anchor, position);
      } else {
        resync_from_native (int.min (anchor, position), int.max (anchor, position));
      }
    }

    private void on_insert_text_native (ref Gtk.TextIter pos, string new_text, int new_text_length) {
      if (updating_programmatically || new_text == "" || active_document == null) {
        return;
      }

      int offset = pos.get_offset ();
      active_document.history.push (
        { new TextEdit () { start_offset = offset, end_offset = offset, old_text = "", new_text = new_text } },
        active_document.cursors.snapshot (), active_document.cursors.snapshot (), EditKind.OTHER
      );
    }

    private void on_delete_range_native (Gtk.TextIter start, Gtk.TextIter end) {
      if (updating_programmatically || active_document == null) {
        return;
      }

      active_document.history.push (
        { new TextEdit () {
          start_offset = start.get_offset (), end_offset = end.get_offset (),
          old_text = source_buffer.get_text (start, end, false), new_text = ""
        } },
        active_document.cursors.snapshot (), active_document.cursors.snapshot (), EditKind.OTHER
      );
    }

    /** Re-syncs from *after* an untracked native edit has actually landed — mark-set doesn't reliably fire for this case. Always normalized: a native edit (e.g. GtkSourceView's own Tab-indent) has no click-drag direction to preserve. */
    private void resync_native_cursor_after_native_edit () {
      if (updating_programmatically || active_document == null) {
        return;
      }
      int anchor = get_anchor_offset ();
      int position = get_position_offset ();
      resync_from_native (int.min (anchor, position), int.max (anchor, position));
    }

    /** Sets the Model's primary cursor to exactly `anchor`/`position` (no normalizing — callers decide that) and repaints. */
    private void resync_from_native (int anchor, int position) {
      var cursor = new Cursor (anchor);
      cursor.position_offset = position;
      active_document.cursors.set_cursors ({ cursor });
      render ();
    }

    private int get_position_offset () {
      Gtk.TextIter iter;
      source_buffer.get_iter_at_mark (out iter, source_buffer.get_insert ());
      return iter.get_offset ();
    }

    private int get_anchor_offset () {
      Gtk.TextIter iter;
      source_buffer.get_iter_at_mark (out iter, source_buffer.get_selection_bound ());
      return iter.get_offset ();
    }

    /**
     * Own registration, same shape VS Code's registerThemingParticipant
     * gets in viewCursors.ts (checked its source) — this class reacts to
     * the app's theme for its own tag's colors, no separate "theme"
     * object reaching in from outside.
     */
    private void apply_theme_colors () {
      focused_selection_background = SystemColor.from_accent ().transparentize (0.35f).to_rgba ();

      // Mirrors GTK's own ratio between its default (backdrop) and
      // :focus-within selection colors: an opaque, fully desaturated
      // color at half the alpha of the focused one.
      backdrop_selection_background = SystemColor.from_accent ()
        .desaturate ()
        .transparentize (focused_selection_background.alpha * 0.5f)
        .to_rgba ();

      update_selection_background ();
    }

    private void update_selection_background () {
      bool backdrop = (text_view.get_state_flags () & Gtk.StateFlags.BACKDROP) != 0;
      selection_tag.background_rgba = backdrop ? backdrop_selection_background : focused_selection_background;
    }

    private void render () {
      render_cursors (active_document.cursors.snapshot ());
    }

    public void render_cursors (Cursor[] cursors) {
      assert (cursors.length > 0);

      setting_cursors_programmatically = true;
      var primary = cursors[0];
      Gtk.TextIter primary_position;
      Gtk.TextIter primary_anchor;
      source_buffer.get_iter_at_offset (out primary_position, primary.position_offset);
      source_buffer.get_iter_at_offset (out primary_anchor, primary.anchor_offset);
      source_buffer.select_range (primary_position, primary_anchor);
      setting_cursors_programmatically = false;

      Gtk.TextIter buffer_start;
      Gtk.TextIter buffer_end;
      source_buffer.get_start_iter (out buffer_start);
      source_buffer.get_end_iter (out buffer_end);
      source_buffer.remove_tag_by_name (SELECTION_TAG_NAME, buffer_start, buffer_end);

      var caret_offsets = new int[cursors.length];
      for (int i = 0; i < cursors.length; i++) {
        var cursor = cursors[i];
        caret_offsets[i] = cursor.position_offset;

        if (!cursor.is_empty) {
          Gtk.TextIter selection_start;
          Gtk.TextIter selection_end;
          source_buffer.get_iter_at_offset (out selection_start, cursor.selection_start);
          source_buffer.get_iter_at_offset (out selection_end, cursor.selection_end);
          source_buffer.apply_tag_by_name (SELECTION_TAG_NAME, selection_start, selection_end);
        }
      }

      text_view.set_carets (caret_offsets);
      text_view.reset_blink ();
    }
  }
}
