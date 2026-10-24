/**
 * The pairs auto-close inserted that are still being typed inside of —
 * what lets typing `)` over the `)` Opus itself put there skip it, and
 * Backspace between the two take both out, while a `)` that was already
 * in the file stays ordinary text. Nothing in the text marks a closer;
 * this list is the only difference between the two.
 *
 * Entries are text spans, not cursors: every cursor move builds a fresh
 * Cursor, so "the cursor that typed it" has no identity to follow. An
 * entry lives while some cursor sits between its open and its close,
 * and dies with the first command that finds none there, or that
 * changed the text under either end (see {@link forget_stale}).
 */
public class InsertedPairs : Object {
  public class Entry : Object {
    /** Where `pair.open` starts. */
    public int open_offset;
    /** Where `pair.close` starts — the offset a cursor typing inside the pair sits at. */
    public int close_offset;
    public Syntax.BracketPair pair;

    public int open_end {
      get { return open_offset + pair.open_chars.length; }
    }
  }

  private GenericArray<Entry> entries = new GenericArray<Entry> ();

  public int count {
    get { return (int) entries.length; }
  }

  public void remember (int open_offset, int close_offset, Syntax.BracketPair pair) {
    var entry = new Entry ();
    entry.open_offset = open_offset;
    entry.close_offset = close_offset;
    entry.pair = pair;
    entries.add (entry);
  }

  public void clear () {
    entries.remove_range (0, entries.length);
  }

  /**
   * Moves both ends of every entry past `edits`, by the same rule
   * CursorCollection moves a cursor: an edit ending at or before an
   * offset shifts it. Typing at the close shifts the close and not the
   * open — `(|)` becomes `(a|)`.
   */
  public void shift (TextEdit[] edits) {
    foreach (var entry in entries) {
      entry.open_offset = shifted (entry.open_offset, edits);
      entry.close_offset = shifted (entry.close_offset, edits);
    }
  }

  /**
   * Drops every entry no cursor sits inside (between the end of its
   * open and the start of its close, both included), whose open or
   * close is no longer where it was, or whose inside now spans a line
   * break. Called once per command, after the cursors have settled.
   */
  public void forget_stale (unichar[] chars, Cursor[] cursors) {
    for (int i = (int) entries.length - 1; i >= 0; i--) {
      if (!still_live (entries[i], chars, cursors)) {
        entries.remove_index (i);
      }
    }
  }

  /** The entry whose close starts at `offset`, null for none. */
  public Entry? closing_at (int offset) {
    foreach (var entry in entries) {
      if (entry.close_offset == offset) {
        return entry;
      }
    }
    return null;
  }

  /** The entry with nothing left between its open and its close, both meeting at `offset` — Backspace's pair delete. */
  public Entry? around (int offset) {
    foreach (var entry in entries) {
      if (entry.open_end == offset && entry.close_offset == offset) {
        return entry;
      }
    }
    return null;
  }

  private static int shifted (int offset, TextEdit[] edits) {
    int delta = 0;
    foreach (var edit in edits) {
      if (edit.end_offset <= offset) {
        delta += edit.new_text.char_count () - (edit.end_offset - edit.start_offset);
      }
    }
    return offset + delta;
  }

  private static bool still_live (Entry entry, unichar[] chars, Cursor[] cursors) {
    if (entry.close_offset < entry.open_end
        || !entry.pair.opens_before (chars, entry.open_end)
        || !entry.pair.closes_at (chars, entry.close_offset)) {
      return false;
    }
    for (int i = entry.open_end; i < entry.close_offset; i++) {
      if (chars[i] == '\n') {
        return false;
      }
    }
    foreach (var cursor in cursors) {
      if (entry.open_end <= cursor.position_offset && cursor.position_offset <= entry.close_offset) {
        return true;
      }
    }
    return false;
  }
}
