/**
 * How a document's text currently breaks into display rows — a View
 * fact (wrap width, font, zoom) the cursor model can't compute itself,
 * handed in so CursorCollection can move by row without importing Gtk.
 * VS Code's own ICursorSimpleModel, which its MoveOperations take as a
 * parameter to move by view line or by model line with one routine
 * (checked common/cursor/cursorMoveOperations.ts: `moveDown (config,
 * model: ICursorSimpleModel, …)` is handed either the view model or the
 * text model).
 *
 * Offsets are codepoint offsets, same as Cursor's. A row's `end` is its
 * last caret position: the newline (or buffer end) on a paragraph's
 * last row, otherwise the position just before the next row's first
 * character — the one GtkTextView's own End lands on
 * (`forward_display_line_end()` steps back one char on a non-last row).
 */
public interface IDisplayRows : Object {
  /** The row containing `offset`. */
  public abstract void row_bounds (int offset, out int start, out int end);

  /** The row above the one containing `offset`; false on the buffer's first row. */
  public abstract bool row_above (int offset, out int start, out int end);

  /** The row below the one containing `offset`; false on the buffer's last row. */
  public abstract bool row_below (int offset, out int start, out int end);
}

/**
 * Rows are `\n`-delimited paragraphs — what every display row is with
 * word wrap off, and what "the line above/below" means for Shift+Alt+
 * Up/Down regardless of wrap (VS Code's insertCursorAbove/Below default
 * to `useLogicalLine = true`, checked contrib/multicursor/browser/
 * multicursor.ts). Built over the text once per command, like
 * CursorCollection's own `to_chars()`.
 */
public class ParagraphRows : Object, IDisplayRows {
  private const unichar NEWLINE = '\n';

  private unichar[] chars;

  public ParagraphRows (string text) {
    int n = text.char_count ();
    chars = new unichar[n];
    unowned string iter = text;
    for (int i = 0; i < n; i++) {
      chars[i] = iter.get_char ();
      iter = iter.next_char ();
    }
  }

  public void row_bounds (int offset, out int start, out int end) {
    start = offset;
    while (start > 0 && chars[start - 1] != NEWLINE) {
      start--;
    }
    end = offset;
    while (end < chars.length && chars[end] != NEWLINE) {
      end++;
    }
  }

  public bool row_above (int offset, out int start, out int end) {
    int this_start;
    int this_end;
    row_bounds (offset, out this_start, out this_end);
    if (this_start == 0) {
      start = 0;
      end = 0;
      return false;
    }
    row_bounds (this_start - 1, out start, out end);
    return true;
  }

  public bool row_below (int offset, out int start, out int end) {
    int this_start;
    int this_end;
    row_bounds (offset, out this_start, out this_end);
    if (this_end >= chars.length) {
      start = 0;
      end = 0;
      return false;
    }
    row_bounds (this_end + 1, out start, out end);
    return true;
  }
}
