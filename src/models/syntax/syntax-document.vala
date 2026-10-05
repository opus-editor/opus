namespace Syntax {
  private class Layer {
    public LoadedLanguage language;
    public TreeSitter.Tree tree;
    // Empty for the document's own language, which covers everything.
    public TreeSitter.Range[] ranges = {};
    public int depth;
  }

  /**
   * The syntax trees of one text, kept current as the text changes,
   * and the highlight spans read off them. One tree for the text's own
   * language, plus one per language injected into it — the script and
   * the style sheet of an HTML page, and whatever those embed in turn.
   */
  public class SyntaxDocument : Object {
    // HTML in Markdown, a script in that HTML, a template string in
    // that script: real nesting stops about there, and a query that
    // injects a language into itself wouldn't stop at all.
    private const int MAX_INJECTION_DEPTH = 4;

    private LoadedLanguage language;
    private Languages? languages;
    private TreeSitter.Parser parser = new TreeSitter.Parser ();
    private GenericArray<Layer> layers = new GenericArray<Layer> ();
    private string text = "";

    /** `languages` resolves the languages `language` injects; without it the document is parsed as `language` alone. */
    public SyntaxDocument (LoadedLanguage language, Languages? languages = null) {
      this.language = language;
      this.languages = languages;
    }

    /**
     * Brings the trees in line with `new_text`. Takes the whole text
     * rather than a list of edits: what changed is worked out as the
     * one stretch between the unchanged start and the unchanged end,
     * which costs a scan of the text but makes a hundred simultaneous
     * cursors exactly as cheap as one keystroke, and can't drift out of
     * sync with the buffer the way replayed edits can.
     */
    public void set_text (string new_text) {
      var previous = layers;
      if (previous.length > 0) {
        var edit = edit_between (text, new_text);
        foreach (var layer in previous) {
          layer.tree.edit (edit);
        }
      }
      text = new_text;

      layers = new GenericArray<Layer> ();
      var reusable = by_extent (previous);
      var root = parse (language, {}, 0, reusable);
      if (root != null) {
        layers.add (root);
        inject_into (root, reusable);
      }
    }

    /**
     * The spans intersecting rows `first_row` to `last_row` inclusive,
     * clipped to them, in document order and never overlapping. Empty
     * before the first {@link set_text}.
     */
    public HighlightSpan[] highlights (uint32 first_row, uint32 last_row) {
      var collector = new HighlightCollector (first_row, last_row, node_text);
      foreach (var layer in layers) {
        collector.add_layer (layer.language, layer.tree, layer.ranges, layer.depth);
      }
      return collector.spans ();
    }

    private void inject_into (Layer host, HashTable<string, Layer> reusable) {
      if (languages == null || host.depth + 1 >= MAX_INJECTION_DEPTH) {
        return;
      }
      foreach (var injection in SyntaxInjections.find (host.language, host.tree, languages, node_text)) {
        var layer = parse (injection.language, injection.ranges, host.depth + 1, reusable);
        if (layer != null) {
          layers.add (layer);
          inject_into (layer, reusable);
        }
      }
    }

    /**
     * Parses `language` over `ranges` (the whole text when empty). The
     * previous parse's layer over the same extent, if there is one,
     * goes in as the old tree: already shifted by the edit, it lets
     * tree-sitter reuse everything the edit didn't touch — for a layer
     * the edit never reached, all of it.
     */
    private Layer? parse (LoadedLanguage layer_language, TreeSitter.Range[] ranges, int depth, HashTable<string, Layer> reusable) {
      // LoadedLanguage only exists for a grammar whose ABI GrammarLoader
      // already accepted, the one thing set_language() can refuse.
      parser.set_language (layer_language.grammar);
      parser.set_included_ranges (ranges.length == 0 ? null : ranges);

      var old = reusable.take (extent_key (layer_language, ranges));
      var tree = parser.parse_string (old == null ? null : old.tree, text, (uint32) text.length);
      if (tree == null) {
        return null;
      }

      var layer = new Layer ();
      layer.language = layer_language;
      layer.tree = (owned) tree;
      layer.ranges = ranges;
      layer.depth = depth;
      return layer;
    }

    /** The layers of the previous parse, findable by where they sit now that their trees have been shifted by the edit. */
    private static HashTable<string, Layer> by_extent (GenericArray<Layer> previous) {
      var table = new HashTable<string, Layer> (str_hash, str_equal);
      foreach (var layer in previous) {
        var ranges = layer.ranges.length == 0 ? layer.ranges : layer.tree.included_ranges ();
        table[extent_key (layer.language, ranges)] = layer;
      }
      return table;
    }

    /** Language, first byte, last byte and how many ranges: enough to pair a layer with its previous self, and a wrong pairing only costs the reuse — the old tree is a hint, never the result. */
    private static string extent_key (LoadedLanguage layer_language, TreeSitter.Range[] ranges) {
      if (ranges.length == 0) {
        return layer_language.package.name;
      }
      return "%s:%u:%u:%d".printf (layer_language.package.name, ranges[0].start_byte, ranges[ranges.length - 1].end_byte, ranges.length);
    }

    private string node_text (TreeSitter.Node node) {
      return text.substring (node.start_byte (), node.end_byte () - node.start_byte ());
    }

    private static TreeSitter.InputEdit edit_between (string old_text, string new_text) {
      uint32 old_length = (uint32) old_text.length;
      uint32 new_length = (uint32) new_text.length;
      uint32 prefix = common_prefix (old_text, old_length, new_text, new_length);
      uint32 suffix = common_suffix (old_text, old_length, new_text, new_length, prefix);

      var start_point = advance ({ 0, 0 }, old_text, 0, prefix);
      return TreeSitter.InputEdit () {
        start_byte = prefix,
        old_end_byte = old_length - suffix,
        new_end_byte = new_length - suffix,
        start_point = start_point,
        old_end_point = advance (start_point, old_text, prefix, old_length - suffix),
        new_end_point = advance (start_point, new_text, prefix, new_length - suffix),
      };
    }

    private static uint32 common_prefix (string a, uint32 a_length, string b, uint32 b_length) {
      uint32 limit = uint32.min (a_length, b_length);
      uint32 prefix = 0;
      while (prefix < limit && a[prefix] == b[prefix]) {
        prefix++;
      }
      // Two different characters can share their leading bytes; an edit
      // has to start on a character, not inside one.
      while (prefix > 0 && is_continuation_byte (a[prefix])) {
        prefix--;
      }
      return prefix;
    }

    /** Never reaches back into `prefix`: in "aa" -> "a" the one `a` left can't count as both the unchanged start and the unchanged end. */
    private static uint32 common_suffix (string a, uint32 a_length, string b, uint32 b_length, uint32 prefix) {
      uint32 limit = uint32.min (a_length, b_length) - prefix;
      uint32 suffix = 0;
      while (suffix < limit && a[a_length - suffix - 1] == b[b_length - suffix - 1]) {
        suffix++;
      }
      while (suffix > 0 && is_continuation_byte (a[a_length - suffix])) {
        suffix--;
      }
      return suffix;
    }

    private static bool is_continuation_byte (char byte) {
      return (byte & 0xC0) == 0x80;
    }

    /** `point`, which is where byte `from` of `text` sits, moved on to byte `to`. */
    private static TreeSitter.Point advance (TreeSitter.Point point, string text, uint32 from, uint32 to) {
      var result = point;
      for (uint32 i = from; i < to; i++) {
        if (text[i] == '\n') {
          result.row++;
          result.column = 0;
        } else {
          result.column++;
        }
      }
      return result;
    }
  }
}
