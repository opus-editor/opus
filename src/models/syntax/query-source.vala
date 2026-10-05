namespace Syntax {
  public errordomain QueryError {
    INVALID,
  }

  /** Reads a language's query files and compiles them against its grammar. */
  public class QuerySource : Object {
    // Helix's own modeline: `; inherits: ecma,_typescript`.
    private const string INHERITS_PATTERN = "^;+\\s*inherits\\s*:?\\s*([a-z_,()-]+)\\s*$";

    private LanguageRegistry registry;
    private Regex inherits_regex;

    public QuerySource (LanguageRegistry registry) {
      this.registry = registry;
      try {
        inherits_regex = new Regex (INHERITS_PATTERN);
      } catch (RegexError e) {
        error ("unreachable: the inherits pattern failed to compile: %s", e.message);
      }
    }

    /**
     * `language`'s `queries/<query_name>.scm`, each `; inherits:` line
     * replaced by the same-named query of the languages it lists — in
     * place, so what follows the line overrides what it brought in (the
     * last matching pattern wins). Null when the language has no such
     * file.
     */
    public string? read (string language, string query_name) {
      return read_expanding (language, query_name, new GenericSet<string> (str_hash, str_equal));
    }

    public static TreeSitter.Query compile (TreeSitter.Language language, string source) throws QueryError {
      uint32 error_offset;
      TreeSitter.QueryError error_type;
      var query = TreeSitter.Query.create (language, source, (uint32) source.length, out error_offset, out error_type);
      if (query == null) {
        throw new QueryError.INVALID ("line %d: %s", line_of (source, error_offset), describe (error_type));
      }
      return (owned) query;
    }

    /** `visiting` holds the languages on the current inheritance chain, so a cycle ends instead of recursing forever. */
    private string? read_expanding (string language, string query_name, GenericSet<string> visiting) {
      var package = registry.by_name (language);
      var path = package == null ? null : package.query_path (query_name);
      if (path == null || visiting.contains (language)) {
        return null;
      }

      string text;
      try {
        FileUtils.get_contents (path, out text);
      } catch (FileError e) {
        Logger.warn ("couldn't read %s: %s".printf (path, e.message));
        return null;
      }

      visiting.add (language);
      var expanded = expand_inherits (text, query_name, visiting);
      visiting.remove (language);
      return expanded;
    }

    private string expand_inherits (string text, string query_name, GenericSet<string> visiting) {
      var lines = text.split ("\n");
      for (int i = 0; i < lines.length; i++) {
        MatchInfo info;
        if (inherits_regex.match (lines[i], 0, out info)) {
          lines[i] = inherited_text (info.fetch (1), query_name, visiting);
        }
      }
      return string.joinv ("\n", lines);
    }

    private string inherited_text (string languages, string query_name, GenericSet<string> visiting) {
      var text = new StringBuilder ();
      foreach (unowned string language in languages.split (",")) {
        text.append (read_expanding (language.strip (), query_name, visiting) ?? "");
        text.append_c ('\n');
      }
      return text.str;
    }

    private static int line_of (string source, uint32 byte_offset) {
      int line = 1;
      for (uint32 i = 0; i < byte_offset && i < source.length; i++) {
        if (source[i] == '\n') {
          line++;
        }
      }
      return line;
    }

    private static string describe (TreeSitter.QueryError error_type) {
      switch (error_type) {
        case TreeSitter.QueryError.NODE_TYPE:
          return "the grammar has no such node type";
        case TreeSitter.QueryError.FIELD:
          return "the grammar has no such field";
        case TreeSitter.QueryError.CAPTURE:
          return "a predicate names a capture the pattern doesn't have";
        case TreeSitter.QueryError.STRUCTURE:
          return "the grammar can never produce this pattern";
        case TreeSitter.QueryError.LANGUAGE:
          return "the grammar can't be queried";
        default:
          return "syntax error";
      }
    }
  }
}
