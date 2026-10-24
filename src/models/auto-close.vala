/** The `editor.auto_close.*` switches, resolved for one language. */
public class AutoCloseSettings : Object {
  public bool brackets { get; construct; }
  public bool quotes { get; construct; }
  public bool surround_selection { get; construct; }
  /** Whether overtype and pair delete act only on pairs Opus inserted (see InsertedPairs); off, any pair at the cursor counts. */
  public bool track_inserted_pairs { get; construct; }

  public AutoCloseSettings (bool brackets, bool quotes, bool surround_selection, bool track_inserted_pairs) {
    Object (brackets: brackets, quotes: quotes, surround_selection: surround_selection, track_inserted_pairs: track_inserted_pairs);
  }

  public static AutoCloseSettings all_on () {
    return new AutoCloseSettings (true, true, true, true);
  }
}

/**
 * The syntax at a character offset — the caret between two characters,
 * or the character at the offset itself with `of_character`. Null when
 * the text has no language. See Syntax.SyntaxDocument.scope_at.
 */
public delegate Syntax.Scope? ScopeAtFunc (int char_offset, bool of_character);

/**
 * What one keystroke does at one cursor beyond inserting itself, as
 * docs/AUTO_CLOSE.md defines it: closing the pair it opens, skipping
 * the closer already there, wrapping the selection, or taking both
 * halves of an empty pair out on Backspace. Each method answers null
 * when the keystroke is plain typing for that cursor.
 */
public class AutoClose : Object {
  private AutoCloseSettings settings;
  private ScopeAtFunc? scope_at;
  private Syntax.PairSet no_language_pairs = Syntax.PairSet.defaults ();

  public AutoClose (AutoCloseSettings settings, owned ScopeAtFunc? scope_at) {
    this.settings = settings;
    this.scope_at = (owned) scope_at;
  }

  public TaggedTextEdit? typing_edit (unichar[] chars, Cursor cursor, unichar typed, bool overtype_mode, InsertedPairs memory) {
    var pairs = pairs_at (cursor.selection_start);
    if (!cursor.is_empty) {
      return surround_edit (chars, cursor, typed, pairs);
    }
    if (overtype_mode) {
      return null;
    }
    return overtype_edit (chars, cursor, typed, pairs, memory) ?? close_edit (chars, cursor, typed, pairs);
  }

  public TaggedTextEdit? backspace_edit (unichar[] chars, Cursor cursor, bool overtype_mode, InsertedPairs memory) {
    if (!cursor.is_empty || overtype_mode) {
      return null;
    }
    int offset = cursor.position_offset;
    var pair = settings.track_inserted_pairs ? memory.around (offset)?.pair : pairs_at (offset).around (chars, offset);
    if (pair == null || !enabled (pair)) {
      return null;
    }
    return tagged (cursor, offset - pair.open_chars.length, offset + pair.close_chars.length, chars, "");
  }

  /** `foo` + `(` is `(foo)`, the selection still on `foo`. Any pair that surrounds, by its one-character open or close; no scope or quote guard. */
  private TaggedTextEdit? surround_edit (unichar[] chars, Cursor cursor, unichar typed, Syntax.PairSet pairs) {
    if (!settings.surround_selection) {
      return null;
    }
    var pair = surrounding_pair (pairs, typed);
    if (pair == null) {
      return null;
    }
    int start = cursor.selection_start;
    int end = cursor.selection_end;
    var result = tagged (cursor, start, end, chars, pair.open + chars_to_string (chars, start, end) + pair.close);
    int inner_start = pair.open_chars.length;
    int inner_end = inner_start + end - start;
    bool forward = cursor.position_offset >= cursor.anchor_offset;
    result.anchor_in_new_text = forward ? inner_start : inner_end;
    result.caret_in_new_text = forward ? inner_end : inner_start;
    return result;
  }

  /** `(foo|)` + `)` only moves past the `)` — a no-op edit over it, which repositions the cursor and changes nothing. One-character closers only. */
  private TaggedTextEdit? overtype_edit (unichar[] chars, Cursor cursor, unichar typed, Syntax.PairSet pairs, InsertedPairs memory) {
    int offset = cursor.position_offset;
    if (offset >= chars.length || chars[offset] != typed) {
      return null;
    }
    var pair = settings.track_inserted_pairs ? memory.closing_at (offset)?.pair : pairs.closing_with (typed);
    if (pair == null || pair.close_chars.length != 1 || !enabled (pair)) {
      return null;
    }
    if (pair.is_quote && offset > 0 && chars[offset - 1] == '\\') {
      return null;
    }
    return tagged (cursor, offset, offset + 1, chars, typed.to_string ());
  }

  /** `(` is `(|)`: the typed character plus the pair's close, caret between them. */
  private TaggedTextEdit? close_edit (unichar[] chars, Cursor cursor, unichar typed, Syntax.PairSet pairs) {
    int offset = cursor.position_offset;
    var pair = pairs.opening_at (chars, offset, typed);
    if (pair == null || !pair.auto_close || !enabled (pair)) {
      return null;
    }
    if (pair.inert_in (captures_at (offset, false)) || !pairs.may_close_before (chars, offset)) {
      return null;
    }
    if (pair.is_quote && (after_word (chars, offset) || closes_a_quote_on_its_line (chars, offset, pair))) {
      return null;
    }
    var result = tagged (cursor, offset, offset, chars, typed.to_string () + pair.close);
    result.caret_in_new_text = 1;
    result.closed_pair = settings.track_inserted_pairs ? pair : null;
    return result;
  }

  private bool enabled (Syntax.BracketPair pair) {
    return pair.is_quote ? settings.quotes : settings.brackets;
  }

  /** `don|` + `'` is an apostrophe, not a string. */
  private static bool after_word (unichar[] chars, int offset) {
    return offset > 0 && (chars[offset - 1].isalnum () || chars[offset - 1] == '_');
  }

  /**
   * `"hello|` + `"` ends the string: an odd number of this quote on
   * the line before the cursor means one is open. Quotes where the pair
   * is inert — an apostrophe inside a comment — don't count.
   */
  private bool closes_a_quote_on_its_line (unichar[] chars, int offset, Syntax.BracketPair pair) {
    var quote = pair.open_chars[0];
    int count = 0;
    for (int k = line_start (chars, offset); k < offset; k++) {
      if (chars[k] == quote && !(pair.not_in.length > 0 && pair.inert_in (captures_at (k, true)))) {
        count++;
      }
    }
    return count % 2 == 1;
  }

  private static Syntax.BracketPair? surrounding_pair (Syntax.PairSet pairs, unichar typed) {
    foreach (var pair in pairs.pairs) {
      if (!pair.surround || pair.open_chars.length != 1) {
        continue;
      }
      if (pair.open_chars[0] == typed || (pair.close_chars.length == 1 && pair.close_chars[0] == typed)) {
        return pair;
      }
    }
    return null;
  }

  private Syntax.PairSet pairs_at (int offset) {
    if (scope_at == null) {
      return no_language_pairs;
    }
    return scope_at (offset, false)?.package.pairs ?? no_language_pairs;
  }

  private string[] captures_at (int offset, bool of_character) {
    if (scope_at == null) {
      return {};
    }
    return scope_at (offset, of_character)?.captures ?? new string[0];
  }

  private static TaggedTextEdit tagged (Cursor cursor, int start, int end, unichar[] chars, string new_text) {
    var edit = new TextEdit ();
    edit.start_offset = start;
    edit.end_offset = end;
    edit.old_text = chars_to_string (chars, start, end);
    edit.new_text = new_text;
    var result = new TaggedTextEdit ();
    result.edit = edit;
    result.cursor = cursor;
    return result;
  }

  private static int line_start (unichar[] chars, int offset) {
    int i = offset;
    while (i > 0 && chars[i - 1] != '\n') {
      i--;
    }
    return i;
  }

  private static string chars_to_string (unichar[] chars, int start, int end) {
    var builder = new StringBuilder ();
    for (int i = start; i < end; i++) {
      builder.append_unichar (chars[i]);
    }
    return builder.str;
  }
}
