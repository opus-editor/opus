namespace Syntax {
  /**
   * Maps a query's capture names onto the style keys a theme actually
   * defines. Captures are dotted and as specific as the query author
   * cared to be (`keyword.control.return`); a theme defines far fewer
   * keys, so a capture falls back one dotted segment at a time until a
   * key exists.
   *
   * A theme may also style a capture for one language only. Such a
   * style has a key of its own, {@link language_key}, and is looked
   * for first: what a theme says about a language outranks what it
   * says in general, however short the name it says it under.
   */
  public class CaptureStyles : Object {
    private const string LANGUAGE_SEPARATOR = ":";

    private GenericSet<string> keys = new GenericSet<string> (str_hash, str_equal);

    public CaptureStyles (string[] style_keys) {
      foreach (unowned string key in style_keys) {
        keys.add (key);
      }
    }

    /** The key of the style `capture` has in `language` alone. */
    public static string language_key (string language, string capture) {
      return language + LANGUAGE_SEPARATOR + capture;
    }

    /** Whether `language` can be part of a {@link language_key} that reads only one way. */
    public static bool can_have_styles (string language) {
      return language != "" && !language.contains (LANGUAGE_SEPARATOR);
    }

    /**
     * The most specific key that is `capture` itself or a dotted prefix
     * of it — among `language`'s own styles first, when one is given —
     * or null when there is none, a capture left unstyled.
     */
    public string? resolve (string capture, string? language = null) {
      if (language != null) {
        var own = longest_key (language + LANGUAGE_SEPARATOR, capture);
        if (own != null) {
          return own;
        }
      }
      return longest_key ("", capture);
    }

    // The prefix stays out of the walk: a language's name may have dots of its own.
    private string? longest_key (string prefix, string capture) {
      var candidate = capture;
      while (!keys.contains (prefix + candidate)) {
        int dot = candidate.last_index_of_char ('.');
        if (dot < 0) {
          return null;
        }
        candidate = candidate.substring (0, dot);
      }
      return prefix + candidate;
    }
  }
}
