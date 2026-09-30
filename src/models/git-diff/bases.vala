namespace GitDiff {
  /** A path's base blob text for both diff sides. Either field null = no usable base for that side (untracked, no such blob, outside repo, conflicted). */
  public class Bases : Object {
    public string? head_text { get; construct; }
    public string? index_text { get; construct; }

    public Bases (string? head_text, string? index_text) {
      Object (head_text: head_text, index_text: index_text);
    }
  }
}
