namespace CommandBar {
  /**
   * What the bar says under an empty input when it was opened with
   * nothing typed: what typing does, and the prefixes that lead to the
   * other lists. Written once, for the two providers that can be on
   * duty then — the file search, and its stand-in with no folder.
   */
  namespace PrefixHint {
    /** `without_prefix` is the line for typing with no prefix at all, the only one that depends on who shows the hint. */
    public string text (string without_prefix) {
      return string.joinv ("\n", {
        without_prefix,
        _(": Go to line"),
        _("# Go to symbol"),
        _("> Run commands")
      });
    }
  }
}
