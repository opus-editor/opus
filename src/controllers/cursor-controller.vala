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
 * the multi-cursor creation commands: Alt+Click adds a cursor (Alt-drag
 * continuing past the click extends that same cursor into a selection,
 * exactly like a plain drag extends the primary cursor's own — see
 * extend_last_added_cursor()'s own doc comment for the deliberate
 * choice not to special-case what happens when that selection ends up
 * overlapping another cursor's), Shift+Alt+Up/Down adds one directly
 * above/below (VS Code's own Linux keybinding for this — see that
 * check's own comment for why not Ctrl+Alt+Up/Down, its Windows/Mac
 * one), Ctrl+D adds the next match of the current selection (or
 * selects the word under the caret on an empty one), Ctrl+Shift+L
 * selects every occurrence at once, and Alt+Shift+drag does a column
 * (box) select — the exact modifier VS Code's own mouse handler uses
 * (verified in its source, viewController.ts: plain Alt is "add a
 * cursor", only Alt+Shift is column-select).
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

    // Set by on_click() when a plain (non-Shift) Alt+click just added a
    // new cursor — on_drag_extended() extends that same cursor into a
    // selection on every subsequent call, exactly like a plain drag
    // extends the primary cursor's own. Both this and
    // box_select_anchor_offset are reset on every single click,
    // regardless of type, so neither can ever linger stale from an
    // earlier, unrelated drag.
    private bool alt_drag_active = false;

    public CursorController (EditorView editor_view) {
        this.editor_view = editor_view;
        editor_view.set_undo_enabled (false);

        editor_view.key_pressed_raw.connect (on_key_pressed);
        editor_view.click_raw.connect (on_click);
        editor_view.drag_extended_raw.connect (on_drag_extended);
        editor_view.native_cursor_moved.connect (on_native_cursor_moved);
        editor_view.untracked_edit.connect (on_untracked_edit);
        editor_view.selection_dropped.connect (on_selection_dropped);
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

        // Claimed ourselves — same reasoning as select-all's own fix:
        // GTK's native cut/paste bypass this controller's edit pipeline
        // entirely (like drag-and-drop's insert/delete), so nothing
        // would ever reach EditHistory for them. Unlike drag-and-drop,
        // these are a single keystroke each, so there's no native
        // interaction (icon, motion, drop target) worth keeping —
        // reusing apply_edit() outright is simpler than reconstructing
        // after the fact.
        if (ctrl && !alt && !shift && lower_keyval == Gdk.Key.x) {
            if (!active_document.cursors.primary.is_empty) {
                editor_view.copy_selection_to_clipboard ();
                apply_edit (EditIntent.INSERT, "", EditKind.OTHER);
            }
            return true;
        }
        if (ctrl && !alt && !shift && lower_keyval == Gdk.Key.v) {
            paste_from_clipboard.begin (active_document);
            return true;
        }

        // Shift+Alt, not Ctrl+Alt: VS Code's own default for "Add Cursor
        // Above/Below" is Ctrl+Alt+Up/Down on Windows/Mac, but Shift+Alt+
        // Up/Down specifically on Linux (confirmed in its keybindings,
        // multicursor.ts) — because Ctrl+Alt+Up/Down is GNOME's own
        // default "switch workspace" shortcut (confirmed live: `gsettings
        // get org.gnome.desktop.wm.keybindings switch-to-workspace-up`),
        // intercepted by the compositor before any application ever sees
        // it. Matching VS Code's Linux choice avoids that collision.
        if (alt && shift && !ctrl && keyval == Gdk.Key.Up) {
            apply_cursor_command (() => active_document.cursors.add_cursor_above (editor_view.get_text ()));
            return true;
        }
        if (alt && shift && !ctrl && keyval == Gdk.Key.Down) {
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
        box_select_anchor_offset = -1;
        alt_drag_active = false;

        bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
        if (n_press < 1 || n_press > 3 || !alt) {
            return; // not one of ours — native handles it, native_cursor_moved resyncs afterward
        }

        if (n_press == 2) {
            active_document.cursors.expand_last_added_cursor_to_word (editor_view.get_text ());
        } else if (n_press == 3) {
            active_document.cursors.expand_last_added_cursor_to_line (editor_view.get_text ());
        } else {
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            if (shift) {
                box_select_anchor_offset = offset;
                active_document.cursors.box_select (offset, offset, editor_view.get_text ());
            } else {
                alt_drag_active = true;
                active_document.cursors.add_cursor_at_click (offset);
            }
        }
        render ();
    }

    // Called for both Alt-drag cases now — EditorView keeps driving
    // drag_extended_raw for either; a plain click-drag-select is
    // entirely native. box_select_anchor_offset/alt_drag_active are
    // mutually exclusive and both reset on every click (see on_click),
    // so exactly one of these branches ever applies for a given drag.
    private void on_drag_extended (int offset, Gdk.ModifierType state) {
        if (active_document == null) {
            return;
        }

        if (box_select_anchor_offset >= 0) {
            active_document.cursors.box_select (box_select_anchor_offset, offset, editor_view.get_text ());
            render ();
        } else if (alt_drag_active) {
            active_document.cursors.extend_last_added_cursor (offset);
            render ();
        }
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

    /**
     * The real buffer changed through some native GTK path this
     * controller didn't drive itself — a defense-in-depth net for
     * whatever that turns out to be (see EditorView.untracked_edit's own
     * doc comment; drag-and-drop used to be the concrete example here
     * before Opus reimplemented that itself — see on_selection_dropped
     * — but this stays in place for anything else, e.g. an external
     * app's text dropped in). Pushed as its own EditKind.OTHER entry,
     * which never coalesces with anything else. Not a data-loss risk:
     * EditKind.OTHER just means "its own undo step," not "approximate"
     * — the edit itself came straight from Gtk.TextBuffer's own
     * insert-text/delete-range parameters, not a reconstructed diff.
     */
    private void on_untracked_edit (TextEdit edit) {
        if (active_document == null) {
            return;
        }

        previous_typed_was_space = false;
        var cursors_snapshot = active_document.cursors.snapshot ();
        active_document.history.push ({ edit }, cursors_snapshot, cursors_snapshot, EditKind.OTHER);
    }

    /**
     * The primary selection's own drag-to-move landed — Opus's own
     * reimplementation of native drag-move (see EditorView.
     * selection_dropped's own doc comment for why native DnD can't be
     * used here at all). Unlike untracked_edit() above, both halves of
     * the move are known up front here, so they're pushed as a single
     * atomic TextEdit[] (one EditHistory entry, one Ctrl+Z) via
     * apply_edits() directly — not routed through compute_edits()/
     * apply_edit(): those are inherently per-cursor and relative to
     * *live* cursor positions, and this move's two edits are at fixed,
     * cursor-independent offsets instead. Leaves the moved text selected
     * at its new destination, matching VS Code's own convention (anchor
     * at the start, caret at the end) — native GTK never did this.
     */
    private void on_selection_dropped (string text, int source_start, int source_end, int drop_offset) {
        if (active_document == null) {
            return;
        }
        if (drop_offset >= source_start && drop_offset <= source_end) {
            return; // dropped back inside (or at either edge of) its own original range — a no-op, matches VS Code
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

        // Order-independent: apply_edits() sorts its own edits highest-
        // offset-first internally before applying them.
        editor_view.apply_edits ({ delete_edit, insert_edit });

        int landed_start = drop_offset > source_end ? drop_offset - (source_end - source_start) : drop_offset;
        int landed_end = landed_start + text.char_count ();
        var new_cursor = new Cursor (landed_start);
        new_cursor.position_offset = landed_end; // anchor at the start, caret at the end
        active_document.cursors.set_cursors ({ new_cursor });

        // EditHistory.push() -> TextEdit.invert_batch() requires edits
        // sorted *ascending* by start_offset — a different requirement
        // from apply_edits()'s own descending order above, so this
        // can't reuse the same array as-is.
        TextEdit[] edits_ascending = source_start < drop_offset
            ? new TextEdit[] { delete_edit, insert_edit }
            : new TextEdit[] { insert_edit, delete_edit };
        active_document.history.push (edits_ascending, before_cursors, active_document.cursors.snapshot (), EditKind.OTHER);

        render ();
    }

    /** Runs a cursor-only command (movement, or a multi-cursor creation command) — none of these touch any text, so unlike apply_edit() there's nothing to push onto EditHistory; they just close whatever undo entry is currently open, same as any other non-edit action, and re-render. */
    private void apply_cursor_command (CursorCommand command) {
        previous_typed_was_space = false;
        command ();
        active_document.history.close_current_entry ();
        render ();
    }

    /** Paste's own async half — clipboard reads can't be synchronous in GTK4. Re-checks active_document once the read comes back: the user could have switched tabs in that gap, and this must never land in whatever tab happens to be active by then. */
    private async void paste_from_clipboard (Document document) {
        string? text = yield editor_view.read_clipboard_text ();
        if (text == null || text == "" || active_document != document) {
            return;
        }

        apply_edit (EditIntent.INSERT, text, EditKind.OTHER);
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
