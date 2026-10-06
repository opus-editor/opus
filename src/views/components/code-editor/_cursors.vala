/**
* CodeEditor's cursor state and editing transactions: the one place the
* buffer, the bound CursorCollection, and the bound EditHistory are kept
* consistent with each other. Every command below is one of two kinds —
* a navigation/multi-cursor command that only moves cursors, or an edit
* that goes through execute_edit(), the single path that mutates the
* buffer and records history (Monaco's own Cursor._executeEdit, checked
* in common/cursor/cursor.ts). Also keeps the cursor set in sync with
* native GTK actions this component doesn't claim itself (double-click,
* Ctrl+A, any unclaimed binding) — see on_mark_set().
*
* Knows nothing about keys or the mouse: CodeEditorInput (_input.vala)
* translates those into calls here, and CodeEditorClipboard
* (_clipboard.vala) owns the system clipboard round-trip. That split is
* what makes read-only a one-line matter — execute_edit() refuses, and
* the input side just stops offering.
*
* Plural, matching VS Code's own real ViewCursors (checked its source,
* browser/viewParts/viewCursors/): the manager for however many cursors
* currently exist, not one instance per cursor. There's no singular
* counterpart here the way VS Code has ViewCursor: that split is about
* each DOM node needing its own on-screen position computed; GTK's shared
* canvas draw has nothing per-cursor left over to be its own object once
* render_cursors()'s loop already does that math.
*/
public class CodeEditorCursors : Object {
  private delegate void CursorCommand ();
  private delegate void CursorReposition ();

  private CodeEditorSourceView text_view;
  private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }

  /** The live cursor set — see bind(). Never null: a fresh one is bound at construction, so nothing here ever has to ask "is there a document". */
  public CursorCollection cursors { get; private set; }

  /** The undo/redo stack every edit here lands in — see bind(). Never null, same as `cursors`. */
  public EditHistory history { get; private set; }

  /**
   * Set by CodeEditorInput on a plain single primary press, so
   * on_mark_set() keeps whatever direction that click (or the
   * drag-select following it) leaves the native marks in, instead of
   * normalizing to caret >= anchor. Input resets it on every key press,
   * claimed or not — a stale true must never leak into a later,
   * unrelated native mark change (e.g. a native Ctrl+A).
   */
  public bool keep_native_direction { get; set; default = false; }

  private int indent_size = 4;
  private bool insert_spaces = false;

  private IndentChangeFunc? indent_change;
  private OutdentChangeFunc? outdent_change;

  /** Tracks edits GtkSourceView itself makes to the buffer unclaimed by this class (block-indent/outdent over a selection) — see its own doc comment. Also where updating_programmatically actually lives now: the one flag both this class and that one need, toggled here around every buffer write this class makes itself. */
  private CodeEditorNativeEdits native_edits;

  /** Suppresses on_mark_set while render_cursors()'s own select_range() call is moving the marks — otherwise that would resync straight back from what render_cursors() was just asked to show. */
  private bool setting_cursors_programmatically = false;

  // See typing_kind() — the only way to tell a first space in a run
  // apart from a consecutive one, since that depends on what came
  // immediately before it. Every command other than type_char() resets
  // it, so a space typed right after one is always a "first" space.
  private bool previous_typed_was_space = false;

  /** reveal_cursors()'s deferred follow-up pass, already queued and not yet run — see that method's own doc comment. 0 means none pending. */
  private uint pending_reveal_id = 0;

  /** See CodeEditor.close(). */
  public void close () {
    if (pending_reveal_id != 0) {
      Source.remove (pending_reveal_id);
      pending_reveal_id = 0;
    }
  }

  /** The buffer's full content just changed via apply_edits() — bubbles up through CodeEditor so whoever owns the document can mark it dirty. */
  public signal void text_changed (string new_text);

  public CodeEditorCursors (CodeEditorSourceView text_view) {
    this.text_view = text_view;
    native_edits = new CodeEditorNativeEdits (text_view);
    native_edits.text_changed.connect ((text) => text_changed (text));
    unbind ();

    // Off in favor of the EditHistory-backed pipeline below — the
    // two would otherwise compete for the same Ctrl+Z.
    source_buffer.enable_undo = false;

    source_buffer.mark_set.connect (on_mark_set);
    // _after: runs once the mutation has actually landed, to resync the
    // tracked cursor — see resync_native_cursor_after_native_edit()'s
    // own doc comment. native_edits connects its own plain (pre-mutation)
    // handlers to these same two signals independently.
    source_buffer.insert_text.connect_after ((ref pos, new_text, len) => resync_native_cursor_after_native_edit ());
    source_buffer.delete_range.connect_after ((start, end) => resync_native_cursor_after_native_edit ());
  }

  /** Swaps in the cursor set and undo stack this editor works on — EditorView.EditorPane.TabDocument hands over its Document's own pair once, when it builds its editor. Renders `cursors` right away. Cancels any still-pending reveal_cursors(), which would otherwise scroll the buffer to a cursor of the pair just replaced. */
  public void bind (CursorCollection cursors, EditHistory history) {
    cancel_pending_reveal ();
    this.cursors = cursors;
    this.history = history;
    native_edits.bind (cursors, history);
    render ();
  }

  /** Back to a fresh, throwaway pair — what a consumer with no per-tab state to preserve (Find Results) stays on for good, and what EditorView.EditorPane.TabDocument binds while no document is showing. */
  public void unbind () {
    bind (new CursorCollection (), new EditHistory ());
  }

  /**
   * Replaces the buffer's whole content — CodeEditor's own set_text()
   * calls this instead of writing text_view.buffer directly: without
   * suppressing native_edits, it would misread loading a brand-new
   * document as an untracked user edit and push it onto EditHistory.
   * Deliberately not an edit: it's how a read-only editor gets its
   * content too.
   */
  public void load_text (string text) {
    cancel_pending_reveal ();
    native_edits.updating_programmatically = true;
    text_view.buffer.text = text;
    native_edits.updating_programmatically = false;
  }

  private void cancel_pending_reveal () {
    if (pending_reveal_id != 0) {
      Source.remove (pending_reveal_id);
      pending_reveal_id = 0;
    }
  }

  /** Columns per indent level, and whether Tab inserts that many spaces instead of a literal tab character — a "prop" this component can't derive on its own (comes from the linked folder's .editorconfig, out of scope here). */
  public void set_indent_config (int indent_size, bool insert_spaces) {
    this.indent_size = indent_size;
    this.insert_spaces = insert_spaces;
  }

  // ---- Navigation and multi-cursor commands — never touch the buffer. ----

  /** Left/Right, word jumps, document start/end — `extend` is whether the selection grows (Shift) or collapses to the new position. */
  public void move (CursorMoveOp op, bool extend) {
    apply_cursor_command (() => cursors.move (op, extend, get_text ()));
  }

  /** Up/Down/Home/End — by display row: `text_view` is the IDisplayRows, so under word wrap a wrapped line's own rows count, and with it off GTK's display lines are the paragraphs anyway. `indent_size` doubles as the tab width, the same value `set_indent_size()` gives GTK to render a `\t` with. */
  public void move_by_row (RowMoveOp op, bool extend) {
    apply_cursor_command (() => cursors.move_by_row (op, extend, get_text (), text_view, indent_size));
  }

  public void add_cursor_above () {
    apply_cursor_command (() => cursors.add_cursor_above (get_text (), indent_size));
  }

  public void add_cursor_below () {
    apply_cursor_command (() => cursors.add_cursor_below (get_text (), indent_size));
  }

  /** Ctrl+D — see CursorCollection.add_cursor_at_next_match(). */
  public void add_cursor_at_next_match () {
    apply_cursor_command (() => cursors.add_cursor_at_next_match (get_text ()));
  }

  /** Selects every occurrence of whatever the primary cursor currently has selected — Ctrl+Shift+L, and EditorView.FindBar's own Alt+Return ("Select All Occurrences", matching VS Code) once the live match has already been handed to the real selection (see CodeEditor.select_last_match()). A no-op if the primary selection is empty. */
  public void select_all_occurrences () {
    apply_cursor_command (() => cursors.select_all_occurrences (get_text ()));
  }

  /** Alt+click on empty space — a new collapsed cursor at `offset`. */
  public void add_cursor_at (int offset) {
    apply_cursor_command (() => cursors.add_cursor_at_click (offset));
  }

  /** Alt+drag continuing past the click that added a cursor — extends that same cursor's selection to `offset`. */
  public void extend_last_added_cursor (int offset) {
    apply_cursor_command (() => cursors.extend_last_added_cursor (offset));
  }

  /** Alt+double-click — the just-added cursor grows to the word under it. */
  public void expand_last_added_cursor_to_word () {
    apply_cursor_command (() => cursors.expand_last_added_cursor_to_word (get_text ()));
  }

  /** Alt+triple-click — the just-added cursor grows to its whole line. */
  public void expand_last_added_cursor_to_line () {
    apply_cursor_command (() => cursors.expand_last_added_cursor_to_line (get_text ()));
  }

  /** Shift+Alt+click/drag — one cursor per line between the two offsets, each selecting the same column range. */
  public void box_select (int anchor_offset, int focus_offset) {
    apply_cursor_command (() => cursors.box_select (anchor_offset, focus_offset, get_text ()));
  }

  /** Escape: drops every secondary cursor first, then (on a later press) the primary's own selection. False if there was nothing to collapse, so the key can fall through to GTK. */
  public bool collapse () {
    if (cursors.count > 1) {
      apply_cursor_command (() => {
        var primary = cursors.primary.clone ();
        cursors.set_cursors ({ primary });
      });
      return true;
    }
    if (!cursors.primary.is_empty) {
      apply_cursor_command (() => {
        var primary = cursors.primary.clone ();
        primary.anchor_offset = primary.position_offset;
        cursors.set_cursors ({ primary });
      });
      return true;
    }
    return false;
  }

  /** A click is an undo-stop boundary: whatever typing run was open ends here, even though the click itself moves nothing this class tracks (GTK's own native handling does that, resynced via on_mark_set()). */
  public void close_history_entry () {
    previous_typed_was_space = false;
    history.close_current_entry ();
  }

  /** Each cursor's own selected text, in cursor order ("" for a collapsed one) — Copy/Cut's read half. */
  public string[] selected_texts () {
    return cursors.selected_texts (get_text ());
  }

  // ---- Edits — every one goes through execute_edit(). ----

  /** One typed character, honoring Session.insert_mode (overtype) — the only command that keeps the space-run bookkeeping typing_kind() needs for undo coalescing. */
  public void type_char (unichar ch) {
    var intent = Session.get_default ().insert_mode ? EditIntent.OVERTYPE : EditIntent.INSERT;
    var kind = typing_kind (ch);
    apply_edit (intent, ch.to_string (), kind);
    if (!ch.isspace ()) {
      outdent_lines_just_closed (kind);
    }
  }

  /**
   * A line that the character just typed made start with something
   * closing a block — the `d` of `end`, a `}` — is pulled out to where
   * that belongs. Recorded under the keystroke's own `kind`, so the
   * two coalesce into one history step: one undo takes back the
   * character and the indentation together.
   */
  private void outdent_lines_just_closed (EditKind kind) {
    if (outdent_change == null) {
      return;
    }
    var edits = cursors.compute_outdent_edits (insert_spaces, indent_size, get_text (), outdent_change);
    execute_edit (edits, kind, () => cursors.shift_for_external_edits (edits));
  }

  /** What knows the language being edited: how far in a new line goes, and when a line just closed a block. Both null until set, and Enter and typing then behave as if no language were known. */
  public void set_indentation (owned IndentChangeFunc? indent_change, owned OutdentChangeFunc? outdent_change) {
    this.indent_change = (owned) indent_change;
    this.outdent_change = (owned) outdent_change;
  }

  /** A plain paste — the same text at every cursor, as one non-coalescing step. */
  public void insert_text (string text) {
    previous_typed_was_space = false;
    var intent = Session.get_default ().insert_mode ? EditIntent.OVERTYPE : EditIntent.INSERT;
    apply_edit (intent, text, EditKind.OTHER);
  }

  /** A distributed paste — `texts[i]` lands at cursor `i`; the caller has already matched the counts (see CodeEditorClipboard). */
  public void paste_pieces (string[] texts) {
    previous_typed_was_space = false;
    bool overtype = Session.get_default ().insert_mode;
    Cursor[] cursors_to_remove;
    var tagged_edits = cursors.compute_distributed_paste_edits (texts, overtype, get_text (), out cursors_to_remove);
    apply_tagged_edits (tagged_edits, cursors_to_remove, EditKind.OTHER);
  }

  /** Cut's delete half — removes every cursor's selection, leaving the cursors collapsed where each selection began. */
  public void delete_selections () {
    previous_typed_was_space = false;
    apply_edit (EditIntent.INSERT, "", EditKind.OTHER);
  }

  public void delete_right () {
    previous_typed_was_space = false;
    apply_edit (EditIntent.DELETE_RIGHT, "", EditKind.DELETING_RIGHT);
  }

  public void backspace () {
    previous_typed_was_space = false;
    Cursor[] cursors_to_remove;
    var tagged_edits = cursors.compute_backspace_edits (indent_size, get_text (), out cursors_to_remove);
    apply_tagged_edits (tagged_edits, cursors_to_remove, EditKind.DELETING_LEFT);
  }

  public void enter () {
    previous_typed_was_space = false;
    Cursor[] cursors_to_remove;
    var tagged_edits = cursors.compute_enter_edits (insert_spaces, indent_size, get_text (), out cursors_to_remove, indent_change);
    apply_tagged_edits (tagged_edits, cursors_to_remove, EditKind.OTHER);
  }

  /** Tab with no selection anywhere — the caller leaves a Tab with a selection to GtkSourceView's own native block-indent instead. */
  public void tab () {
    previous_typed_was_space = false;
    Cursor[] cursors_to_remove;
    var tagged_edits = cursors.compute_tab_edits (insert_spaces, indent_size, get_text (), out cursors_to_remove);
    apply_tagged_edits (tagged_edits, cursors_to_remove, EditKind.OTHER);
  }

  /** Alt+Up/Down — see CursorCollection.compute_move_lines_edits(). */
  public void move_lines (bool down) {
    previous_typed_was_space = false;
    Cursor[] resulting_cursors;
    var edits = cursors.compute_move_lines_edits (down, get_text (), out resulting_cursors);
    execute_edit (edits, EditKind.OTHER, () => cursors.set_cursors (resulting_cursors));
  }

  public void undo () {
    apply_history_step (false);
  }

  public void redo () {
    apply_history_step (true);
  }

  /** Applies `edits` as one atomic, non-coalescing history step not produced by any live cursor (Replace/Replace All results) — every cursor shifts to stay at its own logical position instead of being collapsed onto any of `edits`. */
  public void apply_external_edit (TextEdit[] edits) {
    previous_typed_was_space = false;
    execute_edit (edits, EditKind.OTHER, () => cursors.shift_for_external_edits (edits));
  }

  /**
   * A dragged selection landed at `drop_offset` — cut from where it was,
   * pasted where it dropped, as one history step, with the moved text
   * selected afterwards. A no-op if dropped back inside (or at either
   * edge of) its own original range. Lives here rather than in
   * CodeEditorDragSelection, which has no reference to the cursor set or
   * history.
   */
  public void move_selection (SelectionSnapshot snapshot, int drop_offset) {
    int source_start = snapshot.start_offset;
    int source_end = snapshot.end_offset;
    string text = snapshot.text;
    if (drop_offset >= source_start && drop_offset <= source_end) {
      return;
    }

    close_history_entry ();

    var delete_edit = new TextEdit () {
      start_offset = source_start, end_offset = source_end, old_text = text, new_text = ""
    };
    var insert_edit = new TextEdit () {
      start_offset = drop_offset, end_offset = drop_offset, old_text = "", new_text = text
    };
    // Ascending, as EditHistory expects — apply_edits() sorts its own
    // copy highest-offset-first, so the same array serves both.
    TextEdit[] edits = source_start < drop_offset
      ? new TextEdit[] { delete_edit, insert_edit }
      : new TextEdit[] { insert_edit, delete_edit };

    int landed_start = drop_offset > source_end ? drop_offset - (source_end - source_start) : drop_offset;
    var landed = new Cursor (landed_start);
    landed.position_offset = landed_start + text.char_count (); // anchor at the start, caret at the end

    execute_edit (edits, EditKind.OTHER, () => cursors.set_cursors ({ landed }));
  }

  // ---- The transaction layer. ----

  private string get_text () {
    return text_view.buffer.text;
  }

  private void apply_cursor_command (CursorCommand command) {
    previous_typed_was_space = false;
    command ();
    history.close_current_entry ();
    render ();
    reveal_cursors ();
  }

  private void apply_edit (EditIntent intent, string typed_text, EditKind kind) {
    Cursor[] cursors_to_remove;
    var tagged_edits = cursors.compute_edits (intent, typed_text, get_text (), out cursors_to_remove);
    apply_tagged_edits (tagged_edits, cursors_to_remove, kind);
  }

  private void apply_tagged_edits (TaggedTextEdit[] tagged_edits, Cursor[] cursors_to_remove, EditKind kind) {
    var edits = new TextEdit[tagged_edits.length];
    for (int i = 0; i < tagged_edits.length; i++) {
      edits[i] = tagged_edits[i].edit;
    }
    execute_edit (edits, kind, () => cursors.apply_edit_results (tagged_edits, cursors_to_remove));
  }

  /**
   * The one path every history-producing buffer mutation takes: snapshot
   * the cursors, write the buffer, let `reposition` move the cursors to
   * where the edit leaves them, record the step, repaint. Callers pass
   * `edits` ascending by start_offset — what EditHistory's own
   * invert_batch() expects.
   *
   * Refuses outright on a non-editable view (CodeEditor.read_only) —
   * before the snapshot, so nothing about cursors or history moves for
   * an edit that never lands. GtkTextView's `editable` is the single
   * source of truth here, the same flag that makes GTK refuse its own
   * native writes (IM composition, middle-click paste, unclaimed
   * bindings), which never come through this method at all.
   */
  private void execute_edit (TextEdit[] edits, EditKind kind, CursorReposition reposition) {
    if (!text_view.editable || edits.length == 0) {
      return;
    }

    var before_cursors = cursors.snapshot ();
    apply_edits (edits);
    reposition ();
    history.push (edits, before_cursors, cursors.snapshot (), kind);
    render ();
    reveal_cursors ();
  }

  /** Pops one entry and replays it — its own path, not execute_edit()'s: nothing new gets pushed, and the entry's own recorded cursors are restored rather than recomputed. Same read-only refusal, and for the same reason: a refused replay must not pop. */
  private void apply_history_step (bool redo) {
    if (!text_view.editable) {
      return;
    }
    previous_typed_was_space = false;

    var entry = redo ? history.redo () : history.undo ();
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
    cursors.set_cursors (cloned);

    render ();
    reveal_cursors ();
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
    native_edits.updating_programmatically = true;
    foreach (var edit in sorted) {
      Gtk.TextIter start_iter;
      Gtk.TextIter end_iter;
      source_buffer.get_iter_at_offset (out start_iter, edit.start_offset);
      source_buffer.get_iter_at_offset (out end_iter, edit.end_offset);
      source_buffer.delete (ref start_iter, ref end_iter);
      source_buffer.insert (ref start_iter, edit.new_text, -1);
    }
    native_edits.updating_programmatically = false;
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

  // ---- Native sync — GTK moved the marks or wrote the buffer on its own. ----

  /**
   * The real insert/selection_bound marks moved for a reason this class
   * didn't itself drive (a native double/triple-click's word/line-select,
   * Ctrl+A, or any other native keybinding left unclaimed) — resyncs the
   * Model's own primary cursor to match and repaints, since the native
   * caret is never actually painted (only its marks move). Also fires
   * (harmlessly) right after render_cursors() sets those same marks
   * itself — suppressed via setting_cursors_programmatically above.
   *
   * keep_native_direction (set by CodeEditorInput's own press handler)
   * is the only case with a real "direction" worth keeping as-is — a
   * plain click, or the drag-select that can follow it. Every other
   * unclaimed native action has no such direction, so this normalizes to
   * caret >= anchor instead, regardless of which of GTK's own insert/
   * selection_bound its internal implementation happens to place where.
   */
  private void on_mark_set (Gtk.TextIter location, Gtk.TextMark mark) {
    if (setting_cursors_programmatically) {
      return;
    }
    if (mark.name != "insert" && mark.name != "selection_bound") {
      return;
    }

    int anchor = get_anchor_offset ();
    int position = get_position_offset ();

    if (keep_native_direction) {
      resync_from_native (anchor, position);
    } else {
      resync_from_native (int.min (anchor, position), int.max (anchor, position));
    }
  }

  /** Re-syncs from *after* an untracked native edit has actually landed — mark-set doesn't reliably fire for this case. Always normalized: a native edit (e.g. GtkSourceView's own Tab-indent) has no click-drag direction to preserve. */
  private void resync_native_cursor_after_native_edit () {
    if (native_edits.updating_programmatically) {
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
    cursors.set_cursors ({ cursor });
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

  // ---- Render. ----

  private void render () {
    render_cursors (cursors.snapshot ());
  }

  /** Paints `cursor_set` as the carets/selections shown, and mirrors its primary onto the real insert/selection_bound marks (so copy/IM keep working — scrolling to keep it visible is reveal_cursors()'s own, separate job, deliberately not done here, see that method's own doc comment) — public because EditorView.EditorPane.TabDocument's own SetActiveCursors (Opus.Dev.DevServer) mutates the bound CursorCollection directly and then calls this to make it visible. */
  public void render_cursors (Cursor[] cursor_set) {
    assert (cursor_set.length > 0);

    setting_cursors_programmatically = true;
    var primary = cursor_set[0];
    Gtk.TextIter primary_position;
    Gtk.TextIter primary_anchor;
    source_buffer.get_iter_at_offset (out primary_position, primary.position_offset);
    source_buffer.get_iter_at_offset (out primary_anchor, primary.anchor_offset);
    source_buffer.select_range (primary_position, primary_anchor);
    setting_cursors_programmatically = false;

    var caret_offsets = new int[cursor_set.length];
    for (int i = 0; i < cursor_set.length; i++) {
      caret_offsets[i] = cursor_set[i].position_offset;
    }

    text_view.set_carets (caret_offsets);
    text_view.set_selections (cursor_set);
    text_view.reset_blink ();
  }

  /**
   * Scrolls the viewport to keep the current cursor set visible — called
   * after every command that moves the cursor or edits the buffer
   * (apply_cursor_command()/execute_edit()/apply_history_step()), the
   * exact three sites VS Code's own `_executeEdit`/`_runCursorMove`
   * reveal from (cursor.ts/coreCommands.ts). Never from render() itself:
   * that's also reached by bind() (binding a document, which deliberately
   * does not reveal — the tab's own scroll is restored separately) and by
   * resync_from_native() (a native GTK action — double-click, Ctrl+A,
   * drag-select — already scrolled for itself before this would run; see
   * CodeEditorSourceView's own doc comment for exactly which bindings
   * that covers).
   *
   * Synchronous, right here in the command, not deferred to an idle —
   * the same place GTK's own native handlers call scroll_mark_onscreen().
   * GDK dispatches queued input events *inside* the frame clock's own
   * paint dispatch (gdk_frame_clock_paint_idle(): FLUSH_EVENTS →
   * LAYOUT → PAINT in one go, checked in gdkframeclockidle.c/
   * gdksurface.c), so an idle queued from a key handler — at any
   * priority — runs only after that frame has painted, while
   * GtkTextView paints the edit itself in that same frame (it flushes
   * its own validation synchronously from size_allocate()/draw_text()):
   * the edit shows unscrolled, the scroll lands a frame later, and
   * Enter at the bottom edge visibly jumps twice. A synchronous reveal
   * is exact for every one-row edit or move — see reveal_settled()'s
   * own doc comment for why, and for what the deferred follow-up below
   * is for: a far target (a long paste, an undo across screens) can
   * only be revealed exactly once GTK's incremental validation has
   * measured the rows in between, which it does at a priority above
   * the default idle's, so one coalesced default-idle pass runs the
   * same settle again then — a no-op in the common case, the
   * correction in the rare one.
   */
  private void reveal_cursors () {
    reveal_cursor_extremes ();

    if (pending_reveal_id != 0) {
      return;
    }
    pending_reveal_id = Idle.add (() => {
      pending_reveal_id = 0;
      reveal_cursor_extremes ();
      return Source.REMOVE;
    });
  }

  /**
   * One cursor reveals its own position. Several reveal from the
   * topmost to the bottommost caret — ported from VS Code's own choice
   * (`cursor.ts`'s `getViewPositions`, `viewLines.ts`'s own "reveal
   * every cursor" path) — simplified to the two extremes rather than a
   * true multi-rectangle reveal: revealing each extreme in turn already
   * does the one thing that actually needs it (`add_cursor_above`/
   * `add_cursor_below` adding a cursor right at the viewport's edge)
   * without a second geometry pass to decide whether the full span
   * still fits.
   */
  private void reveal_cursor_extremes () {
    var cursor_set = cursors.snapshot ();
    int min_offset = cursor_set[0].position_offset;
    int max_offset = cursor_set[0].position_offset;
    foreach (var cursor in cursor_set) {
      min_offset = int.min (min_offset, cursor.position_offset);
      max_offset = int.max (max_offset, cursor.position_offset);
    }

    Gtk.TextIter max_iter;
    source_buffer.get_iter_at_offset (out max_iter, max_offset);
    if (min_offset != max_offset) {
      Gtk.TextIter min_iter;
      source_buffer.get_iter_at_offset (out min_iter, min_offset);
      text_view.reveal_settled (min_iter, RevealMode.SIMPLE);
    }
    text_view.reveal_settled (max_iter, RevealMode.SIMPLE);
  }
}
