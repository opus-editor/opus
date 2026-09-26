/**
 * A single text replacement: `[start_offset, end_offset)` in a document's
 * content is replaced with `new_text`. `old_text` is what was there
 * before — kept so the edit can be inverted for undo.
 */
public class TextEdit : Object {
  public int start_offset { get; set; }
  public int end_offset { get; set; }
  public string old_text { get; set; default = ""; }
  public string new_text { get; set; default = ""; }

  /** The opposite edit — replaying it restores what this edit replaced. Only correct in isolation; see invert_batch() for a group of edits that landed together. */
  public TextEdit inverse () {
    var result = new TextEdit ();
    result.start_offset = start_offset;
    result.end_offset = start_offset + new_text.char_count ();
    result.old_text = new_text;
    result.new_text = old_text;
    return result;
  }

  /**
   * Inverts a whole batch of edits that were all computed together
   * against the *same* pre-batch text (e.g. one CursorCollection.
   * compute_edits() call across several simultaneous cursors) —
   * `edits` must already be sorted ascending by start_offset, exactly
   * what compute_edits() returns.
   *
   * A single edit's own inverse() is only correct in isolation: within
   * a batch, a later (higher-offset) edit's true position in the text
   * *after the whole batch lands* is shifted by every earlier edit's
   * own length delta, and inverse() alone doesn't know that — undoing
   * with un-rebased offsets edits the wrong place the moment a batch
   * has more than one edit (e.g. two simultaneous cursors typing the
   * same character).
   */
  public static TextEdit[] invert_batch (TextEdit[] edits) {
    var result = new TextEdit[edits.length];
    int running_delta = 0;

    for (int i = 0; i < edits.length; i++) {
      var edit = edits[i];
      int rebased_start = edit.start_offset + running_delta;
      int new_length = edit.new_text.char_count ();

      var inverted = new TextEdit ();
      inverted.start_offset = rebased_start;
      inverted.end_offset = rebased_start + new_length;
      inverted.old_text = edit.new_text;
      inverted.new_text = edit.old_text;
      result[i] = inverted;

      running_delta += new_length - (edit.end_offset - edit.start_offset);
    }

    return result;
  }
}
