/** One live occurrence within a single line of a single file's own FindInFilesBlock — never exposed outside that block's own `matches`. */
public class FindInFilesMatch : Object {
  /** 1-based, absolute within the file (not relative to the block it's shown in). */
  public int line_number;

  /** Char offset into that line's own text — not a byte offset, so it lines up directly with Gtk.TextIter's own offsets once rendered. */
  public int start_column;

  /** Exclusive. */
  public int end_column;
}
