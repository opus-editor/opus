namespace GitDiff {
  /** A changed stretch of one line, in character (unichar) offsets, end exclusive. */
  public struct CharRange {
    public int start;
    public int end;
  }

  /**
   * What changed inside one pair of lines, the way Zed marks it
   * (crates/language/src/text_diff.rs): both lines cut into tokens — a
   * run of word characters, of whitespace, or of one punctuation
   * character — and the tokens one side has that the other lacks
   * reported as ranges, touching ones merged. No heuristics beyond that:
   * a renamed identifier lights up whole, not just the letters that
   * differ, and an indentation change lights up its spaces.
   */
  public class WordDiff : Object {
    // Bounds the O(n·m) table: a line this long gets the row band alone.
    private const int MAX_TOKENS = 1000;
    private const int WORD = 0;
    private const int WHITESPACE = 1;
    private const int PUNCTUATION = 2;

    private struct Token {
      public string text;
      public int start;
      public int end;
    }

    /** The token ranges `old_line` lost and `new_line` gained. Both empty when the lines are equal. */
    public static void compute (string old_line, string new_line, out CharRange[] old_ranges, out CharRange[] new_ranges) {
      old_ranges = {};
      new_ranges = {};
      if (old_line == new_line) {
        return;
      }
      var old_tokens = tokenize (old_line);
      var new_tokens = tokenize (new_line);
      if (old_tokens.length > MAX_TOKENS || new_tokens.length > MAX_TOKENS) {
        return;
      }
      bool[] old_kept;
      bool[] new_kept;
      common_tokens (old_tokens, new_tokens, out old_kept, out new_kept);
      old_ranges = changed_ranges (old_tokens, old_kept);
      new_ranges = changed_ranges (new_tokens, new_kept);
    }

    private static Token[] tokenize (string line) {
      Token[] tokens = {};
      unichar c;
      int index = 0;
      int offset = 0;
      int kind = -1;
      unichar previous = 0;
      while (line.get_next_char (ref index, out c)) {
        int c_kind = kind_of (c);
        bool starts_token = c_kind != kind || (c_kind == PUNCTUATION && c != previous);
        if (starts_token) {
          tokens += Token () { text = "", start = offset, end = offset };
        }
        tokens[tokens.length - 1].text += c.to_string ();
        tokens[tokens.length - 1].end = offset + 1;
        kind = c_kind;
        previous = c;
        offset++;
      }
      return tokens;
    }

    private static int kind_of (unichar c) {
      if (c.isalnum () || c == '_') {
        return WORD;
      }
      return c.isspace () ? WHITESPACE : PUNCTUATION;
    }

    /** Longest common subsequence over the token texts; `kept` flags the tokens on it. */
    private static void common_tokens (Token[] a, Token[] b, out bool[] a_kept, out bool[] b_kept) {
      int n = a.length;
      int m = b.length;
      var table = new int[(n + 1) * (m + 1)];
      for (int i = n - 1; i >= 0; i--) {
        for (int j = m - 1; j >= 0; j--) {
          if (a[i].text == b[j].text) {
            table[i * (m + 1) + j] = table[(i + 1) * (m + 1) + j + 1] + 1;
          } else {
            table[i * (m + 1) + j] = int.max (table[(i + 1) * (m + 1) + j], table[i * (m + 1) + j + 1]);
          }
        }
      }
      a_kept = new bool[n];
      b_kept = new bool[m];
      int x = 0;
      int y = 0;
      while (x < n && y < m) {
        if (a[x].text == b[y].text) {
          a_kept[x++] = true;
          b_kept[y++] = true;
        } else if (table[(x + 1) * (m + 1) + y] >= table[x * (m + 1) + y + 1]) {
          x++;
        } else {
          y++;
        }
      }
    }

    private static CharRange[] changed_ranges (Token[] tokens, bool[] kept) {
      CharRange[] ranges = {};
      for (int i = 0; i < tokens.length; i++) {
        if (kept[i]) {
          continue;
        }
        if (ranges.length > 0 && ranges[ranges.length - 1].end == tokens[i].start) {
          ranges[ranges.length - 1].end = tokens[i].end;
        } else {
          ranges += CharRange () { start = tokens[i].start, end = tokens[i].end };
        }
      }
      return ranges;
    }
  }
}
