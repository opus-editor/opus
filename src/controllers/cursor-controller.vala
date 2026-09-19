/**
 * Drives the currently active document's CursorCollection + EditHistory
 * from EditorView's raw input signals: classifies a keypress/click into
 * which Model method to call, then pushes the result back through
 * EditorView's own plain methods. All actual cursor/edit logic (normalize,
 * offset bookkeeping, coalescing) lives in the Models and is unit-tested
 * headlessly — this class only routes plain data between them, the same
 * shape as EditorController's own on_text_changed().
 *
 * Deliberately a sibling of EditorController, not folded into it: owning
 * the set of open tabs (EditorController's own job) doesn't overlap with
 * driving intra-buffer cursor/edit mechanics, and mixing the two would
 * work against keeping each cohesive.
 *
 * Arrows/Home/End, Backspace/Delete, typing, Enter, shift-select,
 * click-to-place, click-drag-select, EditHistory-backed undo/redo, and
 * the multi-cursor creation commands: Alt+Click adds a cursor,
 * Ctrl+Alt+Up/Down adds one directly above/below, Ctrl+D adds the next
 * match of the current selection (or selects the word under the caret on
 * an empty one), Ctrl+Shift+L selects every occurrence at once, and
 * Alt+Shift+drag does a column (box) select — the exact modifier VS
 * Code's own mouse handler uses (verified in its source, viewController.
 * ts: plain Alt is "add a cursor", only Alt+Shift is column-select).
 */
public class CursorController : Object {
    private delegate void CursorCommand ();

    private EditorView editor_view;
    private Document? active_document = null;

    // Whether the most recently typed character (in the still-open
    // typing run) was a space — the only way to tell EditKind.
    // TYPING_FIRST_SPACE apart from TYPING_CONSECUTIVE_SPACE, since that
    // distinction depends on what came immediately before it, not
    // anything about the keystroke itself. Reset to false by every
    // non-single-character-typing action.
    private bool previous_typed_was_space = false;

    // Set by on_click() when an Alt+Shift click starts a column (box)
    // select drag — box_select()'s fixed anchor corner, expanded from on
    // every subsequent on_drag_extended() call. -1 means "not
    // box-selecting right now": a plain drag just extends the primary
    // cursor's own selection instead.
    private int box_select_anchor_offset = -1;

    public CursorController (EditorView editor_view) {
        this.editor_view = editor_view;
        editor_view.set_undo_enabled (false);

        editor_view.key_pressed_raw.connect (on_key_pressed);
        editor_view.click_raw.connect (on_click);
        editor_view.drag_extended_raw.connect (on_drag_extended);
        editor_view.native_cursor_moved.connect (on_native_cursor_moved);
    }

    /**
     * Which document's cursors/history this controller is currently
     * driving — null when no tab is active. Leaving a document mid-
     * typing always closes its own open undo entry — coming back to it
     * later (even seconds later) must never silently resume coalescing
     * into whatever was left open.
     *
     * Also renders the newly-active document's own cursors: the native
     * caret is never painted any more (see EditorView's
     * cursor_visible = false), so without an explicit render here,
     * activating a document whose cursor happens to already sit at the
     * same buffer position the view was just showing (nothing actually
     * moved, so GtkTextView's own mark-set never fires) left no cursor
     * visible at all until the next keystroke — most reproducibly a
     * brand-new tab's first-ever activation, still at the buffer's
     * default position 0.
     */
    public void set_active_document (Document? document) {
        if (active_document != null) {
            active_document.history.close_current_entry ();
        }

        active_document = document;
        previous_typed_was_space = false;

        if (active_document != null) {
            render ();
        }
    }

    private bool on_key_pressed (uint keyval, Gdk.ModifierType state) {
        if (active_document == null) {
            return false;
        }

        bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
        bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
        bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;

        // Shift changes which keyval a letter key reports (Gdk.Key.z vs
        // Gdk.Key.Z) — normalize so every Ctrl-combination check below
        // only has to compare against the one lowercase constant and
        // decide on `shift` explicitly, rather than duplicating each
        // check for both cases.
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

        if (ctrl && alt && !shift && keyval == Gdk.Key.Up) {
            apply_cursor_command (() => active_document.cursors.add_cursor_above (editor_view.get_text ()));
            return true;
        }
        if (ctrl && alt && !shift && keyval == Gdk.Key.Down) {
            apply_cursor_command (() => active_document.cursors.add_cursor_below (editor_view.get_text ()));
            return true;
        }
        if (ctrl && !alt && !shift && lower_keyval == Gdk.Key.d) {
            apply_cursor_command (() => active_document.cursors.add_cursor_at_next_match (editor_view.get_text ()));
            return true;
        }
        if (ctrl && !alt && shift && lower_keyval == Gdk.Key.l) {
            apply_cursor_command (() => active_document.cursors.select_all_occurrences (editor_view.get_text ()));
            return true;
        }
        // Word-jump — verified against VS Code's real source
        // (wordOperations.ts): Ctrl+Right is `cursorWordEndRight`
        // (WordNavigationType.WordEnd, lands at the end of the current/
        // next word) and Ctrl+Left is `cursorWordLeft`
        // (WordNavigationType.WordStartFast, lands at the start of the
        // previous word). CursorCollection's own word_left()/word_right()
        // already implement that — this was only ever missing from the
        // key dispatch below.
        if (ctrl && !alt && (keyval == Gdk.Key.Left || keyval == Gdk.Key.Right)) {
            var move_op = keyval == Gdk.Key.Left ? CursorMoveOp.WORD_LEFT : CursorMoveOp.WORD_RIGHT;
            apply_cursor_command (() => active_document.cursors.move (move_op, shift, editor_view.get_text ()));
            return true;
        }

        // Two distinct VS Code commands, both bound to plain Escape (and
        // Shift+Escape) — verified in its real source, coreCommands.ts:
        // RemoveSecondaryCursors (precondition: more than one cursor,
        // higher priority) keeps the primary cursor exactly as it is,
        // selection included, and just drops every other one; only when
        // that precondition doesn't hold does CancelSelection (a single
        // cursor with a non-empty selection) get a turn, collapsing that
        // selection to its caret end specifically — not its anchor (see
        // CursorMoveCommands.cancelSelection, which rebuilds the state
        // from `cursor.viewState.position`, the moving end).
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
            return false; // a single cursor with no selection matches neither command — nothing to do
        }

        if (ctrl || alt) {
            return false; // no other Ctrl/Alt combination is claimed yet
        }

        CursorMoveOp move_op;
        if (move_op_for_keyval (keyval, out move_op)) {
            apply_cursor_command (() => active_document.cursors.move (move_op, shift, editor_view.get_text ()));
            return true;
        }

        if (keyval == Gdk.Key.BackSpace) {
            previous_typed_was_space = false;
            apply_edit (EditIntent.DELETE_LEFT, "", EditKind.DELETING_LEFT);
            return true;
        }
        if (keyval == Gdk.Key.Delete || keyval == Gdk.Key.KP_Delete) {
            previous_typed_was_space = false;
            apply_edit (EditIntent.DELETE_RIGHT, "", EditKind.DELETING_RIGHT);
            return true;
        }
        if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
            previous_typed_was_space = false;
            apply_edit (EditIntent.INSERT, "\n", EditKind.OTHER);
            return true;
        }

        // Anything with a Unicode codepoint and no Ctrl/Alt held is typed
        // as-is. Deliberately not a full IME-aware input pipeline — see
        // the plan's own risk list: composed/IME input (CJK, dead keys)
        // isn't in this allow-list, so it falls through to GtkSourceView's
        // native handling instead of being (mis)claimed here, and
        // native_cursor_moved keeps the tracked cursor in sync with
        // wherever that native path actually lands.
        unichar ch = (unichar) Gdk.keyval_to_unicode (keyval);
        if (ch != 0 && !ch.iscntrl ()) {
            apply_edit (EditIntent.INSERT, ch.to_string (), typing_kind (ch));
            return true;
        }

        return false;
    }

    private void on_click (int offset, int n_press, uint button, Gdk.ModifierType state) {
        if (active_document == null || button != 1) {
            return;
        }

        // Bookkeeping runs for every click, even ones we don't act on
        // further below — a plain/Shift/double/triple-click is a
        // non-edit action same as any other, and EditorView still claims
        // nothing for those (see index.vala's click_gesture), so
        // GtkTextView's own native handling runs and native_cursor_moved
        // picks up wherever it lands.
        previous_typed_was_space = false;
        active_document.history.close_current_entry ();

        bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
        if (n_press != 1 || !alt) {
            return; // not one of ours — native handles it, native_cursor_moved resyncs afterward
        }

        bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
        if (shift) {
            box_select_anchor_offset = offset;
            active_document.cursors.box_select (offset, offset, editor_view.get_text ());
        } else {
            box_select_anchor_offset = -1;
            active_document.cursors.add_cursor_at_click (offset);
        }
        render ();
    }

    // Only ever called for the Alt+Shift box-select drag now — EditorView
    // only claims (and so only keeps driving drag_extended_raw for) that
    // one case; a plain click-drag-select is entirely native.
    private void on_drag_extended (int offset, Gdk.ModifierType state) {
        if (active_document == null || box_select_anchor_offset < 0) {
            return;
        }

        active_document.cursors.box_select (box_select_anchor_offset, offset, editor_view.get_text ());
        render ();
    }

    // The buffer's real marks moved for a reason this controller didn't
    // itself drive — a plain/Shift click, a native double/triple-click,
    // a click-drag-select, or an unclaimed key (EditorView already
    // suppresses this during its own render_cursors() call, so a
    // multi-cursor set this controller just rendered doesn't collapse
    // right back to one on its own). Always replacing the whole set with
    // a single cursor is still the right call here: every one of those
    // is a single-point mouse/keyboard operation the user is using right
    // now — a plain click always means "just this one cursor," whether
    // it's this controller or GtkTextView's own native handling that
    // ends up deciding where.
    //
    // Also renders: the native caret is never painted any more (see
    // EditorView's cursor_visible = false), so nothing else makes this
    // new position visible on screen — without this, a plain click
    // updated the model correctly but the caret only actually moved on
    // whatever key was pressed next.
    private void on_native_cursor_moved (int anchor_offset, int position_offset) {
        if (active_document == null) {
            return;
        }

        var cursor = new Cursor (anchor_offset);
        cursor.position_offset = position_offset;
        active_document.cursors.set_cursors ({ cursor });
        render ();
    }

    /** Runs a cursor-only command (movement, or a multi-cursor creation command) — none of these touch any text, so unlike apply_edit() there's nothing to push onto EditHistory; they just close whatever undo entry is currently open, same as any other non-edit action, and re-render. */
    private void apply_cursor_command (CursorCommand command) {
        previous_typed_was_space = false;
        command ();
        active_document.history.close_current_entry ();
        render ();
    }

    private void apply_edit (EditIntent intent, string typed_text, EditKind kind) {
        var document = active_document;
        var text = editor_view.get_text ();
        var before_cursors = document.cursors.snapshot ();

        Cursor[] cursors_to_remove;
        var tagged_edits = document.cursors.compute_edits (intent, typed_text, text, out cursors_to_remove);
        if (tagged_edits.length == 0) {
            return;
        }

        var edits = new TextEdit[tagged_edits.length];
        for (int i = 0; i < tagged_edits.length; i++) {
            edits[i] = tagged_edits[i].edit;
        }

        editor_view.apply_edits (edits);
        document.cursors.apply_edit_results (tagged_edits, cursors_to_remove);

        // EditHistory rebases each push's own edits into a correct
        // inverse batch internally (TextEdit.invert_batch) before
        // coalescing it with an adjacent keystroke's — so a run of
        // multi-cursor typing coalesces into one undo step exactly like
        // single-cursor typing does, without corrupting anything.
        document.history.push (edits, before_cursors, document.cursors.snapshot (), kind);

        render ();
    }

    private void apply_history_step (bool redo) {
        var entry = redo ? active_document.history.redo () : active_document.history.undo ();
        if (entry == null) {
            return;
        }

        // Each coalesced keystroke is only self-consistent on its own —
        // see EditHistory.push()'s own comment — so they're replayed one
        // push at a time, not as one flattened batch: forward (redo) in
        // the order they originally happened, inverse (undo) in reverse.
        if (redo) {
            for (uint i = 0; i < entry.pushes.length; i++) {
                editor_view.apply_edits (entry.pushes[i].edits);
            }
        } else {
            for (int i = (int) entry.pushes.length - 1; i >= 0; i--) {
                editor_view.apply_edits (entry.pushes[i].inverse_edits);
            }
        }

        // Clone before handing these to the live collection — later
        // edits mutate cursors in place (see CursorCollection.
        // apply_edit_results), which would otherwise corrupt this same
        // entry still sitting in the undo/redo stack.
        var restored = redo ? entry.after_cursors : entry.before_cursors;
        var cloned = new Cursor[restored.length];
        for (int i = 0; i < restored.length; i++) {
            cloned[i] = restored[i].clone ();
        }
        active_document.cursors.set_cursors (cloned);

        render ();
    }

    private void render () {
        editor_view.render_cursors (active_document.cursors.snapshot ());
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
        case Gdk.Key.Left:
            op = CursorMoveOp.LEFT;
            return true;
        case Gdk.Key.Right:
            op = CursorMoveOp.RIGHT;
            return true;
        case Gdk.Key.Up:
            op = CursorMoveOp.UP;
            return true;
        case Gdk.Key.Down:
            op = CursorMoveOp.DOWN;
            return true;
        case Gdk.Key.Home:
            op = CursorMoveOp.HOME;
            return true;
        case Gdk.Key.End:
            op = CursorMoveOp.END;
            return true;
        default:
            op = CursorMoveOp.LEFT;
            return false;
        }
    }
}
