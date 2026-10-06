/**
 * Tracks edits GtkSourceView itself makes to the buffer, unclaimed by
 * CodeEditorInput — block-indent/outdent over a selected Tab/Shift+Tab is
 * the only such case today (see CodeEditorInput's own doc comment on its
 * Tab handler). An edit CodeEditorCursors claims gets an EditHistory
 * entry and the text_changed signal that tells the Document it's dirty
 * for free, through its own execute_edit(); this is that same
 * bookkeeping for the edits it never sees land.
 *
 * Every edit landing inside one begin/end-user-action pair is coalesced
 * into a single EditHistory push instead of one per edit: GtkSourceView's
 * own block-indent fires one insert-text per selected line inside a
 * single such pair, so without this, Ctrl+Z would undo it one line at a
 * time. Each line's own raw buffer offset already reflects every earlier
 * line's own insertion in the same group (GTK applies them one at a
 * time, for real, as it goes) — rebased back to the group's shared
 * pre-batch coordinates before being stored, since invert_batch()/
 * CodeEditorCursors' own apply_edits() need every edit in a push
 * expressed against that same pre-edit text, the same shape
 * CursorCollection.compute_edits() already produces for a claimed edit.
 */
public class CodeEditorNativeEdits : Object {
  private CodeEditorSourceView text_view;
  private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }

  private CursorCollection cursors;
  private EditHistory history;

  /** Suppresses every handler below while CodeEditorCursors is itself writing the buffer (its own apply_edits()/load_text()) — otherwise that write would be misread as an untracked native edit. Toggled by CodeEditorCursors around those calls. */
  public bool updating_programmatically { get; set; default = false; }

  // Collects every native edit landing inside one begin/end-user-action
  // pair into a single push instead of one per edit. Counts nesting
  // depth since GtkTextBuffer emits both signals on every begin/end
  // call, not only the outermost pair. Null between groups.
  private int action_depth = 0;
  private GenericArray<TextEdit>? pending_edits = null;
  private Cursor[] pending_before_cursors;
  // Net length change (chars) of every edit already collected into
  // pending_edits — see the class doc comment for why each raw offset
  // needs rebasing by this before being stored.
  private int pending_delta = 0;

  /** The buffer's full content just changed through an edit recorded here — CodeEditorCursors.text_changed just re-emits this one, the same bubbling its own apply_edits() already does one level up. */
  public signal void text_changed (string new_text);

  public CodeEditorNativeEdits (CodeEditorSourceView text_view) {
    this.text_view = text_view;

    source_buffer.begin_user_action.connect (on_begin_user_action);
    source_buffer.end_user_action.connect (on_end_user_action);
    // Plain .connect() (not _after) runs before the mutation actually
    // lands, so pos/start/end still describe what's *about to* happen.
    source_buffer.insert_text.connect (on_insert_text);
    source_buffer.delete_range.connect (on_delete_range);
  }

  /** Swaps in the cursor set and undo stack to record against — CodeEditorCursors calls this from its own bind(), with the exact same pair. */
  public void bind (CursorCollection cursors, EditHistory history) {
    this.cursors = cursors;
    this.history = history;
  }

  private void on_insert_text (ref Gtk.TextIter pos, string new_text, int new_text_length) {
    if (updating_programmatically || new_text == "") {
      return;
    }

    int offset = pos.get_offset ();
    push_edit (new TextEdit () { start_offset = offset, end_offset = offset, old_text = "", new_text = new_text });
  }

  private void on_delete_range (Gtk.TextIter start, Gtk.TextIter end) {
    if (updating_programmatically) {
      return;
    }

    push_edit (new TextEdit () {
      start_offset = start.get_offset (), end_offset = end.get_offset (),
      old_text = source_buffer.get_text (start, end, false), new_text = ""
    });
  }

  /** Records one native edit — into the open begin/end-user-action group it landed in, rebased back to that group's pre-batch coordinates (see the class doc comment), or pushed (and signaled) alone if somehow none is open. */
  private void push_edit (TextEdit edit) {
    if (pending_edits == null) {
      history.push ({ edit }, cursors.snapshot (), cursors.snapshot (), EditKind.OTHER);
      text_changed (source_buffer.text);
      return;
    }

    int length = edit.end_offset - edit.start_offset;
    pending_edits.add (new TextEdit () {
      start_offset = edit.start_offset - pending_delta,
      end_offset = edit.end_offset - pending_delta,
      old_text = edit.old_text, new_text = edit.new_text,
    });
    pending_delta += edit.new_text.char_count () - length;
  }

  private void on_begin_user_action () {
    if (updating_programmatically) {
      return;
    }
    if (action_depth == 0) {
      pending_edits = new GenericArray<TextEdit> ();
      pending_before_cursors = cursors.snapshot ();
      pending_delta = 0;
    }
    action_depth++;
  }

  private void on_end_user_action () {
    if (updating_programmatically) {
      return;
    }
    action_depth--;
    if (action_depth > 0 || pending_edits == null) {
      return;
    }

    if (pending_edits.length > 0) {
      var edits = new TextEdit[pending_edits.length];
      for (uint i = 0; i < pending_edits.length; i++) {
        edits[i] = pending_edits[i];
      }
      history.push (edits, pending_before_cursors, cursors.snapshot (), EditKind.OTHER);
      text_changed (source_buffer.text);
    }
    pending_edits = null;
  }
}
