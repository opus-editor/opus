namespace Syntax {
  /**
   * A definition found in a text — a class, a method, a heading: what
   * a "go to symbol" list is made of. Lines are 1-based and the column
   * counts characters, the coordinates the editor is asked to go to.
   */
  public class Symbol : Object {
    public string name { get; private set; }
    /** What kind of thing it is, as its language's query calls it: `method`, `class`, `section`… */
    public string kind { get; private set; }
    /** The name of the definition this one sits directly inside — "" at the top level. */
    public string container { get; internal set; default = ""; }
    /** Where the name is. */
    public int line { get; private set; }
    public int column { get; private set; }
    /** The lines the whole definition spans: a cursor on any of them is "in" it. */
    public int first_line { get; private set; }
    public int last_line { get; private set; }

    public Symbol (string name, string kind, int line, int column, int first_line, int last_line, string container = "") {
      this.name = name;
      this.kind = kind;
      this.line = line;
      this.column = column;
      this.first_line = first_line;
      this.last_line = last_line;
      this.container = container;
    }
  }

  private class FoundSymbol {
    public Symbol symbol;
    public uint32 start;
    public uint32 end;
  }

  /**
   * Reads a language's tags query — tree-sitter's own convention for
   * code navigation, as Helix uses it: `@definition.<kind>` on the
   * whole definition, `@name` on its name. Anything else a pattern
   * captures (`@reference.*`, `@doc`) is of no use here.
   *
   * What a definition belongs to isn't in the query at all: it is the
   * innermost other definition whose node contains it.
   */
  namespace SyntaxSymbols {
    /** Every definition in `tree`, in the order they appear in `text`. */
    internal Symbol[] collect (LoadedLanguage language, TreeSitter.Tree tree, string text, NodeTextFunc node_text) {
      var found = new GenericArray<FoundSymbol> ();
      var seen = new GenericSet<string> (str_hash, str_equal);
      var cursor = new TreeSitter.QueryCursor ();
      cursor.exec (language.tags, tree.root_node ());

      TreeSitter.QueryMatch match;
      while (cursor.next_match (out match)) {
        if (!language.tag_predicates.accepts (match, node_text)) {
          continue;
        }
        var symbol = symbol_of (language, match, text, node_text);
        // Two patterns may capture the same name; it is still one symbol.
        if (symbol != null && seen.add ("%d:%d".printf (symbol.symbol.line, symbol.symbol.column))) {
          found.add (symbol);
        }
      }

      // Outermost first among definitions starting together, so containers are met before what they contain.
      found.sort ((a, b) => a.start != b.start ? (a.start < b.start ? -1 : 1) : (a.end > b.end ? -1 : (a.end < b.end ? 1 : 0)));
      name_containers (found);

      Symbol[] symbols = {};
      foreach (var entry in found) {
        symbols += entry.symbol;
      }
      return symbols;
    }

    /** Null for a match with no definition or no name to show — a reference, say. */
    private FoundSymbol? symbol_of (LoadedLanguage language, TreeSitter.QueryMatch match, string text, NodeTextFunc node_text) {
      string? kind = null;
      bool has_definition = false;
      bool has_name = false;
      TreeSitter.Node definition = match.captures[0].node;
      TreeSitter.Node name = match.captures[0].node;
      foreach (var capture in match.captures) {
        if (language.tag_kinds[capture.index] != null) {
          kind = language.tag_kinds[capture.index];
          definition = capture.node;
          has_definition = true;
        } else if (capture.index == language.tag_name_capture) {
          name = capture.node;
          has_name = true;
        }
      }
      if (!has_definition || !has_name) {
        return null;
      }

      var found = new FoundSymbol ();
      found.symbol = new Symbol (
        node_text (name).strip (),
        kind,
        (int) name.start_point ().row + 1,
        character_column (text, name),
        (int) definition.start_point ().row + 1,
        (int) definition.end_point ().row + 1
      );
      found.start = definition.start_byte ();
      found.end = definition.end_byte ();
      return found;
    }

    /** tree-sitter counts a column in bytes; the editor counts characters. */
    private int character_column (string text, TreeSitter.Node node) {
      uint32 start = node.start_byte ();
      uint32 line_start = start - node.start_point ().column;
      return text.substring (line_start, start - line_start).char_count ();
    }

    /** A sweep in document order, keeping the definitions still open: the innermost of them contains the one just reached. */
    private void name_containers (GenericArray<FoundSymbol> found) {
      var open = new GenericArray<FoundSymbol> ();
      foreach (var entry in found) {
        while (open.length > 0 && open[open.length - 1].end <= entry.start) {
          open.remove_index (open.length - 1);
        }
        if (open.length > 0) {
          entry.symbol.container = open[open.length - 1].symbol.name;
        }
        open.add (entry);
      }
    }
  }
}
