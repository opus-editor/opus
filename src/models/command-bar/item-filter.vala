namespace CommandBar {
  /**
   * Narrows a short, fixed list of rows by what was typed — the fuzzy
   * match the file search uses, for the providers whose rows are known
   * up front (commands, languages) rather than searched for.
   */
  namespace ItemFilter {
    private class Scored {
      public Item item;
      public int score;
    }

    /**
     * The rows of `all` whose label matches `filter`, best match first,
     * each a copy carrying the matched stretches as highlights. With
     * nothing typed, every row as it came, in its own order.
     */
    public GenericArray<Item> narrow (GenericArray<Item> all, string filter) {
      var query = new Opus.FuzzyFinder.Query (filter);
      if (query.is_empty) {
        return all.copy ((item) => item);
      }

      var matches = new GenericArray<Scored> ();
      foreach (var item in all) {
        int score;
        int[] ranges;
        if (!Opus.FuzzyFinder.Scorer.score (item.label, item.label.casefold (), query, out score, out ranges)) {
          continue;
        }
        var match = new Scored ();
        match.item = highlighted (item, ranges);
        match.score = score;
        matches.add (match);
      }
      // GenericArray's sort isn't stable: ties are settled by label, so the order is the same every time.
      matches.sort ((a, b) => a.score != b.score ? b.score - a.score : strcmp (a.item.label, b.item.label));

      var narrowed = new GenericArray<Item> ();
      foreach (var match in matches) {
        narrowed.add (match.item);
      }
      return narrowed;
    }

    private Item highlighted (Item item, int[] ranges) {
      var copy = new Item (item.id, item.label);
      copy.description = item.description;
      copy.label_highlights = ranges;
      return copy;
    }
  }
}
