namespace Syntax {
  /** The text a node covers — the one thing a predicate needs from whoever holds the document. */
  public delegate string NodeTextFunc (TreeSitter.Node node);

  private enum PredicateKind {
    EQ,
    MATCH,
    ANY_OF,
    // `(#is? local)` / `(#is-not? local)`: whether the node is a local
    // variable. Telling takes a locals query, which Opus doesn't read
    // yet, so a pattern conditioned on it either way never applies:
    // Ruby's "an identifier that isn't a local is a method call" would
    // otherwise paint every variable as one.
    LOCAL,
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
   * forms, `#is? local` and `#is-not? local`) and `#set!` properties
   * of one compiled query. tree-sitter
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

    /** Whether every predicate of `match`'s pattern holds. */
    public bool accepts (TreeSitter.QueryMatch match, NodeTextFunc node_text) {
      foreach (var predicate in predicates_by_pattern[match.pattern_index]) {
        if (predicate.kind == PredicateKind.LOCAL || holds (predicate, match, node_text) == predicate.negated) {
          return false;
        }
      }
      return true;
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
      if (name == "is?" || name == "is-not?") {
        predicates.add (local_assertion (name, arguments));
        return;
      }

      var predicate = new Predicate ();
      predicate.negated = name.has_prefix ("not-");
      var kind_name = predicate.negated ? name.substring (4) : name;

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
        default:
          throw new QueryError.INVALID ("unsupported predicate #%s", name);
      }
      predicates.add (predicate);
    }

    private static Predicate local_assertion (string name, GenericArray<PredicateArgument> arguments) throws QueryError {
      if (arguments.length != 2 || arguments[1].is_capture || arguments[1].text != "local") {
        throw new QueryError.INVALID ("#%s only knows the property \"local\"", name);
      }
      var predicate = new Predicate ();
      predicate.kind = PredicateKind.LOCAL;
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
