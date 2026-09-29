/**
 * One piece of a parsed dynamic {@link ReplacePattern} — either static
 * text, or a capture-group reference with whatever `\u\U\l\L` case ops
 * (if any) immediately preceded it in the Replace field. Never exposed
 * past ReplacePattern's own private `pieces` field.
 */
private class ReplacePiece : Object {
  public string? static_text { get; set; }
  public int group_index { get; set; default = -1; }
  public string[] case_ops { get; set; default = {}; }
}

/**
 * Parses a Find/Replace "Replace" field into a reusable pattern for
 * building the actual replacement text per match. A plain literal string
 * outside Regex mode; with Regex on, ported straight from VS Code's own
 * real `parseReplaceString`/`buildReplaceString`
 * (`src/vs/editor/contrib/find/browser/replacePattern.ts`) —
 * `gnome-text-editor` has no equivalent feature at all to check against
 * instead.
 *
 * Supported once Regex is on:
 *   `$$`          → a literal `$`
 *   `$&` and `$0` → the whole match
 *   `$1`-`$99`    → capture group N
 *   `\n` `\t` `\\` → newline, tab, a literal backslash
 *   `\u` / `\l`   → upper/lower-cases just the next one character of
 *                   whatever immediately follows (one-shot, consumes itself)
 *   `\U` / `\L`   → upper/lower-cases every remaining character of
 *                   whatever follows, until another case op overrides it
 * A case op only ever attaches to the *one* `$n` reference immediately
 * after it in the Replace text — it's consumed the moment that reference
 * is parsed, so `\U$1-$2` uppercases `$1` only, not `$2` too.
 */
public class ReplacePattern : Object {
  private bool is_static;
  private string static_text;
  private ReplacePiece[] pieces;

  private ReplacePattern () {}

  /** `regex_enabled` false always returns a plain literal pattern — the whole DSL above is regex-mode-only, matching VS Code's own real gate (`_getReplacePattern()`). */
  public static ReplacePattern parse (string replace_text, bool regex_enabled) {
    return regex_enabled ? parse_dynamic (replace_text) : literal (replace_text);
  }

  public static ReplacePattern literal (string value) {
    var pattern = new ReplacePattern ();
    pattern.is_static = true;
    pattern.static_text = value;
    pattern.pieces = {};
    return pattern;
  }

  /** Whether this pattern actually references capture groups/case-ops — false for a plain literal (regex off, or no `$`/`\` escapes found in the Replace text). */
  public bool has_replacement_patterns { get { return !is_static; } }

  /** `groups[0]` is the whole match, `groups[1..]` its capture groups (empty string for a group that didn't participate, or an out-of-range reference). */
  public string build (string[] groups) {
    if (is_static) {
      return static_text;
    }

    var result = new StringBuilder ();
    foreach (var piece in pieces) {
      if (piece.static_text != null) {
        result.append (piece.static_text);
      } else {
        result.append (apply_case_ops (group_text (piece.group_index, groups), piece.case_ops));
      }
    }
    return result.str;
  }

  private static string group_text (int index, string[] groups) {
    return (index >= 0 && index < groups.length) ? groups[index] : "";
  }

  private static string apply_case_ops (string text, string[] case_ops) {
    if (case_ops.length == 0) {
      return text;
    }

    var result = new StringBuilder ();
    int op_index = 0;
    foreach (var c in to_chars (text)) {
      if (op_index >= case_ops.length) {
        result.append_unichar (c);
        continue;
      }
      switch (case_ops[op_index]) {
        case "U":
          result.append_unichar (c.toupper ());
          break;
        case "u":
          result.append_unichar (c.toupper ());
          op_index++;
          break;
        case "L":
          result.append_unichar (c.tolower ());
          break;
        case "l":
          result.append_unichar (c.tolower ());
          op_index++;
          break;
      }
    }
    return result.str;
  }

  private static ReplacePattern parse_dynamic (string replace_text) {
    var chars = to_chars (replace_text);
    int n = chars.length;

    var pieces = new GenericArray<ReplacePiece> ();
    var static_buffer = new StringBuilder ();
    var pending_case_ops = new GenericArray<string> ();

    int i = 0;
    while (i < n) {
      unichar c = chars[i];

      if (c == '\\' && i + 1 < n) {
        unichar next = chars[i + 1];
        if (next == '\\') {
          static_buffer.append_c ('\\');
          i += 2;
        } else if (next == 'n') {
          static_buffer.append_c ('\n');
          i += 2;
        } else if (next == 't') {
          static_buffer.append_c ('\t');
          i += 2;
        } else if (next == 'u' || next == 'U' || next == 'l' || next == 'L') {
          pending_case_ops.add (next.to_string ());
          i += 2;
        } else {
          static_buffer.append_unichar (c);
          i += 1;
        }
        continue;
      }

      if (c == '$' && i + 1 < n) {
        unichar next = chars[i + 1];
        if (next == '$') {
          static_buffer.append_c ('$');
          i += 2;
          continue;
        }
        if (next == '0' || next == '&') {
          flush_static (pieces, static_buffer);
          pieces.add (new ReplacePiece () { group_index = 0, case_ops = to_string_array (pending_case_ops) });
          pending_case_ops = new GenericArray<string> ();
          i += 2;
          continue;
        }
        if (next.isdigit () && next != '0') {
          int group_index = next.digit_value ();
          int consumed = 2;
          if (i + 2 < n && chars[i + 2].isdigit ()) {
            group_index = group_index * 10 + chars[i + 2].digit_value ();
            consumed = 3;
          }
          flush_static (pieces, static_buffer);
          pieces.add (new ReplacePiece () { group_index = group_index, case_ops = to_string_array (pending_case_ops) });
          pending_case_ops = new GenericArray<string> ();
          i += consumed;
          continue;
        }
      }

      static_buffer.append_unichar (c);
      i += 1;
    }

    flush_static (pieces, static_buffer);

    // No `$n`/case-op ever showed up at all — every "\U"/"$$"-free
    // string parses down to exactly one purely-static piece (or
    // zero, for ""), same as VS Code's own real ReplacePattern
    // constructor collapses that case back to a plain literal
    // rather than leaving it "dynamic" with nothing to substitute.
    if (pieces.length == 0) {
      return literal ("");
    }
    if (pieces.length == 1 && pieces[0].static_text != null) {
      return literal (pieces[0].static_text);
    }

    var pattern = new ReplacePattern ();
    pattern.is_static = false;
    pattern.static_text = "";
    pattern.pieces = new ReplacePiece[pieces.length];
    for (uint k = 0; k < pieces.length; k++) {
      pattern.pieces[k] = pieces[k];
    }
    return pattern;
  }

  private static void flush_static (GenericArray<ReplacePiece> pieces, StringBuilder buffer) {
    if (buffer.len > 0) {
      pieces.add (new ReplacePiece () { static_text = buffer.str });
      buffer.erase ();
    }
  }

  private static string[] to_string_array (GenericArray<string> items) {
    var result = new string[items.length];
    for (uint i = 0; i < items.length; i++) {
      result[i] = items[i];
    }
    return result;
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
}
