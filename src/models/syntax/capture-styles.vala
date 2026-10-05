namespace Syntax {
  /**
   * Maps a query's capture names onto the style keys a theme actually
   * defines. Captures are dotted and as specific as the query author
   * cared to be (`keyword.control.return`); a theme defines far fewer
   * keys, so a capture falls back one dotted segment at a time until a
   * key exists.
   */
  public class CaptureStyles : Object {
    private GenericSet<string> keys = new GenericSet<string> (str_hash, str_equal);

    public CaptureStyles (string[] style_keys) {
      foreach (unowned string key in style_keys) {
        keys.add (key);
      }
    }

    /** The most specific key that is `capture` itself or a dotted prefix of it — null when there is none, a capture left unstyled. */
    public string? resolve (string capture) {
      var candidate = capture;
      while (!keys.contains (candidate)) {
        int dot = candidate.last_index_of_char ('.');
        if (dot < 0) {
          return null;
        }
        candidate = candidate.substring (0, dot);
      }
      return candidate;
    }
  }
}
