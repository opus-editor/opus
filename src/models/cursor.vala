/**
 * One text cursor: an anchor (the fixed end of a selection) and a caret
 * position (the end that moves), both plain codepoint offsets into a
 * document's content. A collapsed cursor (no selection) has
 * `anchor_offset == position_offset`.
 */
public class Cursor : Object {
  public int anchor_offset { get; set; }
  public CursorAnchorKind anchor_kind { get; set; default = CursorAnchorKind.CHARACTER; }
  public int position_offset { get; set; }

  /**
   * The goal visible column within the cursor's display row (a `\t`
   * counting up to the next tab stop), remembered across consecutive
   * Up/Down presses so moving through shorter rows and back doesn't
   * lose the original horizontal position — VS Code's own
   * leftoverVisibleColumns, GTK's virtual_cursor_x in columns rather
   * than pixels. `-1` means "no memory yet" — the next vertical move
   * derives it fresh from the current position; every other move,
   * edit, or click resets it to that.
   */
  public double leftover_column { get; set; default = -1.0; }

  public Cursor (int offset) {
    anchor_offset = offset;
    position_offset = offset;
  }

  public int selection_start { get { return int.min (anchor_offset, position_offset); } }
  public int selection_end { get { return int.max (anchor_offset, position_offset); } }
  public bool is_empty { get { return anchor_offset == position_offset; } }

  /** An independent copy — used whenever a cursor's state is captured into a snapshot (e.g. undo history) that must not be affected by further live edits. */
  public Cursor clone () {
    var copy = new Cursor (anchor_offset);
    copy.anchor_kind = anchor_kind;
    copy.position_offset = position_offset;
    copy.leftover_column = leftover_column;
    return copy;
  }
}

/** Which granularity a cursor's anchor was set at — remembered so extending a word/line-selected anchor keeps snapping to that same granularity. Not yet acted on beyond WORD (set by {@link CursorCollection.add_cursor_at_next_match}'s word-expansion) — LINE is reserved for a future triple-click/select-line command. */
public enum CursorAnchorKind {
  CHARACTER,
  WORD,
  LINE
}
