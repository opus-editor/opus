namespace Syntax {
  /** A run of text and the style to paint it with. Rows and byte columns, the coordinates tree-sitter works in. */
  public struct HighlightSpan {
    public uint32 start_row;
    public uint32 start_column;
    public uint32 end_row;
    public uint32 end_column;
    /** Owned by the LoadedLanguage the span came from. */
    public unowned string style;
  }

  private class Capture {
    public TreeSitter.Point start;
    public TreeSitter.Point end;
    public int depth;
    public uint16 pattern;
    public unowned string style;
  }

  /**
   * Turns the captures of highlights queries into the spans to paint.
   * Captures overlap freely — a whole call expression, the function
   * name inside it, a keyword matched by two patterns, a script inside
   * the HTML string that holds it — where painting needs exactly one
   * style per character. An injected language wins over the one it
   * sits in; within a language the rule is Helix's: the innermost
   * capture wins, and between two captures of the same node, the
   * pattern written later in the query.
   */
  internal class HighlightCollector {
    private TreeSitter.Point range_start;
    private TreeSitter.Point range_end;
    private unowned NodeTextFunc node_text;
    private GenericArray<Capture> captures = new GenericArray<Capture> ();

    /** Collects what intersects rows `first_row` to `last_row` inclusive, clipped to them. */
    public HighlightCollector (uint32 first_row, uint32 last_row, NodeTextFunc node_text) {
      range_start = { first_row, 0 };
      range_end = { last_row + 1, 0 };
      this.node_text = node_text;
    }

    /**
     * Adds one parsed layer. `ranges` are the stretches of the text an
     * injected layer was parsed over — empty for the document's own
     * language, which covers everything. A node of an injected layer
     * can reach across the gaps between them (a Ruby `if … end`
     * wrapped around ERB's HTML), so its captures are cut down to the
     * ranges.
     */
    public void add_layer (LoadedLanguage language, TreeSitter.Tree tree, TreeSitter.Range[] ranges, int depth) {
      var cursor = new TreeSitter.QueryCursor ();
      cursor.set_point_range (range_start, range_end);
      cursor.exec (language.highlights, tree.root_node ());

      TreeSitter.QueryMatch match;
      while (cursor.next_match (out match)) {
        if (language.highlight_predicates.accepts (match, node_text)) {
          add_match (language, match, ranges, depth);
        }
      }
    }

    /** In document order, never overlapping. */
    public HighlightSpan[] spans () {
      return flatten ();
    }

    private void add_match (LoadedLanguage language, TreeSitter.QueryMatch match, TreeSitter.Range[] ranges, int depth) {
      foreach (var query_capture in match.captures) {
        unowned string? style = language.highlight_styles[query_capture.index];
        if (style == null) {
          continue;
        }
        var start = later (query_capture.node.start_point (), range_start);
        var end = earlier (query_capture.node.end_point (), range_end);
        if (ranges.length == 0) {
          add_capture (start, end, depth, match.pattern_index, style);
          continue;
        }
        foreach (var range in ranges) {
          add_capture (later (start, range.start_point), earlier (end, range.end_point), depth, match.pattern_index, style);
        }
      }
    }

    private void add_capture (TreeSitter.Point start, TreeSitter.Point end, int depth, uint16 pattern, string style) {
      if (compare (start, end) >= 0) {
        return;
      }
      var capture = new Capture ();
      capture.start = start;
      capture.end = end;
      capture.depth = depth;
      capture.pattern = pattern;
      capture.style = style;
      captures.add (capture);
    }

    /**
     * A sweep over every capture boundary in document order, keeping
     * the captures open at the current position: each stretch between
     * two boundaries is painted with the winner among them. Walking
     * the captures once by start and once by end yields the boundaries
     * already sorted.
     */
    private HighlightSpan[] flatten () {
      var by_start = captures.copy ((capture) => capture);
      var by_end = captures.copy ((capture) => capture);
      by_start.sort ((a, b) => compare (a.start, b.start));
      by_end.sort ((a, b) => compare (a.end, b.end));

      HighlightSpan[] spans = {};
      var open = new GenericArray<Capture> ();
      TreeSitter.Point from = { 0, 0 };
      int started = 0;
      int ended = 0;
      while (ended < by_end.length) {
        var boundary = by_end[ended].end;
        if (started < by_start.length) {
          boundary = earlier (boundary, by_start[started].start);
        }

        var winner = winner_of (open);
        if (winner != null && compare (from, boundary) < 0) {
          spans += HighlightSpan () {
            start_row = from.row,
            start_column = from.column,
            end_row = boundary.row,
            end_column = boundary.column,
            style = winner.style,
          };
        }

        while (ended < by_end.length && compare (by_end[ended].end, boundary) == 0) {
          open.remove (by_end[ended]);
          ended++;
        }
        while (started < by_start.length && compare (by_start[started].start, boundary) == 0) {
          open.add (by_start[started]);
          started++;
        }
        from = boundary;
      }
      return spans;
    }

    private static Capture? winner_of (GenericArray<Capture> open) {
      Capture? winner = null;
      foreach (var capture in open) {
        if (winner == null || beats (capture, winner)) {
          winner = capture;
        }
      }
      return winner;
    }

    /** Within one layer captures are nodes of one tree, so two that overlap are nested: the one starting later, or ending sooner, is the inner one. */
    private static bool beats (Capture challenger, Capture holder) {
      if (challenger.depth != holder.depth) {
        return challenger.depth > holder.depth;
      }
      int by_start = compare (challenger.start, holder.start);
      if (by_start != 0) {
        return by_start > 0;
      }
      int by_end = compare (challenger.end, holder.end);
      if (by_end != 0) {
        return by_end < 0;
      }
      return challenger.pattern >= holder.pattern;
    }

    internal static int compare (TreeSitter.Point a, TreeSitter.Point b) {
      if (a.row != b.row) {
        return a.row < b.row ? -1 : 1;
      }
      if (a.column != b.column) {
        return a.column < b.column ? -1 : 1;
      }
      return 0;
    }

    private static TreeSitter.Point later (TreeSitter.Point a, TreeSitter.Point b) {
      return compare (a, b) >= 0 ? a : b;
    }

    private static TreeSitter.Point earlier (TreeSitter.Point a, TreeSitter.Point b) {
      return compare (a, b) <= 0 ? a : b;
    }
  }
}
