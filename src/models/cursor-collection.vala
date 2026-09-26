/** Cursor movement commands that don't themselves change any text. */
public enum CursorMoveOp {
    LEFT,
    RIGHT,
    UP,
    DOWN,
    WORD_LEFT,
    WORD_RIGHT,
    HOME,
    END,
    DOCUMENT_START,
    DOCUMENT_END
}

/** What a single keystroke's edit should do to each cursor's own range. */
public enum EditIntent {
    INSERT,
    DELETE_LEFT,
    DELETE_RIGHT
}

/**
 * One cursor's edit, paired with the live cursor that produced it — lets
 * {@link CursorCollection.apply_edit_results} reposition (or drop) the
 * right cursor once every cursor's edit in a batch has been resolved.
 * Never stored past that call — {@link EditHistory} only ever sees the
 * plain {@link TextEdit}s themselves.
 */
public class TaggedTextEdit : Object {
    public TextEdit edit { get; set; }
    public Cursor cursor { get; set; }
}

/**
 * The full set of simultaneous cursors/selections for one document, plus
 * every operation that moves them, creates more of them, or turns a
 * keystroke into the right multi-range text edit. Every method is pure
 * with respect to text: it's always passed the document's current content
 * explicitly and never touches a GTK buffer.
 *
 * Invariant: {@link count} is always at least 1, and {@link primary}
 * (`cursors[0]`) is always the first surviving cursor in original
 * insertion order — see {@link normalize}.
 */
public class CursorCollection : Object {
    private const unichar NEWLINE = '\n';

    private GenericArray<Cursor> cursors;
    private Cursor? last_added_cursor = null;

    public CursorCollection () {
        cursors = new GenericArray<Cursor> ();
        cursors.add (new Cursor (0));
    }

    public int count { get { return (int) cursors.length; } }
    public Cursor primary { get { return cursors[0]; } }

    /** Whether any cursor (not just the primary) currently has a non-empty selection — Cut/Copy/Delete's own "is there anything to act on" check, e.g. for EditorView.TextEditor's context menu. */
    public bool has_selection {
        get {
            for (uint i = 0; i < cursors.length; i++) {
                if (!cursors[i].is_empty) {
                    return true;
                }
            }
            return false;
        }
    }

    public Cursor at (int index) {
        return cursors[(uint) index];
    }

    /** Independent copies of every current cursor — for capturing a before/after snapshot into undo history without aliasing the live, mutating cursors. */
    public Cursor[] snapshot () {
        var result = new Cursor[cursors.length];
        for (uint i = 0; i < cursors.length; i++) {
            result[i] = cursors[i].clone ();
        }
        return result;
    }

    /**
     * Replaces the whole cursor set and re-establishes every invariant —
     * the one entry point every mutator below (and every multi-cursor
     * creation command) funnels through, so there's no separate
     * "multi-cursor mode": adding cursors is just building a new array
     * and handing it here. `new_last_added`, if given, is the cursor
     * that wins any merge tie against an older one that now overlaps it
     * (see {@link normalize}).
     */
    public void set_cursors (Cursor[] new_cursors, Cursor? new_last_added = null) {
        assert (new_cursors.length > 0);
        cursors = new GenericArray<Cursor> ();
        foreach (var cursor in new_cursors) {
            cursors.add (cursor);
        }
        last_added_cursor = new_last_added;
        normalize ();
    }

    /** Alt+Click on an existing secondary cursor to remove just that one — a no-op if it's the only cursor left. */
    public void remove_cursor_at (int index) {
        if (cursors.length <= 1) {
            return;
        }

        var result = new Cursor[cursors.length - 1];
        int w = 0;
        for (uint i = 0; i < cursors.length; i++) {
            if ((int) i != index) {
                result[w++] = cursors[i];
            }
        }
        set_cursors (result);
    }

    /** Alt+Click on empty space to add a new collapsed cursor at `offset`. */
    public void add_cursor_at_click (int offset) {
        var extra = new Cursor (offset);
        var result = new Cursor[cursors.length + 1];
        for (uint i = 0; i < cursors.length; i++) {
            result[i] = cursors[i];
        }
        result[cursors.length] = extra;
        set_cursors (result, extra);
    }

    /**
     * Alt+drag continuing past the initial click that added a cursor
     * (add_cursor_at_click) — moves that same cursor's own caret to
     * `new_position` while keeping its anchor fixed at the original
     * click point, extending it into a selection exactly like a plain
     * drag extends the primary cursor's own selection. No-op if there's
     * no last-added cursor (shouldn't happen in practice — this is only
     * ever called while an Alt-drag that just added one is still live).
     *
     * Re-normalizes afterward, same as any other cursor-set change: if
     * the growing selection now overlaps another cursor, they merge
     * into the union of both, the same way any other overlap does
     * (Ctrl+D, box-select, ...) — no special-casing for this one, by
     * design, to keep the app's own overlap behavior consistent with
     * itself rather than picking a different rule for Alt-drag alone.
     */
    public void extend_last_added_cursor (int new_position) {
        if (last_added_cursor == null) {
            return;
        }

        last_added_cursor.position_offset = new_position;
        var result = new Cursor[cursors.length];
        for (uint i = 0; i < cursors.length; i++) {
            result[i] = cursors[i];
        }
        set_cursors (result, last_added_cursor);
    }

    /**
     * Alt+DoubleClick: expands the just-added cursor (add_cursor_at_click)
     * to the word touching its own position — matching VS Code's own
     * LastCursorWordSelect, minus its drag-to-extend-by-word nuance
     * (dragging further after the double-click keeps growing the
     * selection word-by-word there); left out here to keep this to a
     * single click, same simplicity trade-off as extend_last_added_cursor()
     * makes for overlap. No-op if there's no last-added cursor, or it
     * isn't sitting on/next to a word.
     */
    public void expand_last_added_cursor_to_word (string text) {
        if (last_added_cursor == null) {
            return;
        }

        var chars = to_chars (text);
        int start = find_word_boundary_start (chars, last_added_cursor.position_offset);
        int end = find_word_boundary_end (chars, last_added_cursor.position_offset);
        if (start == end) {
            return;
        }

        last_added_cursor.anchor_offset = start;
        last_added_cursor.position_offset = end;
        last_added_cursor.anchor_kind = CursorAnchorKind.WORD;

        var result = new Cursor[cursors.length];
        for (uint i = 0; i < cursors.length; i++) {
            result[i] = cursors[i];
        }
        set_cursors (result, last_added_cursor);
    }

    /**
     * Alt+TripleClick: expands the just-added cursor to its whole
     * line — deliberately *not* including the trailing newline (unlike
     * VS Code's own LastCursorLineSelect, which does, landing the caret
     * at the start of the next line instead): checked by hand against a
     * plain triple-click, which already leaves the caret on the same
     * line, not the one below — matching that existing, native
     * convention here keeps Opus consistent with itself, which matters
     * more here than matching VS Code's own choice. Also leaves out
     * LastCursorLineSelect's drag-to-extend-by-line nuance, same
     * reasoning as expand_last_added_cursor_to_word() above.
     */
    public void expand_last_added_cursor_to_line (string text) {
        if (last_added_cursor == null) {
            return;
        }

        var chars = to_chars (text);
        int start = line_start (chars, last_added_cursor.position_offset);
        int end = line_end (chars, last_added_cursor.position_offset);

        last_added_cursor.anchor_offset = start;
        last_added_cursor.position_offset = end;

        var result = new Cursor[cursors.length];
        for (uint i = 0; i < cursors.length; i++) {
            result[i] = cursors[i];
        }
        set_cursors (result, last_added_cursor);
    }

    /** Arrow keys, word jumps, Home/End, and document-start/end — maps one pure per-cursor move over every cursor independently, then merges any that now collide. `extend` is whether Shift is held (grow the selection) or not (collapse to the new position). */
    public void move (CursorMoveOp op, bool extend, string text) {
        var chars = to_chars (text);
        var moved = new Cursor[cursors.length];
        for (uint i = 0; i < cursors.length; i++) {
            moved[i] = move_one (cursors[i], op, extend, chars);
        }
        set_cursors (moved, last_added_cursor);
    }

    public void add_cursor_above (string text) {
        add_cursor_vertical (text, -1);
    }

    public void add_cursor_below (string text) {
        add_cursor_vertical (text, 1);
    }

    private void add_cursor_vertical (string text, int direction) {
        var chars = to_chars (text);
        var result = new Cursor[cursors.length * 2];
        Cursor? new_last = null;

        for (uint i = 0; i < cursors.length; i++) {
            result[i] = cursors[i];
        }
        for (uint i = 0; i < cursors.length; i++) {
            var vertical = move_vertical (chars, cursors[i].position_offset, cursors[i].leftover_column, direction);
            var extra = new Cursor (vertical.offset);
            extra.leftover_column = vertical.leftover_column;
            result[cursors.length + i] = extra;
            new_last = extra;
        }

        set_cursors (result, new_last);
    }

    /**
     * Ctrl+D: on an empty selection, expands the last cursor in the
     * collection to the word it's touching (no search yet — that's what
     * makes the very first press just select the word). On a non-empty
     * one, searches forward from the end of that same last cursor for
     * the next occurrence of its selected text and appends a new cursor
     * there. A no-op if there's no word under the caret, or no further
     * match.
     */
    public void add_cursor_at_next_match (string text) {
        var chars = to_chars (text);
        var last = cursors[cursors.length - 1];

        if (last.is_empty) {
            int start = find_word_boundary_start (chars, last.position_offset);
            int end = find_word_boundary_end (chars, last.position_offset);
            if (start == end) {
                return;
            }

            var expanded = last.clone ();
            expanded.anchor_offset = start;
            expanded.position_offset = end;
            expanded.anchor_kind = CursorAnchorKind.WORD;

            var result = new Cursor[cursors.length];
            for (uint i = 0; i < cursors.length - 1; i++) {
                result[i] = cursors[i];
            }
            result[cursors.length - 1] = expanded;
            set_cursors (result, expanded);
            return;
        }

        string needle = chars_to_string (chars, last.selection_start, last.selection_end);
        int found = find_next (chars, needle, last.selection_end);
        if (found < 0) {
            return;
        }

        var match = new Cursor (found);
        match.anchor_offset = found;
        match.position_offset = found + needle.char_count ();

        var appended = new Cursor[cursors.length + 1];
        for (uint i = 0; i < cursors.length; i++) {
            appended[i] = cursors[i];
        }
        appended[cursors.length] = match;
        set_cursors (appended, match);
    }

    /** Finds every occurrence of the primary cursor's currently selected text and selects all of them at once. A no-op if the primary selection is empty. */
    public void select_all_occurrences (string text) {
        var chars = to_chars (text);
        var primary_cursor = cursors[0];
        if (primary_cursor.is_empty) {
            return;
        }

        string needle = chars_to_string (chars, primary_cursor.selection_start, primary_cursor.selection_end);
        int needle_length = needle.char_count ();

        var matches = new GenericArray<Cursor> ();
        int from = 0;
        while (true) {
            int found = find_next (chars, needle, from);
            if (found < 0) {
                break;
            }

            var match = new Cursor (found);
            match.anchor_offset = found;
            match.position_offset = found + needle_length;
            matches.add (match);
            from = found + needle_length;
        }

        if (matches.length == 0) {
            return;
        }

        var result = new Cursor[matches.length];
        for (uint i = 0; i < matches.length; i++) {
            result[i] = matches[i];
        }
        set_cursors (result, result[result.length - 1]);
    }

    /**
     * Column/box select between two offsets: one cursor per line spanned,
     * each selecting the same raw character-column range (falling back
     * to end-of-line on a shorter line). Character columns, not
     * tab-expanded visual ones — a deliberate simplification for now,
     * since visual width depends on the View's tab-width setting, which
     * this GTK-free model has no access to; worth revisiting once the
     * View layer lands.
     */
    public void box_select (int anchor_offset, int focus_offset, string text) {
        var chars = to_chars (text);
        int anchor_line = line_number_at (chars, anchor_offset);
        int focus_line = line_number_at (chars, focus_offset);
        int anchor_column = anchor_offset - line_start (chars, anchor_offset);
        int focus_column = focus_offset - line_start (chars, focus_offset);

        int from_line = int.min (anchor_line, focus_line);
        int to_line = int.max (anchor_line, focus_line);
        int start_column = int.min (anchor_column, focus_column);
        int end_column = int.max (anchor_column, focus_column);

        var result = new GenericArray<Cursor> ();
        int offset = find_line_start_offset (chars, from_line);
        for (int line = from_line; line <= to_line; line++) {
            int line_end_offset = line_end (chars, offset);
            int line_length = line_end_offset - offset;

            int column_start = int.min (start_column, line_length);
            int column_end = int.min (end_column, line_length);

            var cursor = new Cursor (offset + column_start);
            cursor.position_offset = offset + column_end;
            result.add (cursor);

            offset = (line_end_offset < chars.length) ? line_end_offset + 1 : line_end_offset;
        }

        if (result.length == 0) {
            return;
        }

        var arr = new Cursor[result.length];
        for (uint i = 0; i < result.length; i++) {
            arr[i] = result[i];
        }
        set_cursors (arr, arr[arr.length - 1]);
    }

    /**
     * Builds one text edit per cursor for a single keystroke (typed
     * insertion, or a left/right delete), tagged with the cursor that
     * produced it. `cursors_to_remove` is always empty today — given
     * {@link normalize}'s own invariant (no two cursors closer than one
     * character apart) and that every edit here is either a cursor's own
     * pre-existing selection or an at-most-one-character extension of a
     * collapsed cursor, two cursors' edits can never truly overlap yet.
     * It stays part of the contract for when a future edit intent (e.g.
     * auto-closing a bracket) can produce a real collision between
     * cursors, and needs one of them dropped.
     *
     * Purely computes what *should* happen — it doesn't touch the
     * cursors themselves. Call {@link apply_edit_results} with the
     * result once the edits have actually been applied to the real
     * buffer.
     */
    public TaggedTextEdit[] compute_edits (EditIntent intent, string typed_text, string text, out Cursor[] cursors_to_remove) {
        var chars = to_chars (text);
        var attempted = new GenericArray<TaggedTextEdit> ();

        for (uint i = 0; i < cursors.length; i++) {
            var cursor = cursors[i];
            int start;
            int end;
            string new_text;

            switch (intent) {
            case EditIntent.INSERT:
                if (!cursor.is_empty) {
                    start = cursor.selection_start;
                    end = cursor.selection_end;
                } else {
                    start = end = cursor.position_offset;
                }
                new_text = typed_text;
                break;
            case EditIntent.DELETE_LEFT:
                if (!cursor.is_empty) {
                    start = cursor.selection_start;
                    end = cursor.selection_end;
                } else if (cursor.position_offset > 0) {
                    start = cursor.position_offset - 1;
                    end = cursor.position_offset;
                } else {
                    continue; // nothing before the document start
                }
                new_text = "";
                break;
            case EditIntent.DELETE_RIGHT:
                if (!cursor.is_empty) {
                    start = cursor.selection_start;
                    end = cursor.selection_end;
                } else if (cursor.position_offset < chars.length) {
                    start = cursor.position_offset;
                    end = cursor.position_offset + 1;
                } else {
                    continue; // nothing after the document end
                }
                new_text = "";
                break;
            default:
                continue;
            }

            var edit = new TextEdit ();
            edit.start_offset = start;
            edit.end_offset = end;
            edit.old_text = chars_to_string (chars, start, end);
            edit.new_text = new_text;

            var tagged = new TaggedTextEdit ();
            tagged.edit = edit;
            tagged.cursor = cursor;
            attempted.add (tagged);
        }

        return finalize_edits (attempted, out cursors_to_remove);
    }

    /**
     * Enter, carrying the current line's own leading indentation forward
     * to the new line — VS Code's own "Keep" auto-indent strategy
     * (`EnterOperation._enter`, `cursorTypeEditOperations.ts`), the only
     * one of its several layered strategies this class can port: the
     * others (Indent/Outdent/IndentOutdent) key off real language
     * configuration — bracket pairs, onEnterRules — which GtkSourceView's
     * own `.lang` files don't carry (confirmed earlier this session:
     * syntax-highlighting metadata only, no indent/outdent rules).
     *
     * The carried-forward indentation is each cursor's own selection-
     * start line's leading whitespace, truncated to the start column
     * itself when the cursor sits inside that whitespace rather than
     * past it (so pressing Enter halfway through leading spaces doesn't
     * grow the indentation) — then re-normalized to `indent_size`/
     * `insert_spaces` (VS Code's own `normalizeIndentation`), so an
     * existing indentation that doesn't match the current settings
     * (leftover tabs in a spaces-configured file, say) still comes out
     * canonical on the new line. A cursor with a selection replaces it,
     * same as {@link compute_edits}'s own INSERT case.
     */
    public TaggedTextEdit[] compute_enter_edits (bool insert_spaces, int indent_size, string text, out Cursor[] cursors_to_remove) {
        var chars = to_chars (text);
        var attempted = new GenericArray<TaggedTextEdit> ();

        for (uint i = 0; i < cursors.length; i++) {
            var cursor = cursors[i];
            int start;
            int end;
            if (!cursor.is_empty) {
                start = cursor.selection_start;
                end = cursor.selection_end;
            } else {
                start = end = cursor.position_offset;
            }

            int ls = line_start (chars, start);
            int whitespace_end = ls;
            while (whitespace_end < chars.length && (chars[whitespace_end] == ' ' || chars[whitespace_end] == '\t')) {
                whitespace_end++;
            }
            int captured_end = int.min (start, whitespace_end);
            string indentation = normalize_indentation (chars, ls, captured_end, indent_size, insert_spaces);

            var edit = new TextEdit ();
            edit.start_offset = start;
            edit.end_offset = end;
            edit.old_text = chars_to_string (chars, start, end);
            edit.new_text = "\n" + indentation;

            var tagged = new TaggedTextEdit ();
            tagged.edit = edit;
            tagged.cursor = cursor;
            attempted.add (tagged);
        }

        return finalize_edits (attempted, out cursors_to_remove);
    }

    /**
     * Tab, honoring .editorconfig's `indent_style` — ported from VS
     * Code's own `_replaceJumpToNextIndent`
     * (`cursorTypeEditOperations.ts`). Only ever called once the caller
     * has already confirmed no cursor has a selection (block-indent isn't
     * implemented — see CursorController's own Tab handling).
     *
     * `insert_spaces` true inserts however many space characters reach
     * the *next* column that's a multiple of `indent_size` — not always a
     * flat `indent_size` spaces, just enough from wherever the cursor's
     * own line already puts it (a `\t` already in that prefix jumps to
     * the next multiple of `indent_size`, same as a real tab stop, any
     * other character advances by one). `insert_spaces` false inserts a
     * single literal tab character regardless of column, matching plain
     * typing.
     */
    public TaggedTextEdit[] compute_tab_edits (bool insert_spaces, int indent_size, string text, out Cursor[] cursors_to_remove) {
        var chars = to_chars (text);
        var attempted = new GenericArray<TaggedTextEdit> ();

        for (uint i = 0; i < cursors.length; i++) {
            var cursor = cursors[i];
            int offset = cursor.position_offset;

            string new_text;
            if (insert_spaces) {
                int column = visible_column (chars, line_start (chars, offset), offset, indent_size);
                int spaces_needed = indent_size - (column % indent_size);
                new_text = string.nfill (spaces_needed, ' ');
            } else {
                new_text = "\t";
            }

            var edit = new TextEdit ();
            edit.start_offset = offset;
            edit.end_offset = offset;
            edit.old_text = "";
            edit.new_text = new_text;

            var tagged = new TaggedTextEdit ();
            tagged.edit = edit;
            tagged.cursor = cursor;
            attempted.add (tagged);
        }

        return finalize_edits (attempted, out cursors_to_remove);
    }

    /**
     * Backspace, honoring .editorconfig's `indent_size` — ported from VS
     * Code's own `DeleteOperations.getDeleteLeftRange`
     * (`cursorDeleteOperations.ts`). A cursor with a selection deletes
     * that selection, same as {@link compute_edits}'s own DELETE_LEFT
     * case; a cursor already at the document start produces no edit
     * (`continue`), also unchanged. The only real difference: a collapsed
     * cursor sitting anywhere within its own line's leading whitespace
     * deletes back to the *previous* column that's a multiple of
     * `indent_size` — VS Code's own `prevIndentTabStop`, `max(0, column -
     * 1 - (column - 1) % indent_size)` — which can remove more than one
     * real character in a single press (or fewer than `indent_size`, if
     * the whitespace wasn't already stop-aligned to begin with). Outside
     * leading whitespace, still exactly one character, unchanged.
     */
    public TaggedTextEdit[] compute_backspace_edits (int indent_size, string text, out Cursor[] cursors_to_remove) {
        var chars = to_chars (text);
        var attempted = new GenericArray<TaggedTextEdit> ();

        for (uint i = 0; i < cursors.length; i++) {
            var cursor = cursors[i];
            int start;
            int end;

            if (!cursor.is_empty) {
                start = cursor.selection_start;
                end = cursor.selection_end;
            } else if (cursor.position_offset == 0) {
                continue; // nothing before the document start
            } else {
                int offset = cursor.position_offset;
                int ls = line_start (chars, offset);
                // `offset > ls` first: on an empty (or already-at-its-own-
                // start) line, ls == offset, and within_leading_whitespace
                // over that empty range is vacuously true — without this
                // guard the tab-stop math below computes target_column ==
                // column == 0, an empty start == end == offset delete
                // range, instead of falling through to the plain
                // one-character delete that actually removes the newline
                // and merges with the line above (VS Code's own real
                // guard for this, `position.column > 1`, is the same
                // check in 1-based terms).
                if (offset > ls && within_leading_whitespace (chars, ls, offset)) {
                    int column = visible_column (chars, ls, offset, indent_size);
                    int target_column = int.max (0, column - 1 - (column - 1) % indent_size);
                    start = ls + offset_for_visible_column (chars, ls, target_column, indent_size);
                    end = offset;
                } else {
                    start = offset - 1;
                    end = offset;
                }
            }

            var edit = new TextEdit ();
            edit.start_offset = start;
            edit.end_offset = end;
            edit.old_text = chars_to_string (chars, start, end);
            edit.new_text = "";

            var tagged = new TaggedTextEdit ();
            tagged.edit = edit;
            tagged.cursor = cursor;
            attempted.add (tagged);
        }

        return finalize_edits (attempted, out cursors_to_remove);
    }

    /**
     * Alt+Up/Alt+Down — moves every cursor's own touched lines (the
     * lines its selection spans, whole lines regardless of column) up or
     * down by swapping them with the adjacent line. Ported from VS
     * Code's own MoveLinesCommand (moveLinesCommand.ts), with its
     * language-configuration-aware indentation adjustment of the moved
     * block left out entirely — needs real bracket/onEnter rules Opus
     * has nowhere to source (same cut already made for
     * compute_enter_edits()).
     *
     * The core swap, per touched cursor:
     * - Moving down: delete from the end of the selection's last line
     *   through the end of the line right below it (removing the
     *   separating newline plus that line's own content), then insert
     *   that removed line's text + "\n" at the very start of the
     *   selection's first line.
     * - Moving up: mirrored — delete the line right above (its own
     *   content plus trailing newline), insert "\n" plus that text at
     *   the end of the selection's last line.
     *
     * Both are pure whole-line insert/delete around the selection, never
     * touching text *inside* it — this is what makes the selection's own
     * shape (both ends, whichever direction) survive intact: its offsets
     * just shift by the moved line's length (+1 newline), computed
     * directly rather than through any generic "track this selection
     * through the edit" machinery. GtkSourceView's own native move-lines
     * (what Alt+Up/Down fell through to before this) collapses the
     * selection to the whole moved line instead — the bug this fixes.
     *
     * `resulting_cursors` always has the same length/order as the live
     * cursor set: a cursor already at the buffer's own edge in the
     * requested direction comes back unchanged, not dropped — matches VS
     * Code, where each selection's own MoveLinesCommand instance no-ops
     * independently without blocking any other selection's own move. The
     * one case that *does* block everything: two cursors whose own
     * touched line ranges (their selected lines, plus the one line each
     * is about to swap into) collide — realistic here (Ctrl+D, Alt+Click
     * can land cursors on adjacent lines, unlike compute_edits()'s own
     * "always a full edit apart" assumption) — the whole call no-ops
     * rather than attempt an undefined partial move.
     */
    public TextEdit[] compute_move_lines_edits (bool down, string text, out Cursor[] resulting_cursors) {
        var chars = to_chars (text);
        int line_count = line_number_at (chars, chars.length) + 1;

        var start_lines = new int[cursors.length];
        var end_lines = new int[cursors.length];
        var effective_ends = new int[cursors.length];
        var movable = new bool[cursors.length];

        for (uint i = 0; i < cursors.length; i++) {
            var cursor = cursors[i];
            // A selection that merely touches the next line's own start
            // (Shift+Down after triple-click, say) doesn't count as
            // touching that line — VS Code's own endColumn === 1 check.
            // The *tracked* selection uses this adjusted end too, not the
            // raw one: same rule VS Code's own setEndPosition() applies
            // (its own comment: "we still honor that"), otherwise the
            // resulting cursor's own offset could land inside the
            // deleted "moving" line's own range entirely, past the end
            // of the buffer in the down+last-line case.
            int effective_end = cursor.selection_end;
            if (cursor.selection_end > cursor.selection_start && effective_end > 0 && chars[effective_end - 1] == NEWLINE) {
                effective_end -= 1;
            }
            effective_ends[i] = effective_end;

            start_lines[i] = line_number_at (chars, cursor.selection_start);
            end_lines[i] = line_number_at (chars, effective_end);
            movable[i] = down ? end_lines[i] < line_count - 1 : start_lines[i] > 0;
        }

        for (uint i = 0; i < cursors.length; i++) {
            if (!movable[i]) {
                continue;
            }
            int touched_start_i = down ? start_lines[i] : start_lines[i] - 1;
            int touched_end_i = down ? end_lines[i] + 1 : end_lines[i];
            for (uint j = i + 1; j < cursors.length; j++) {
                if (!movable[j]) {
                    continue;
                }
                int touched_start_j = down ? start_lines[j] : start_lines[j] - 1;
                int touched_end_j = down ? end_lines[j] + 1 : end_lines[j];
                if (touched_start_i <= touched_end_j && touched_start_j <= touched_end_i) {
                    var unchanged = new Cursor[cursors.length];
                    for (uint k = 0; k < cursors.length; k++) {
                        unchanged[k] = cursors[k];
                    }
                    resulting_cursors = unchanged;
                    return new TextEdit[0];
                }
            }
        }

        var edits = new GenericArray<TextEdit> ();
        var new_cursors = new Cursor[cursors.length];

        for (uint i = 0; i < cursors.length; i++) {
            var cursor = cursors[i];
            if (!movable[i]) {
                new_cursors[i] = cursor;
                continue;
            }

            int start_line_offset = find_line_start_offset (chars, start_lines[i]);
            int end_line_end_offset = line_end (chars, find_line_start_offset (chars, end_lines[i]));

            TextEdit delete_edit;
            TextEdit insert_edit;
            int shift;

            if (down) {
                int moving_line_start = find_line_start_offset (chars, end_lines[i] + 1);
                int moving_line_end = line_end (chars, moving_line_start);
                string moving_line_text = chars_to_string (chars, moving_line_start, moving_line_end);

                delete_edit = new TextEdit () {
                    start_offset = end_line_end_offset, end_offset = moving_line_end,
                    old_text = chars_to_string (chars, end_line_end_offset, moving_line_end), new_text = ""
                };
                insert_edit = new TextEdit () {
                    start_offset = start_line_offset, end_offset = start_line_offset,
                    old_text = "", new_text = moving_line_text + "\n"
                };
                shift = moving_line_text.char_count () + 1;
            } else {
                int moving_line_start = find_line_start_offset (chars, start_lines[i] - 1);
                string moving_line_text = chars_to_string (chars, moving_line_start, line_end (chars, moving_line_start));

                delete_edit = new TextEdit () {
                    start_offset = moving_line_start, end_offset = start_line_offset,
                    old_text = chars_to_string (chars, moving_line_start, start_line_offset), new_text = ""
                };
                insert_edit = new TextEdit () {
                    start_offset = end_line_end_offset, end_offset = end_line_end_offset,
                    old_text = "", new_text = "\n" + moving_line_text
                };
                shift = -(moving_line_text.char_count () + 1);
            }

            edits.add (delete_edit);
            edits.add (insert_edit);

            // Tracks [selection_start, effective_end] through the shift,
            // not the raw anchor/position — see effective_ends' own
            // comment above for why — preserving which of anchor/
            // position was which side (a reversed selection stays
            // reversed).
            int new_start = cursor.selection_start + shift;
            int new_end = effective_ends[i] + shift;
            bool anchor_was_end = cursor.anchor_offset > cursor.position_offset;

            var moved = cursor.clone ();
            moved.anchor_offset = anchor_was_end ? new_end : new_start;
            moved.position_offset = anchor_was_end ? new_start : new_end;
            new_cursors[i] = moved;
        }

        resulting_cursors = new_cursors;
        stable_sort_text_edits_by_start (edits);

        var result = new TextEdit[edits.length];
        for (uint k = 0; k < edits.length; k++) {
            result[k] = edits[k];
        }
        return result;
    }

    /**
     * Each cursor's own selected text (codepoint-exact, "" for a cursor
     * with no selection), in cursor order — Copy/Cut's own per-cursor
     * read half, mirroring {@link compute_edits}'s own per-cursor
     * INSERT-range logic. Kept alongside a piece count when writing to
     * the system clipboard so a later Paste can distribute one piece per
     * cursor when the counts still match — see {@link
     * compute_distributed_paste_edits}.
     */
    public string[] selected_texts (string text) {
        var chars = to_chars (text);
        var texts = new string[cursors.length];
        for (uint i = 0; i < cursors.length; i++) {
            var cursor = cursors[i];
            texts[i] = cursor.is_empty ? "" : chars_to_string (chars, cursor.selection_start, cursor.selection_end);
        }
        return texts;
    }

    /**
     * Like {@link compute_edits}'s own EditIntent.INSERT case, but
     * assigns a distinct replacement text per cursor (`texts[i]` for
     * `cursors[i]`) instead of one string shared by every cursor —
     * Paste's own per-cursor distribution, once `texts.length` is
     * confirmed to match the live cursor count by the caller (see
     * CursorController's own clipboard handling for when that applies:
     * VS Code's real `PasteOperation._distributePasteToCursors`,
     * `src/vs/editor/common/cursor/cursorTypeEditOperations.ts`, is the
     * verified reference this mirrors).
     */
    public TaggedTextEdit[] compute_distributed_paste_edits (string[] texts, string text, out Cursor[] cursors_to_remove) {
        assert (texts.length == cursors.length);

        var chars = to_chars (text);
        var attempted = new GenericArray<TaggedTextEdit> ();

        for (uint i = 0; i < cursors.length; i++) {
            var cursor = cursors[i];
            int start;
            int end;
            if (!cursor.is_empty) {
                start = cursor.selection_start;
                end = cursor.selection_end;
            } else {
                start = end = cursor.position_offset;
            }

            var edit = new TextEdit ();
            edit.start_offset = start;
            edit.end_offset = end;
            edit.old_text = chars_to_string (chars, start, end);
            edit.new_text = texts[i];

            var tagged = new TaggedTextEdit ();
            tagged.edit = edit;
            tagged.cursor = cursor;
            attempted.add (tagged);
        }

        return finalize_edits (attempted, out cursors_to_remove);
    }

    private TaggedTextEdit[] finalize_edits (GenericArray<TaggedTextEdit> attempted, out Cursor[] cursors_to_remove) {
        stable_sort_edits_by_start (attempted);

        // normalize() already keeps every pair of cursors at least one
        // character apart, and each edit above is either a cursor's own
        // pre-existing (already non-overlapping) selection or an
        // at-most-one-character extension of a collapsed cursor — so two
        // cursors' edits can at most touch here, never truly overlap,
        // and nothing needs to be dropped. `cursors_to_remove` stays
        // part of the contract for when a future edit intent (e.g.
        // auto-closing a bracket, or any other command that can produce
        // more than one edit per cursor) makes a real collision
        // possible, and needs this same resolution restored.
        cursors_to_remove = new Cursor[0];

        var result = new TaggedTextEdit[attempted.length];
        for (uint k = 0; k < attempted.length; k++) {
            result[k] = attempted[k];
        }
        return result;
    }

    /**
     * Repositions every surviving cursor after `edits` (from
     * {@link compute_edits}) have actually been applied to the real
     * buffer: a cursor that produced one of `edits` collapses to just
     * after its own replacement text; any other cursor shifts purely by
     * the combined length delta of every edit that landed before it — no
     * buffer read-back needed, since the edits already carry their own
     * old/new lengths. Cursors in `cursors_to_remove` are dropped
     * entirely, matching {@link compute_edits}'s collision resolution.
     */
    public void apply_edit_results (TaggedTextEdit[] edits, Cursor[] cursors_to_remove) {
        var delta_before_edit = new int[edits.length];
        int running = 0;
        for (int e = 0; e < edits.length; e++) {
            delta_before_edit[e] = running;
            running += edits[e].edit.new_text.char_count () - (edits[e].edit.end_offset - edits[e].edit.start_offset);
        }

        var survivors = new GenericArray<Cursor> ();
        Cursor? new_last_added = last_added_cursor;

        for (uint i = 0; i < cursors.length; i++) {
            var cursor = cursors[i];
            if (contains_cursor (cursors_to_remove, cursor)) {
                if (last_added_cursor == cursor) {
                    new_last_added = null;
                }
                continue;
            }

            int own_edit_index = -1;
            for (int e = 0; e < edits.length; e++) {
                if (edits[e].cursor == cursor) {
                    own_edit_index = e;
                    break;
                }
            }

            if (own_edit_index >= 0) {
                var tagged = edits[own_edit_index];
                int new_position = tagged.edit.start_offset + delta_before_edit[own_edit_index] + tagged.edit.new_text.char_count ();
                cursor.anchor_offset = new_position;
                cursor.position_offset = new_position;
                cursor.anchor_kind = CursorAnchorKind.CHARACTER;
            } else {
                int delta = 0;
                for (int e = 0; e < edits.length; e++) {
                    if (edits[e].edit.end_offset <= cursor.position_offset) {
                        delta += edits[e].edit.new_text.char_count () - (edits[e].edit.end_offset - edits[e].edit.start_offset);
                    }
                }
                cursor.anchor_offset += delta;
                cursor.position_offset += delta;
            }

            cursor.leftover_column = -1.0;
            survivors.add (cursor);
        }

        var arr = new Cursor[survivors.length];
        for (uint i = 0; i < survivors.length; i++) {
            arr[i] = survivors[i];
        }
        set_cursors (arr, new_last_added);
    }

    /**
     * Shifts every cursor by the combined length delta of `edits`
     * landing before it — Find/Replace's own version of
     * apply_edit_results(): none of `edits` are "produced" by any
     * cursor here (they come from search matches, not the live cursor
     * set), so every cursor always takes that method's own "an edit it
     * didn't produce" branch, never its "collapse onto my own edit"
     * one. Kept as its own small method rather than routing dummy,
     * never-matching TaggedTextEdits through apply_edit_results() just
     * to reach that one branch.
     */
    public void shift_for_external_edits (TextEdit[] edits) {
        for (uint i = 0; i < cursors.length; i++) {
            var cursor = cursors[i];
            int delta = 0;
            for (int e = 0; e < edits.length; e++) {
                if (edits[e].end_offset <= cursor.position_offset) {
                    delta += edits[e].new_text.char_count () - (edits[e].end_offset - edits[e].start_offset);
                }
            }
            cursor.anchor_offset += delta;
            cursor.position_offset += delta;
        }
    }

    /**
     * Sorts cursors by position and merges any that now touch (if either
     * is collapsed) or overlap (if both have a selection), then
     * re-establishes `cursors[0]` as the primary — the same pass runs
     * after every mutation above, so multi-cursor commands never need
     * their own separate merge logic. Original relative order among
     * survivors is preserved (not sorted order): a merge only ever
     * removes an entry, it doesn't reorder the rest.
     */
    private void normalize () {
        if (cursors.length <= 1) {
            return;
        }

        var sorted = new GenericArray<Cursor> ();
        for (uint i = 0; i < cursors.length; i++) {
            sorted.add (cursors[i]);
        }
        stable_sort_cursors_by_start (sorted);

        int i = 0;
        while (i < (int) sorted.length - 1) {
            var a = sorted[(uint) i];
            var b = sorted[(uint) (i + 1)];

            bool touches = (a.is_empty || b.is_empty)
                ? b.selection_start <= a.selection_end
                : b.selection_start < a.selection_end;

            if (!touches) {
                i++;
                continue;
            }

            bool b_wins = (b == last_added_cursor);
            var winner = b_wins ? b : a;
            var loser = b_wins ? a : b;

            int new_start = int.min (a.selection_start, b.selection_start);
            int new_end = int.max (a.selection_end, b.selection_end);
            bool forward = winner.position_offset >= winner.anchor_offset;
            winner.anchor_offset = forward ? new_start : new_end;
            winner.position_offset = forward ? new_end : new_start;

            if (last_added_cursor == loser) {
                last_added_cursor = winner;
            }

            if (loser == a) {
                sorted.remove_index ((uint) i);
                if (i > 0) {
                    i--;
                }
            } else {
                sorted.remove_index ((uint) (i + 1));
            }
        }

        var survivors = new GenericArray<Cursor> ();
        for (uint k = 0; k < cursors.length; k++) {
            if (contains_cursor_array (sorted, cursors[k])) {
                survivors.add (cursors[k]);
            }
        }
        cursors = survivors;

        if (last_added_cursor != null && !contains_cursor_array (cursors, last_added_cursor)) {
            last_added_cursor = null;
        }
    }

    private static Cursor move_one (Cursor cursor, CursorMoveOp op, bool extend, unichar[] chars) {
        var result = cursor.clone ();
        int new_position;
        double new_leftover = -1.0;

        switch (op) {
        case CursorMoveOp.LEFT:
            new_position = (!extend && !cursor.is_empty) ? cursor.selection_start : int.max (0, cursor.position_offset - 1);
            break;
        case CursorMoveOp.RIGHT:
            new_position = (!extend && !cursor.is_empty) ? cursor.selection_end : int.min (chars.length, cursor.position_offset + 1);
            break;
        case CursorMoveOp.HOME:
            new_position = line_start (chars, cursor.position_offset);
            break;
        case CursorMoveOp.END:
            new_position = line_end (chars, cursor.position_offset);
            break;
        case CursorMoveOp.DOCUMENT_START:
            new_position = 0;
            break;
        case CursorMoveOp.DOCUMENT_END:
            new_position = chars.length;
            break;
        case CursorMoveOp.WORD_LEFT:
            new_position = word_left (chars, cursor.position_offset);
            break;
        case CursorMoveOp.WORD_RIGHT:
            new_position = word_right (chars, cursor.position_offset);
            break;
        case CursorMoveOp.UP:
        case CursorMoveOp.DOWN:
            var vertical = move_vertical (chars, cursor.position_offset, cursor.leftover_column, op == CursorMoveOp.UP ? -1 : 1);
            new_position = vertical.offset;
            new_leftover = vertical.leftover_column;
            break;
        default:
            new_position = cursor.position_offset;
            break;
        }

        result.position_offset = new_position;
        result.leftover_column = new_leftover;

        if (!extend) {
            result.anchor_offset = new_position;
            result.anchor_kind = CursorAnchorKind.CHARACTER;
        }

        return result;
    }

    private struct VerticalMove {
        public int offset;
        public double leftover_column;
    }

    private static VerticalMove move_vertical (unichar[] chars, int position, double leftover_column, int direction) {
        int current_line_start = line_start (chars, position);
        double column = leftover_column >= 0 ? leftover_column : (position - current_line_start);

        if (direction < 0) {
            if (current_line_start == 0) {
                VerticalMove result = { 0, column };
                return result;
            }
            int target_line_start = line_start (chars, current_line_start - 1);
            int target_line_end = line_end (chars, target_line_start);
            int clamped = int.min ((int) column, target_line_end - target_line_start);
            VerticalMove result = { target_line_start + clamped, column };
            return result;
        }

        int current_line_end = line_end (chars, position);
        if (current_line_end == chars.length) {
            VerticalMove result = { chars.length, column };
            return result;
        }
        int next_line_start = current_line_end + 1;
        int next_line_end = line_end (chars, next_line_start);
        int clamped_down = int.min ((int) column, next_line_end - next_line_start);
        VerticalMove down_result = { next_line_start + clamped_down, column };
        return down_result;
    }

    private static int line_start (unichar[] chars, int offset) {
        int i = offset;
        while (i > 0 && chars[i - 1] != NEWLINE) {
            i--;
        }
        return i;
    }

    /** Ported from VS Code's own `CursorColumns.visibleColumnFromColumn`: walks `chars[from:to]`, a `\t` jumps to the next multiple of `indent_size`, anything else advances by one. */
    private static int visible_column (unichar[] chars, int from, int to, int indent_size) {
        int column = 0;
        for (int i = from; i < to; i++) {
            if (chars[i] == '\t') {
                column = column - column % indent_size + indent_size;
            } else {
                column++;
            }
        }
        return column;
    }

    /** The inverse of {@link visible_column}, ported from `CursorColumns.columnFromVisibleColumn`: how many characters from `from` reach a visible column `>= target_column` — every character in that span must already be space/tab (only ever called within a line's own leading whitespace). Relative to `from`, not an absolute offset. */
    private static int offset_for_visible_column (unichar[] chars, int from, int target_column, int indent_size) {
        int column = 0;
        int i = from;
        while (column < target_column) {
            if (chars[i] == '\t') {
                column = column - column % indent_size + indent_size;
            } else {
                column++;
            }
            i++;
        }
        return i - from;
    }

    /** Whether every character from `line_start_offset` up to (not including) `offset` is a space or tab — Backspace's own "am I still inside the leading whitespace" check. */
    private static bool within_leading_whitespace (unichar[] chars, int line_start_offset, int offset) {
        for (int i = line_start_offset; i < offset; i++) {
            if (chars[i] != ' ' && chars[i] != '\t') {
                return false;
            }
        }
        return true;
    }

    /** Re-expresses a whitespace-only run (`chars[from:to]`) using `indent_size`/`insert_spaces` — same visible width (via {@link visible_column}), canonical characters: all spaces when `insert_spaces`, otherwise as many whole `indent_size`-wide tabs as fit plus leftover spaces. Ported from VS Code's own `normalizeIndentation` (`core/misc/indentation.ts`). */
    private static string normalize_indentation (unichar[] chars, int from, int to, int indent_size, bool insert_spaces) {
        int width = visible_column (chars, from, to, indent_size);
        if (insert_spaces) {
            return string.nfill (width, ' ');
        }
        return string.nfill (width / indent_size, '\t') + string.nfill (width % indent_size, ' ');
    }

    private static int line_end (unichar[] chars, int offset) {
        int i = offset;
        while (i < chars.length && chars[i] != NEWLINE) {
            i++;
        }
        return i;
    }

    private static int line_number_at (unichar[] chars, int offset) {
        int line = 0;
        for (int i = 0; i < offset && i < chars.length; i++) {
            if (chars[i] == NEWLINE) {
                line++;
            }
        }
        return line;
    }

    private static int find_line_start_offset (unichar[] chars, int line_number) {
        if (line_number == 0) {
            return 0;
        }

        int line = 0;
        for (int i = 0; i < chars.length; i++) {
            if (chars[i] == NEWLINE) {
                line++;
                if (line == line_number) {
                    return i + 1;
                }
            }
        }
        return chars.length;
    }

    private static bool is_word_char (unichar c) {
        return c.isalnum () || c == '_';
    }

    private static int word_left (unichar[] chars, int offset) {
        int i = offset;
        while (i > 0 && chars[i - 1].isspace ()) {
            i--;
        }
        if (i > 0) {
            bool word_group = is_word_char (chars[i - 1]);
            while (i > 0 && !chars[i - 1].isspace () && is_word_char (chars[i - 1]) == word_group) {
                i--;
            }
        }
        return i;
    }

    private static int word_right (unichar[] chars, int offset) {
        int i = offset;
        int n = chars.length;
        while (i < n && chars[i].isspace ()) {
            i++;
        }
        if (i < n) {
            bool word_group = is_word_char (chars[i]);
            while (i < n && !chars[i].isspace () && is_word_char (chars[i]) == word_group) {
                i++;
            }
        }
        return i;
    }

    // The word touching `offset` (from either side) — distinct from
    // word_left/word_right, which *jump* to the next boundary rather than
    // report the boundaries of the word already under the caret.
    private static int word_char_probe (unichar[] chars, int offset) {
        if (offset < chars.length && is_word_char (chars[offset])) {
            return offset;
        }
        if (offset > 0 && is_word_char (chars[offset - 1])) {
            return offset - 1;
        }
        return -1;
    }

    private static int find_word_boundary_start (unichar[] chars, int offset) {
        int probe = word_char_probe (chars, offset);
        if (probe < 0) {
            return offset;
        }
        int i = probe;
        while (i > 0 && is_word_char (chars[i - 1])) {
            i--;
        }
        return i;
    }

    private static int find_word_boundary_end (unichar[] chars, int offset) {
        int probe = word_char_probe (chars, offset);
        if (probe < 0) {
            return offset;
        }
        int i = probe + 1;
        while (i < chars.length && is_word_char (chars[i])) {
            i++;
        }
        return i;
    }

    // Naive forward substring search over codepoints, starting at `from`.
    // O(n*m) — acceptable for a model-layer correctness-first
    // implementation; worth revisiting if it shows up in profiling on a
    // large file.
    private static int find_next (unichar[] chars, string needle, int from) {
        var needle_chars = to_chars (needle);
        int m = needle_chars.length;
        if (m == 0) {
            return -1;
        }

        int n = chars.length;
        for (int start = from; start + m <= n; start++) {
            bool match = true;
            for (int j = 0; j < m; j++) {
                if (chars[start + j] != needle_chars[j]) {
                    match = false;
                    break;
                }
            }
            if (match) {
                return start;
            }
        }
        return -1;
    }

    private static unichar[] to_chars (string text) {
        int n = text.char_count ();
        var result = new unichar[n];
        unowned string iter = text;
        for (int i = 0; i < n; i++) {
            result[i] = iter.get_char ();
            iter = iter.next_char ();
        }
        return result;
    }

    private static string chars_to_string (unichar[] chars, int start, int end) {
        var builder = new StringBuilder ();
        for (int i = start; i < end; i++) {
            builder.append_unichar (chars[i]);
        }
        return builder.str;
    }

    private static bool contains_cursor (Cursor[] array, Cursor cursor) {
        foreach (var candidate in array) {
            if (candidate == cursor) {
                return true;
            }
        }
        return false;
    }

    private static bool contains_cursor_array (GenericArray<Cursor> array, Cursor cursor) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == cursor) {
                return true;
            }
        }
        return false;
    }

    private static void stable_sort_cursors_by_start (GenericArray<Cursor> items) {
        for (uint i = 1; i < items.length; i++) {
            var key = items[i];
            int j = (int) i - 1;
            while (j >= 0 && items[(uint) j].selection_start > key.selection_start) {
                items[(uint) (j + 1)] = items[(uint) j];
                j--;
            }
            items[(uint) (j + 1)] = key;
        }
    }

    private static void stable_sort_edits_by_start (GenericArray<TaggedTextEdit> items) {
        for (uint i = 1; i < items.length; i++) {
            var key = items[i];
            int j = (int) i - 1;
            while (j >= 0 && items[(uint) j].edit.start_offset > key.edit.start_offset) {
                items[(uint) (j + 1)] = items[(uint) j];
                j--;
            }
            items[(uint) (j + 1)] = key;
        }
    }

    /** Same as {@link stable_sort_edits_by_start}, for plain TextEdit[] (compute_move_lines_edits()'s own return, not tagged to any cursor). */
    private static void stable_sort_text_edits_by_start (GenericArray<TextEdit> items) {
        for (uint i = 1; i < items.length; i++) {
            var key = items[i];
            int j = (int) i - 1;
            while (j >= 0 && items[(uint) j].start_offset > key.start_offset) {
                items[(uint) (j + 1)] = items[(uint) j];
                j--;
            }
            items[(uint) (j + 1)] = key;
        }
    }
}
