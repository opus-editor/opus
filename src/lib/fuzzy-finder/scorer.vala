namespace Opus.FuzzyFinder {
  /**
   * Scores one candidate string against a {@link Query}: a port of VS
   * Code's `scoreFuzzy`/`scoreItemFuzzy` (base/common/fuzzyScorer.ts) —
   * a query×target matrix rewarding consecutive runs, word/segment
   * starts and matching case, with a candidate's basename (the text
   * after its last "/") tried first and boosted so that typing a file
   * name wins over the same letters scattered through its directory.
   *
   * `char_bag_of`/`contains_subsequence` are the two cheap rejections
   * callers run before paying for the matrix: a bitset of which
   * characters a string contains (Zed's CharBag), and VS Code's own
   * `fuzzyContains` ordered-subsequence test — both strict supersets of
   * what `score` can match, so nothing true is ever dropped.
   */
  public class Scorer : Object {
    public const int PATH_IDENTITY_SCORE = 1 << 18;
    public const int LABEL_PREFIX_SCORE = 1 << 17;
    public const int LABEL_SCORE = 1 << 16;

    public static uint64 char_bag_of (string lower) {
      uint64 bag = 0;
      int index = 0;
      unichar c;
      while (lower.get_next_char (ref index, out c)) {
        int bit = char_bag_bit (c);
        if (bit >= 0) {
          bag |= ((uint64) 1) << bit;
        }
      }
      return bag;
    }

    private static int char_bag_bit (unichar c) {
      if (c >= 'a' && c <= 'z') {
        return (int) (c - 'a');
      }
      if (c >= '0' && c <= '9') {
        return 26 + (int) (c - '0');
      }
      switch (c) {
        case '-': return 36;
        case '_': return 37;
        case '.': return 38;
        case '/': return 39;
        default: return -1;
      }
    }

    /** Whether every byte of `query_lower` appears in `target_lower`, in order — bytes, not characters: on valid UTF-8 that can only ever over-accept, never reject a real match. */
    public static bool contains_subsequence (string target_lower, string query_lower) {
      if (query_lower.length == 0) {
        return true;
      }
      if (target_lower.length < query_lower.length) {
        return false;
      }
      int target_index = 0;
      for (int query_index = 0; query_index < query_lower.length; query_index++) {
        char wanted = query_lower[query_index];
        while (target_index < target_lower.length && target_lower[target_index] != wanted) {
          target_index++;
        }
        if (target_index == target_lower.length) {
          return false;
        }
        target_index++;
      }
      return true;
    }

    /** Scores `target` (a "/"-separated path, or any string) against `query`; false when it doesn't match at all. `target_lower` is `target.casefold ()`, passed in so an index casefolds each candidate once rather than per query. */
    public static bool score (string target, string target_lower, Query query, out int score, out int[] ranges) {
      score = 0;
      ranges = {};
      if (query.is_empty || target == "") {
        return false;
      }

      var target_chars = to_chars (target);
      var target_lower_chars = to_chars (target_lower);
      if (target_lower == query.normalized_lower) {
        score = PATH_IDENTITY_SCORE;
        ranges = { 0, target_chars.length };
        return true;
      }

      bool allow_non_contiguous = !query.exact;
      int label_start = label_start_of (target_chars);
      bool prefer_label = !query.contains_separator || label_start == 0;

      if (prefer_label) {
        var label = target_chars[label_start : target_chars.length];
        var label_lower = target_lower_chars[label_start : target_lower_chars.length];
        int[] positions;
        int label_score = score_fuzzy (label, label_lower, query.chars, query.chars_lower, allow_non_contiguous, out positions);
        if (label_score > 0) {
          if (starts_with_at (label_lower, query.chars_lower, 0)) {
            int prefix_length_boost = (query.chars_lower.length * 100 + label.length / 2) / label.length;
            score = LABEL_PREFIX_SCORE + prefix_length_boost + label_score;
            ranges = { label_start, label_start + query.chars_lower.length };
          } else {
            score = LABEL_SCORE + label_score;
            ranges = positions_to_ranges (positions, label_start);
          }
          return true;
        }
      }

      if (label_start > 0) {
        int[] positions;
        int full_score = score_fuzzy (target_chars, target_lower_chars, query.chars, query.chars_lower, allow_non_contiguous, out positions);
        if (full_score > 0) {
          score = full_score;
          ranges = positions_to_ranges (positions, 0);
          return true;
        }
      }

      return false;
    }

    internal static unichar[] to_chars (string text) {
      var result = new unichar[text.char_count ()];
      int index = 0;
      int i = 0;
      unichar c;
      while (text.get_next_char (ref index, out c)) {
        result[i++] = c;
      }
      return result;
    }

    private static int label_start_of (unichar[] chars) {
      for (int i = chars.length - 1; i >= 0; i--) {
        if (chars[i] == '/') {
          return i + 1;
        }
      }
      return 0;
    }

    private static bool starts_with_at (unichar[] target_lower, unichar[] query_lower, int at) {
      if (at + query_lower.length > target_lower.length) {
        return false;
      }
      for (int i = 0; i < query_lower.length; i++) {
        if (!considered_equal (query_lower[i], target_lower[at + i])) {
          return false;
        }
      }
      return true;
    }

    /** Merges adjacent matched positions into [start, end) ranges, shifted by `offset` back into the full text. */
    private static int[] positions_to_ranges (int[] positions, int offset) {
      int[] ranges = {};
      foreach (int position in positions) {
        int absolute = position + offset;
        if (ranges.length > 0 && ranges[ranges.length - 1] == absolute) {
          ranges[ranges.length - 1] = absolute + 1;
        } else {
          ranges += absolute;
          ranges += absolute + 1;
        }
      }
      return ranges;
    }

    /**
     * The scoring matrix itself: for query[qi] against target[ti], a
     * cell either extends the diagonal (the characters match and that
     * beats the running best to the left) or inherits the left cell.
     * Positions are read back from the bottom-right corner.
     */
    private static int score_fuzzy (unichar[] target, unichar[] target_lower, unichar[] query, unichar[] query_lower, bool allow_non_contiguous, out int[] positions) {
      positions = {};
      int target_length = target.length;
      int query_length = query.length;
      if (target_length == 0 || query_length == 0 || target_length < query_length) {
        return 0;
      }

      var scores = new int[query_length * target_length];
      var matches = new int[query_length * target_length];

      for (int qi = 0; qi < query_length; qi++) {
        int row = qi * target_length;
        int previous_row = row - target_length;
        bool has_previous_row = qi > 0;

        for (int ti = 0; ti < target_length; ti++) {
          bool has_left = ti > 0;
          int current = row + ti;
          int left_score = has_left ? scores[current - 1] : 0;
          int diagonal_score = has_previous_row && has_left ? scores[previous_row + ti - 1] : 0;
          int sequence_length = has_previous_row && has_left ? matches[previous_row + ti - 1] : 0;

          int char_score = 0;
          if (diagonal_score > 0 || !has_previous_row) {
            char_score = compute_char_score (query[qi], query_lower[qi], target, target_lower, ti, sequence_length);
          }

          bool extends_diagonal = char_score > 0 && diagonal_score + char_score >= left_score;
          if (extends_diagonal && (allow_non_contiguous || has_previous_row || starts_with_at (target_lower, query_lower, ti))) {
            matches[current] = sequence_length + 1;
            scores[current] = diagonal_score + char_score;
          } else {
            matches[current] = 0;
            scores[current] = left_score;
          }
        }
      }

      int[] reversed = {};
      int qi_back = query_length - 1;
      int ti_back = target_length - 1;
      while (qi_back >= 0 && ti_back >= 0) {
        if (matches[qi_back * target_length + ti_back] == 0) {
          ti_back--;
        } else {
          reversed += ti_back;
          qi_back--;
          ti_back--;
        }
      }
      positions = new int[reversed.length];
      for (int i = 0; i < reversed.length; i++) {
        positions[i] = reversed[reversed.length - 1 - i];
      }

      return scores[query_length * target_length - 1];
    }

    private static int compute_char_score (unichar query_char, unichar query_lower_char, unichar[] target, unichar[] target_lower, int target_index, int sequence_length) {
      if (!considered_equal (query_lower_char, target_lower[target_index])) {
        return 0;
      }

      int score = 1;
      if (sequence_length > 0) {
        score += int.min (sequence_length, 3) * 6 + int.max (0, sequence_length - 3) * 3;
      }
      if (query_char == target[target_index]) {
        score += 1;
      }
      if (target_index == 0) {
        score += 8;
      } else {
        int separator_bonus = separator_bonus_of (target[target_index - 1]);
        if (separator_bonus > 0) {
          score += separator_bonus;
        } else if (target[target_index].isupper () && sequence_length == 0) {
          score += 2;
        }
      }
      return score;
    }

    private static bool considered_equal (unichar a, unichar b) {
      if (a == b) {
        return true;
      }
      return (a == '/' || a == '\\') && (b == '/' || b == '\\');
    }

    private static int separator_bonus_of (unichar c) {
      switch (c) {
        case '/':
        case '\\':
          return 5;
        case '_':
        case '-':
        case '.':
        case ' ':
        case '\'':
        case '"':
        case ':':
          return 4;
        default:
          return 0;
      }
    }
  }
}
