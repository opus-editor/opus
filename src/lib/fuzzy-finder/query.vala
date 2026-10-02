namespace Opus.FuzzyFinder {
  /**
   * A search string prepared once per keystroke so every candidate
   * scored against it pays nothing for normalization — the same split
   * VS Code's own `prepareQuery` (fuzzyScorer.ts) makes. Whitespace,
   * wildcards and quotes are matching syntax, not characters to find:
   * `"quoted"` asks for a contiguous match instead of a fuzzy one.
   */
  public class Query : Object {
    public string original { get; private set; }
    public string normalized { get; private set; }
    public string normalized_lower { get; private set; }
    public bool contains_separator { get; private set; }
    public bool exact { get; private set; }
    public uint64 char_bag { get; private set; }

    internal unichar[] chars;
    internal unichar[] chars_lower;

    public Query (string text) {
      original = text;
      exact = text.length >= 2 && text.has_prefix ("\"") && text.has_suffix ("\"");

      var builder = new StringBuilder ();
      int index = 0;
      unichar c;
      while (text.get_next_char (ref index, out c)) {
        if (c.isspace () || c == '*' || c == '"' || c == 0x2026) {
          continue;
        }
        builder.append_unichar (c == '\\' ? '/' : c);
      }
      normalized = builder.str;
      normalized_lower = normalized.casefold ();
      contains_separator = normalized.contains ("/");
      char_bag = Scorer.char_bag_of (normalized_lower);
      chars = Scorer.to_chars (normalized);
      chars_lower = Scorer.to_chars (normalized_lower);
    }

    public bool is_empty {
      get { return normalized_lower == ""; }
    }

    /** Whether this query only adds characters to `previous` — the case where everything `previous` rejected stays rejected, so only its survivors need re-scoring. */
    public bool extends (Query previous) {
      return previous.normalized_lower != "" && normalized_lower.has_prefix (previous.normalized_lower);
    }
  }
}
