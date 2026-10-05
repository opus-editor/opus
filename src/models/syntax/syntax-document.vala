namespace Syntax {
  private class Layer {
    public LoadedLanguage language;
    public TreeSitter.Tree tree;
    // Empty for the document's own language, which covers everything.
    public TreeSitter.Range[] ranges = {};
    public int depth;
    // Resolved the first time the layer is highlighted, and good until
    // the next parse replaces the layer.
    public LocalReferences? locals;
  }

  /** What a halted parse reads from: the text, addressed by byte. */
  private struct ParseSource {
    public char* text;
    public uint32 length;
  }

  /**
   * The syntax trees of one text, kept current as the text changes,
   * and the highlight spans read off them. One tree for the text's own
   * language, plus one per language injected into it — the script and
   * the style sheet of an HTML page, and whatever those embed in turn.
   *
   * Only what has to be is parsed when the text changes: the text's
   * own language and the injections that gather text from all over it
   * (the Ruby of an ERB file). An injection that is a document of its
   * own — one `<script>`, one fenced code block — is parsed when the
   * rows it sits on are first asked for, so a file with a thousand of
   * them costs the few on screen.
   */
  public class SyntaxDocument : Object {
    // HTML in Markdown, a script in that HTML, a template string in
    // that script: real nesting stops about there, and a query that
    // injects a language into itself wouldn't stop at all.
    private const int MAX_INJECTION_DEPTH = 4;

    private LoadedLanguage language;
    private Languages? languages;
    private TreeSitter.Parser parser = new TreeSitter.Parser ();
    // Parsed with the text: its own language first, then the combined injections.
    private GenericArray<Layer> layers = new GenericArray<Layer> ();
    // Parsed on demand since the text last changed, by extent_key().
    private HashTable<string, Layer> on_demand = new HashTable<string, Layer> (str_hash, str_equal);
    // The on-demand layers of the text before, shifted by the edit:
    // old trees for the same injections when they are asked for again.
    private HashTable<string, Layer> on_demand_before = new HashTable<string, Layer> (str_hash, str_equal);
    // What the trees in `layers` are aligned to: already the new text
    // while a parse of it is still halted, and the trees merely
    // shifted to it.
    private string text = "";
    private bool halted = false;

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
     *
     * With a `budget_usec`, gives up once parsing has taken that long
     * and returns false: {@link resume} carries on from there. Until
     * it is done, {@link highlights} answers from the previous trees,
     * shifted to where the edit moved things. A negative budget parses
     * to the end.
     */
    public bool set_text (string new_text, int64 budget_usec = -1) {
      if (layers.length > 0) {
        var edit = edit_between (text, new_text);
        foreach (var layer in layers) {
          shift (layer, edit);
        }
        // Still unparsed layers of an even older text are of no more
        // use: only what was on screen just now is worth keeping.
        on_demand_before = new HashTable<string, Layer> (str_hash, str_equal);
        foreach (var layer in on_demand.get_values ()) {
          shift (layer, edit);
          on_demand_before[extent_key (layer.language, layer.ranges)] = layer;
        }
        on_demand = new HashTable<string, Layer> (str_hash, str_equal);
      }
      if (halted) {
        // The halted parse was of a text that no longer exists.
        parser.reset ();
        halted = false;
      }
      text = new_text;
      return resume (budget_usec);
    }

    private static void shift (Layer layer, TreeSitter.InputEdit edit) {
      layer.tree.edit (edit);
      // What it resolved before has moved with the edit.
      layer.locals = null;
      if (layer.ranges.length > 0) {
        layer.ranges = layer.tree.included_ranges ();
      }
    }

    /** Carries on a parse {@link set_text} or an earlier resume left halted; true once the trees are current. */
    public bool resume (int64 budget_usec = -1) {
      var root_tree = parse_root (budget_usec);
      if (root_tree == null) {
        halted = true;
        return false;
      }
      halted = false;

      var reusable = by_extent (layers);
      layers = new GenericArray<Layer> ();
      var root = new Layer ();
      root.language = language;
      root.tree = (owned) root_tree;
      layers.add (root);
      inject_combined_into (root, reusable);
      return true;
    }

    /**
     * The spans intersecting rows `first_row` to `last_row` inclusive,
     * clipped to them, in document order and never overlapping. Empty
     * before the first {@link set_text}.
     */
    public HighlightSpan[] highlights (uint32 first_row, uint32 last_row) {
      var collector = new HighlightCollector (first_row, last_row, node_text);
      // Grows as it is walked: each layer adds the ones injected into its visible rows.
      var visible = layers.copy ((layer) => layer);
      for (int i = 0; i < visible.length; i++) {
        var layer = visible[i];
        if (layer.locals == null && layer.language.locals != null) {
          layer.locals = SyntaxLocals.resolve (layer.language, layer.tree, node_text);
        }
        collector.add_layer (layer.language, layer.tree, layer.ranges, layer.depth, layer.locals);
        add_injected_in_rows (layer, first_row, last_row, visible);
      }
      return collector.spans ();
    }

    private void add_injected_in_rows (Layer host, uint32 first_row, uint32 last_row, GenericArray<Layer> visible) {
      if (languages == null || halted || host.depth + 1 >= MAX_INJECTION_DEPTH) {
        return;
      }
      foreach (var injection in SyntaxInjections.find_in_rows (host.language, host.tree, first_row, last_row, languages, node_text)) {
        var key = extent_key (injection.language, injection.ranges);
        var layer = on_demand[key];
        if (layer == null) {
          layer = parse (injection.language, injection.ranges, host.depth + 1, on_demand_before);
          if (layer == null) {
            continue;
          }
          on_demand[key] = layer;
        }
        visible.add (layer);
      }
    }

    private void inject_combined_into (Layer host, HashTable<string, Layer> reusable) {
      if (languages == null || host.depth + 1 >= MAX_INJECTION_DEPTH) {
        return;
      }
      foreach (var injection in SyntaxInjections.find_combined (host.language, host.tree, languages, node_text)) {
        var layer = parse (injection.language, injection.ranges, host.depth + 1, reusable);
        if (layer != null) {
          layers.add (layer);
          inject_combined_into (layer, reusable);
        }
      }
    }

    /**
     * The document's own language over the whole text — the one parse
     * long enough on a large file to be worth halting. Null when the
     * budget ran out first.
     */
    private TreeSitter.Tree? parse_root (int64 budget_usec) {
      // Not while halted: configuring the parser resets it, and the
      // parse would start over instead of carrying on.
      if (!halted) {
        parser.set_language (language.grammar);
        parser.set_included_ranges (null);
      }

      ParseSource source = { (char*) text, (uint32) text.length };
      int64 deadline = budget_usec < 0 ? int64.MAX : get_monotonic_time () + budget_usec;
      TreeSitter.Input input = { &source, read_source, TreeSitter.InputEncoding.UTF8, null };
      TreeSitter.ParseOptions options = { &deadline, past_deadline };
      unowned TreeSitter.Tree? old = layers.length > 0 ? layers[0].tree : null;
      return parser.parse_with_options (old, input, options);
    }

    private static unowned string read_source (void* payload, uint32 byte_index, TreeSitter.Point position, out uint32 bytes_read) {
      ParseSource* source = (ParseSource*) payload;
      uint32 from = uint32.min (byte_index, source->length);
      bytes_read = source->length - from;
      return (string) (source->text + from);
    }

    private static TreeSitter.CBool past_deadline (TreeSitter.ParseState* state) {
      return get_monotonic_time () > *((int64*) state->payload);
    }

    /**
     * Parses an injected `layer_language` over `ranges`. The
     * previous parse's layer over the same extent, if there is one,
     * goes in as the old tree: already shifted by the edit, it lets
     * tree-sitter reuse everything the edit didn't touch — for a layer
     * the edit never reached, all of it.
     */
    private Layer? parse (LoadedLanguage layer_language, TreeSitter.Range[] ranges, int depth, HashTable<string, Layer> reusable) {
      // LoadedLanguage only exists for a grammar whose ABI GrammarLoader
      // already accepted, the one thing set_language() can refuse.
      parser.set_language (layer_language.grammar);
      parser.set_included_ranges (ranges);

      var key = extent_key (layer_language, ranges);
      var old = reusable[key];
      // Each previous layer is the old tree of one new layer at most.
      reusable.remove (key);
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
        table[extent_key (layer.language, layer.ranges)] = layer;
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
