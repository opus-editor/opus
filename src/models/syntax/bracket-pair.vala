namespace Syntax {
  /**
   * One pair a language auto-closes or surrounds a selection with — a
   * `pairs` entry of `language.json`. `open` and `close` can be any
   * length: a block comment's delimiters are a pair as much as `(` and `)`.
   */
  public class BracketPair : Object {
    public string open { get; private set; }
    public string close { get; private set; }
    /** Highlight captures the pair is inert inside; `string` covers `string.special` too. */
    public string[] not_in { get; private set; }
    /** Whether typing `open` inserts `close`; false keeps the pair for surround alone. */
    public bool auto_close { get; private set; }
    /** Whether typing `open` over a selection wraps it; false keeps the pair for auto-close alone. */
    public bool surround { get; private set; }
    /** Whether Enter between the two halves opens a line between them, indented — `{|}` becoming three lines. Brackets by default; quotes, and whatever the manifest says otherwise, not. */
    public bool newline { get; private set; }

    /** `open` and `close` as code points, for matching against a text's own characters. */
    public unichar[] open_chars;
    public unichar[] close_chars;

    public BracketPair (string open, string close, string[] not_in, bool auto_close, bool surround, bool? newline = null) {
      this.open = open;
      this.close = close;
      this.not_in = not_in;
      this.auto_close = auto_close;
      this.surround = surround;
      this.newline = newline ?? !is_quote;
      open_chars = chars_of (open);
      close_chars = chars_of (close);
    }

    /** A quote closes with what opened it, so it can't tell an opening from a closing by itself. */
    public bool is_quote {
      get { return open == close; }
    }

    /** Whether any of `captures` (highlight capture names at a place in the text) is one `not_in` names. */
    public bool inert_in (string[] captures) {
      foreach (var capture in captures) {
        foreach (var scope in not_in) {
          if (capture == scope || capture.has_prefix (scope + ".")) {
            return true;
          }
        }
      }
      return false;
    }

    /** Whether `chars` holds `open` ending right before `offset`. */
    public bool opens_before (unichar[] chars, int offset) {
      return matches_at (open_chars, chars, offset - open_chars.length);
    }

    /** Whether `chars` holds `close` starting at `offset`. */
    public bool closes_at (unichar[] chars, int offset) {
      return matches_at (close_chars, chars, offset);
    }

    private static bool matches_at (unichar[] needle, unichar[] chars, int start) {
      if (start < 0 || start + needle.length > chars.length) {
        return false;
      }
      for (int i = 0; i < needle.length; i++) {
        if (chars[start + i] != needle[i]) {
          return false;
        }
      }
      return true;
    }

    private static unichar[] chars_of (string text) {
      unichar[] result = {};
      int index = 0;
      unichar c;
      while (text.get_next_char (ref index, out c)) {
        result += c;
      }
      return result;
    }
  }

  /** A language's pairs and the characters a closer may be inserted in front of. */
  public class PairSet : Object {
    public const string DEFAULT_AUTO_CLOSE_BEFORE = ";:.,=}])>";

    public BracketPair[] pairs;
    /** Besides whitespace and the end of a line, what the character after the cursor may be for a pair to close. */
    public string auto_close_before { get; private set; }

    public PairSet (BracketPair[] pairs, string auto_close_before) {
      this.pairs = pairs;
      this.auto_close_before = auto_close_before;
    }

    /** What a language gets when its manifest declares no `pairs`, and what a file with no language gets. */
    public static PairSet defaults () {
      return new PairSet ({
        new BracketPair ("(", ")", {}, true, true),
        new BracketPair ("[", "]", {}, true, true),
        new BracketPair ("{", "}", {}, true, true),
        new BracketPair ("\"", "\"", {}, true, true),
        new BracketPair ("'", "'", {}, true, true),
      }, DEFAULT_AUTO_CLOSE_BEFORE);
    }

    /**
     * The pair `typed` at `offset` finishes opening — the longest one
     * whose `open` ends in `typed` and otherwise already sits before
     * `offset`. With `${` and `{` both declared, `{` after `$` is `${`.
     */
    public BracketPair? opening_at (unichar[] chars, int offset, unichar typed) {
      BracketPair? found = null;
      foreach (var pair in pairs) {
        var open = pair.open_chars;
        if (open[open.length - 1] != typed) {
          continue;
        }
        var prefix = open[0 : open.length - 1];
        if (!prefix_before (prefix, chars, offset)) {
          continue;
        }
        if (found == null || open.length > found.open_chars.length) {
          found = pair;
        }
      }
      return found;
    }

    /**
     * Whether a closer may be inserted at `offset`: at the end of the
     * text or line, before whitespace, before one of
     * `auto_close_before`, or before what closes a bracket — never
     * before a quote, which may just as well be opening one.
     */
    public bool may_close_before (unichar[] chars, int offset) {
      if (offset >= chars.length) {
        return true;
      }
      var next = chars[offset];
      if (next.isspace () || auto_close_before.index_of_char (next) >= 0) {
        return true;
      }
      foreach (var pair in pairs) {
        if (!pair.is_quote && pair.closes_at (chars, offset)) {
          return true;
        }
      }
      return false;
    }

    /** The first pair whose close is exactly `typed`, null for none. */
    public BracketPair? closing_with (unichar typed) {
      foreach (var pair in pairs) {
        if (pair.close_chars.length == 1 && pair.close_chars[0] == typed) {
          return pair;
        }
      }
      return null;
    }

    /** The first pair with its open ending and its close starting at `offset` — an empty pair the cursor sits inside. */
    public BracketPair? around (unichar[] chars, int offset) {
      foreach (var pair in pairs) {
        if (pair.opens_before (chars, offset) && pair.closes_at (chars, offset)) {
          return pair;
        }
      }
      return null;
    }

    private static bool prefix_before (unichar[] prefix, unichar[] chars, int offset) {
      int start = offset - prefix.length;
      if (start < 0) {
        return false;
      }
      for (int i = 0; i < prefix.length; i++) {
        if (chars[start + i] != prefix[i]) {
          return false;
        }
      }
      return true;
    }
  }
}
