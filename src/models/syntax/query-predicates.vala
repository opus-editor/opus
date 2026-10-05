namespace Syntax {
  /** The text a node covers — the one thing a predicate needs from whoever holds the document. */
  public delegate string NodeTextFunc (TreeSitter.Node node);

  /** Whether a node is a reference to a local variable, as a locals query resolved it. */
  public delegate bool NodeIsLocalFunc (TreeSitter.Node node);

  private enum PredicateKind {
    EQ,
    MATCH,
    ANY_OF,
    // `(#is? local)` / `(#is-not? local)`: whether what the pattern
    // captured is a reference to a local variable.
    LOCAL,
    // The three below are what indent queries ask: a node's kind, and
    // which lines nodes sit on.
    KIND_EQ,
    SAME_LINE,
    ONE_LINE,
  }

  private class Predicate : Object {
    public PredicateKind kind;
    public bool negated;
    public uint32 capture;
    /** EQ against another capture's text; -1 when it compares against `values` instead. */
    public int64 other_capture = -1;
    public string[] values = {};
    public Regex? regex;
  }

  private class PredicateArgument : Object {
    public bool is_capture;
    public uint32 capture;
    public string text = "";
  }

  /**
   * The predicates (`#eq?`, `#match?`, `#any-of?` and their `not-`
   * forms, `#is? local` and `#is-not? local`, and the `#kind-eq?`,
   * `#same-line?` and `#one-line?` of indent queries with theirs) and
   * `#set!` properties of one compiled query. `#strip!` and
   * `#select-adjacent!`, which tags queries use on documentation
   * comments, are accepted and do nothing. tree-sitter
   * itself only stores them: matching a pattern says nothing about
   * whether its predicates hold, so every match has to be put through
   * {@link accepts}.
   */
  public class QueryPredicates : Object {
    private GenericArray<GenericArray<Predicate>> predicates_by_pattern = new GenericArray<GenericArray<Predicate>> ();
    private GenericArray<HashTable<string, string>> properties_by_pattern = new GenericArray<HashTable<string, string>> ();

    /** Reads everything out of `query` up front — it isn't kept. A predicate this class doesn't implement is an error rather than silently true: a pattern would otherwise apply far wider than its author meant. */
    public QueryPredicates (TreeSitter.Query query) throws QueryError {
      for (uint32 pattern = 0; pattern < query.pattern_count (); pattern++) {
        var predicates = new GenericArray<Predicate> ();
        var properties = new HashTable<string, string> (str_hash, str_equal);
        read_pattern (query, pattern, predicates, properties);
        predicates_by_pattern.add (predicates);
        properties_by_pattern.add (properties);
      }
    }

    /**
     * Whether every predicate of `match`'s pattern holds. Without
     * `is_local`, no node is a local. `new_line_byte`, when not
     * negative, has the line predicates answer for the text as it
     * will be once a line break is inserted at that byte — see
     * {@link start_row}.
     */
    public bool accepts (TreeSitter.QueryMatch match, NodeTextFunc node_text, NodeIsLocalFunc? is_local = null, int64 new_line_byte = -1) {
      foreach (var predicate in predicates_by_pattern[match.pattern_index]) {
        if (!satisfied (predicate, match, node_text, is_local, new_line_byte)) {
          return false;
        }
      }
      return true;
    }

    /** The row `node` starts on — one further down when it starts at or after a line break about to be inserted at `new_line_byte`. */
    internal static uint32 start_row (TreeSitter.Node node, int64 new_line_byte) {
      uint32 row = node.start_point ().row;
      return new_line_byte >= 0 && node.start_byte () >= new_line_byte ? row + 1 : row;
    }

    /** The row `node` ends on — one further down when it reaches past the break. */
    internal static uint32 end_row (TreeSitter.Node node, int64 new_line_byte) {
      uint32 row = node.end_point ().row;
      return new_line_byte >= 0 && node.end_byte () > new_line_byte ? row + 1 : row;
    }

    private static bool satisfied (Predicate predicate, TreeSitter.QueryMatch match, NodeTextFunc node_text, NodeIsLocalFunc? is_local, int64 new_line_byte) {
      switch (predicate.kind) {
        case PredicateKind.LOCAL:
          return captures_a_local (match, is_local) != predicate.negated;
        case PredicateKind.KIND_EQ:
          return kind_matches (predicate, match);
        case PredicateKind.SAME_LINE:
          return lines_match (predicate, match, new_line_byte);
        case PredicateKind.ONE_LINE:
          return fits_one_line (predicate, match, new_line_byte);
        default:
          return holds (predicate, match, node_text) != predicate.negated;
      }
    }

    /** A capture the match didn't take has no kind to compare: `#not-kind-eq?` holds, `#kind-eq?` doesn't. */
    private static bool kind_matches (Predicate predicate, TreeSitter.QueryMatch match) {
      TreeSitter.Node node;
      if (!first_node (match, predicate.capture, out node)) {
        return predicate.negated;
      }
      return (node.type () == predicate.values[0]) != predicate.negated;
    }

    /** Needs both nodes to be there, negated or not — Helix's own reading. */
    private static bool lines_match (Predicate predicate, TreeSitter.QueryMatch match, int64 new_line_byte) {
      TreeSitter.Node first;
      if (!first_node (match, predicate.capture, out first)) {
        return false;
      }
      TreeSitter.Node second;
      if (!first_node (match, (uint32) predicate.other_capture, out second)) {
        return false;
      }
      return (start_row (first, new_line_byte) == start_row (second, new_line_byte)) != predicate.negated;
    }

    private static bool fits_one_line (Predicate predicate, TreeSitter.QueryMatch match, int64 new_line_byte) {
      TreeSitter.Node node;
      if (!first_node (match, predicate.capture, out node)) {
        return false;
      }
      return (start_row (node, new_line_byte) == end_row (node, new_line_byte)) != predicate.negated;
    }

    private static bool first_node (TreeSitter.QueryMatch match, uint32 capture_index, out TreeSitter.Node node) {
      foreach (var capture in match.captures) {
        if (capture.index == capture_index) {
          node = capture.node;
          return true;
        }
      }
      node = match.captures[0].node;
      return false;
    }

    private static bool captures_a_local (TreeSitter.QueryMatch match, NodeIsLocalFunc? is_local) {
      if (is_local == null) {
        return false;
      }
      foreach (var capture in match.captures) {
        if (is_local (capture.node)) {
          return true;
        }
      }
      return false;
    }

    /** What `(#set! key value)` gave pattern `pattern_index` — "" for a bare `(#set! key)`, null when it never set `key`. */
    public string? property (uint pattern_index, string key) {
      return properties_by_pattern[pattern_index][key];
    }

    private static void read_pattern (TreeSitter.Query query, uint32 pattern, GenericArray<Predicate> predicates, HashTable<string, string> properties) throws QueryError {
      var arguments = new GenericArray<PredicateArgument> ();
      foreach (var step in query.predicates_for_pattern (pattern)) {
        if (step.type != TreeSitter.QueryPredicateStepType.DONE) {
          arguments.add (argument_of (query, step));
          continue;
        }
        read_predicate (arguments, predicates, properties);
        arguments = new GenericArray<PredicateArgument> ();
      }
    }

    private static PredicateArgument argument_of (TreeSitter.Query query, TreeSitter.QueryPredicateStep step) {
      var argument = new PredicateArgument ();
      if (step.type == TreeSitter.QueryPredicateStepType.CAPTURE) {
        argument.is_capture = true;
        argument.capture = step.value_id;
        return argument;
      }
      uint32 length;
      argument.text = query.string_value_for_id (step.value_id, out length);
      return argument;
    }

    /** `arguments[0]` is the predicate's own name: tree-sitter guarantees a string there. */
    private static void read_predicate (GenericArray<PredicateArgument> arguments, GenericArray<Predicate> predicates, HashTable<string, string> properties) throws QueryError {
      var name = arguments[0].text;
      if (name == "set!") {
        read_property (arguments, properties);
        return;
      }
      if (name == "strip!" || name == "select-adjacent!") {
        // Both only shape the `@doc` of a tags query — the comment
        // above a definition — which nothing here reads.
        return;
      }
      if (name == "is?" || name == "is-not?") {
        predicates.add (local_assertion (name, arguments));
        return;
      }

      var predicate = new Predicate ();
      predicate.negated = name.has_prefix ("not-");
      var kind_name = predicate.negated ? name.substring (4) : name;

      if (kind_name == "same-line?" || kind_name == "one-line?") {
        read_line_predicate (name, kind_name, arguments, predicate);
        predicates.add (predicate);
        return;
      }

      if (arguments.length < 3 || !arguments[1].is_capture) {
        throw new QueryError.INVALID ("#%s needs a capture and at least one value", name);
      }
      predicate.capture = arguments[1].capture;

      switch (kind_name) {
        case "eq?":
          predicate.kind = PredicateKind.EQ;
          read_eq_operand (arguments[2], predicate);
          break;
        case "match?":
          predicate.kind = PredicateKind.MATCH;
          predicate.regex = compile_regex (name, arguments[2].text);
          break;
        case "any-of?":
          predicate.kind = PredicateKind.ANY_OF;
          predicate.values = texts_from (arguments, 2);
          break;
        case "kind-eq?":
          predicate.kind = PredicateKind.KIND_EQ;
          predicate.values = { arguments[2].text };
          break;
        default:
          throw new QueryError.INVALID ("unsupported predicate #%s", name);
      }
      predicates.add (predicate);
    }

    /** `(#same-line? @a @b)` and `(#one-line? @a)`: captures only, where every other predicate ends in a value. */
    private static void read_line_predicate (string name, string kind_name, GenericArray<PredicateArgument> arguments, Predicate predicate) throws QueryError {
      int captures_wanted = kind_name == "same-line?" ? 2 : 1;
      if (arguments.length != captures_wanted + 1) {
        throw new QueryError.INVALID ("#%s takes %d capture(s)", name, captures_wanted);
      }
      for (int i = 1; i < arguments.length; i++) {
        if (!arguments[i].is_capture) {
          throw new QueryError.INVALID ("#%s takes %d capture(s)", name, captures_wanted);
        }
      }
      predicate.capture = arguments[1].capture;
      if (captures_wanted == 2) {
        predicate.kind = PredicateKind.SAME_LINE;
        predicate.other_capture = arguments[2].capture;
      } else {
        predicate.kind = PredicateKind.ONE_LINE;
      }
    }

    private static Predicate local_assertion (string name, GenericArray<PredicateArgument> arguments) throws QueryError {
      if (arguments.length != 2 || arguments[1].is_capture || arguments[1].text != "local") {
        throw new QueryError.INVALID ("#%s only knows the property \"local\"", name);
      }
      var predicate = new Predicate ();
      predicate.kind = PredicateKind.LOCAL;
      predicate.negated = name == "is-not?";
      return predicate;
    }

    private static void read_property (GenericArray<PredicateArgument> arguments, HashTable<string, string> properties) throws QueryError {
      if (arguments.length < 2 || arguments[1].is_capture) {
        throw new QueryError.INVALID ("#set! needs a property name");
      }
      properties[arguments[1].text] = arguments.length > 2 ? arguments[2].text : "";
    }

    private static void read_eq_operand (PredicateArgument operand, Predicate predicate) {
      if (operand.is_capture) {
        predicate.other_capture = operand.capture;
        return;
      }
      predicate.values = { operand.text };
    }

    private static Regex compile_regex (string predicate_name, string pattern) throws QueryError {
      try {
        return new Regex (pattern);
      } catch (RegexError e) {
        throw new QueryError.INVALID ("#%s: %s", predicate_name, e.message);
      }
    }

    private static string[] texts_from (GenericArray<PredicateArgument> arguments, int first) {
      string[] texts = {};
      for (int i = first; i < arguments.length; i++) {
        texts += arguments[i].text;
      }
      return texts;
    }

    /**
     * Before negation. Holds when every node the capture took passes —
     * so vacuously for a capture this match didn't take at all, the
     * same reading tree-sitter's own highlighter gives an optional
     * capture.
     */
    private static bool holds (Predicate predicate, TreeSitter.QueryMatch match, NodeTextFunc node_text) {
      string? other_text = null;
      if (predicate.other_capture >= 0) {
        other_text = first_text (match, (uint32) predicate.other_capture, node_text);
        if (other_text == null) {
          return true;
        }
      }

      foreach (var capture in match.captures) {
        if (capture.index == predicate.capture && !passes (predicate, node_text (capture.node), other_text)) {
          return false;
        }
      }
      return true;
    }

    private static bool passes (Predicate predicate, string text, string? other_text) {
      switch (predicate.kind) {
        case PredicateKind.MATCH:
          return predicate.regex.match (text);
        case PredicateKind.EQ:
          return text == (other_text ?? predicate.values[0]);
        default:
          return text in predicate.values;
      }
    }

    private static string? first_text (TreeSitter.QueryMatch match, uint32 capture_index, NodeTextFunc node_text) {
      foreach (var capture in match.captures) {
        if (capture.index == capture_index) {
          return node_text (capture.node);
        }
      }
      return null;
    }
  }
}
