namespace Syntax {
  public errordomain LanguageError {
    UNUSABLE,
    // Set apart from the rest: the one failure that building the grammar fixes.
    GRAMMAR_NOT_BUILT,
  }

  /**
   * A language package made ready to work with: its grammar loaded and
   * its highlights, injections, locals, indents and tags queries
   * compiled. Building one is the expensive step
   * — {@link Languages} does it once per language and shares it.
   */
  public class LoadedLanguage : Object {
    private const string LOCAL_DEFINITION_PREFIX = "local.definition.";
    private const string TAG_DEFINITION_PREFIX = "definition.";

    public LanguagePackage package { get; private set; }
    public unowned TreeSitter.Language grammar { get; private set; }
    public QueryPredicates highlight_predicates { get; private set; }

    internal TreeSitter.Query highlights;
    // Indexed by capture id. Every HighlightSpan points at one of these
    // without copying it, so they have to live as long as the language.
    internal string[] highlight_captures;
    // Indexed by capture id — null for a capture no style key covers.
    internal string?[] highlight_styles;
    // Indexed by capture id: whether the capture marks literal text, a
    // string or a comment. Known from the capture's own name, whatever
    // the theme makes of it.
    internal bool[] highlight_literal_captures;

    // Null for a language that embeds no other.
    internal TreeSitter.Query? injections;
    internal QueryPredicates? injection_predicates;
    // The ids of `@injection.content` and `@injection.language` in
    // `injections`; -1 when the query never uses the capture.
    internal int64 injection_content_capture = -1;
    internal int64 injection_language_capture = -1;
    // Whether any pattern sets `injection.combined` — the only kind
    // that can't be found by looking at just the rows on screen.
    internal bool has_combined_injections = false;

    // Null for a language with no locals query: nothing in it is ever a local.
    internal TreeSitter.Query? locals;
    internal QueryPredicates? local_predicates;
    // Indexed by the locals query's capture ids.
    internal LocalRole[] local_roles;

    // Null for a language with no indents query: Enter just carries the line's indentation on.
    internal TreeSitter.Query? indents;
    internal QueryPredicates? indent_predicates;
    // Indexed by the indents query's capture ids.
    internal IndentRole[] indent_roles;
    // Indexed by pattern: whether it set `scope` to `header`.
    internal bool[] indent_header_patterns;

    // Null for a language with no tags query: it has no list of symbols.
    internal TreeSitter.Query? tags;
    internal QueryPredicates? tag_predicates;
    // The id of `@name` in `tags`; -1 when the query never uses it.
    internal int64 tag_name_capture = -1;
    // Indexed by the tags query's capture ids: for `@definition.<kind>`, the kind.
    internal string?[] tag_kinds;

    /** Whether the package says where lines go: without an indents query, Enter only carries indentation on. */
    public bool indents_lines {
      get { return indents != null; }
    }

    private LoadedLanguage () {}

    /** Fails when `package` can't highlight: no grammar, no `highlights` query, or a query that doesn't compile. */
    public static LoadedLanguage load (LanguagePackage package, GrammarLoader grammars, QuerySource queries, CaptureStyles styles) throws LanguageError {
      if (package.grammar == null) {
        throw new LanguageError.UNUSABLE ("language \"%s\" has no grammar", package.name);
      }
      var highlights_source = queries.read (package.name, "highlights");
      if (highlights_source == null) {
        throw new LanguageError.UNUSABLE ("language \"%s\" has no highlights query", package.name);
      }

      var language = new LoadedLanguage ();
      language.package = package;
      try {
        language.grammar = grammars.load (package.grammar);
        language.highlights = QuerySource.compile (language.grammar, highlights_source);
        language.highlight_predicates = new QueryPredicates (language.highlights);
        language.read_capture_names ();
        language.find_literal_captures ();
      } catch (GrammarError e) {
        if (e is GrammarError.NOT_FOUND) {
          throw new LanguageError.GRAMMAR_NOT_BUILT ("%s", e.message);
        }
        throw new LanguageError.UNUSABLE ("%s", e.message);
      } catch (QueryError e) {
        throw new LanguageError.UNUSABLE ("language \"%s\", highlights query: %s", package.name, e.message);
      }
      language.resolve_styles (styles);
      language.load_injections (queries.read (package.name, "injections"));
      language.load_locals (queries.read (package.name, "locals"));
      language.load_indents (queries.read (package.name, "indents"));
      language.load_tags (queries.read (package.name, "tags"));
      return language;
    }

    private void load_tags (string? source) throws LanguageError {
      if (source == null) {
        return;
      }
      try {
        tags = QuerySource.compile (grammar, source);
        tag_predicates = new QueryPredicates (tags);
      } catch (QueryError e) {
        throw new LanguageError.UNUSABLE ("language \"%s\", tags query: %s", package.name, e.message);
      }

      tag_kinds = new string?[tags.capture_count ()];
      for (uint32 id = 0; id < tag_kinds.length; id++) {
        uint32 length;
        unowned string name = tags.capture_name_for_id (id, out length);
        if (name == "name") {
          tag_name_capture = id;
        } else if (name.has_prefix (TAG_DEFINITION_PREFIX)) {
          tag_kinds[id] = name.substring (TAG_DEFINITION_PREFIX.length);
        }
      }
    }

    private void read_capture_names () {
      highlight_captures = new string[highlights.capture_count ()];
      for (uint32 id = 0; id < highlight_captures.length; id++) {
        uint32 length;
        highlight_captures[id] = highlights.capture_name_for_id (id, out length);
      }
    }

    private void find_literal_captures () {
      highlight_literal_captures = new bool[highlight_captures.length];
      for (uint32 id = 0; id < highlight_literal_captures.length; id++) {
        unowned string name = highlight_captures[id];
        highlight_literal_captures[id] = name == "string" || name.has_prefix ("string.")
          || name == "comment" || name.has_prefix ("comment.");
      }
    }

    private void load_indents (string? source) throws LanguageError {
      if (source == null) {
        return;
      }
      try {
        indents = QuerySource.compile (grammar, source);
        indent_predicates = new QueryPredicates (indents);
      } catch (QueryError e) {
        throw new LanguageError.UNUSABLE ("language \"%s\", indents query: %s", package.name, e.message);
      }

      indent_roles = new IndentRole[indents.capture_count ()];
      for (uint32 id = 0; id < indent_roles.length; id++) {
        uint32 length;
        indent_roles[id] = indent_role_of (indents.capture_name_for_id (id, out length));
      }
      indent_header_patterns = new bool[indents.pattern_count ()];
      for (uint32 pattern = 0; pattern < indent_header_patterns.length; pattern++) {
        indent_header_patterns[pattern] = indent_predicates.property (pattern, "scope") == "header";
      }
    }

    private static IndentRole indent_role_of (string capture_name) {
      switch (capture_name) {
        case "indent":
          return IndentRole.INDENT;
        case "indent.always":
          return IndentRole.INDENT_ALWAYS;
        case "outdent":
          return IndentRole.OUTDENT;
        case "outdent.always":
          return IndentRole.OUTDENT_ALWAYS;
        default:
          return IndentRole.NONE;
      }
    }

    private void load_locals (string? source) throws LanguageError {
      if (source == null) {
        return;
      }
      try {
        locals = QuerySource.compile (grammar, source);
        local_predicates = new QueryPredicates (locals);
      } catch (QueryError e) {
        throw new LanguageError.UNUSABLE ("language \"%s\", locals query: %s", package.name, e.message);
      }
      local_roles = new LocalRole[locals.capture_count ()];
      for (uint32 id = 0; id < local_roles.length; id++) {
        local_roles[id] = role_of (local_capture_name (id));
      }
    }

    private unowned string local_capture_name (uint32 id) {
      uint32 length;
      return locals.capture_name_for_id (id, out length);
    }

    private static LocalRole role_of (string capture_name) {
      if (capture_name == "local.scope") {
        return LocalRole.SCOPE;
      }
      if (capture_name == "local.reference") {
        return LocalRole.REFERENCE;
      }
      if (capture_name.has_prefix (LOCAL_DEFINITION_PREFIX)) {
        return LocalRole.DEFINITION;
      }
      return LocalRole.DISCARD;
    }

    private void load_injections (string? source) throws LanguageError {
      if (source == null) {
        return;
      }
      try {
        injections = QuerySource.compile (grammar, source);
        injection_predicates = new QueryPredicates (injections);
      } catch (QueryError e) {
        throw new LanguageError.UNUSABLE ("language \"%s\", injections query: %s", package.name, e.message);
      }
      for (uint32 pattern = 0; pattern < injections.pattern_count (); pattern++) {
        if (injection_predicates.property (pattern, "injection.combined") != null) {
          has_combined_injections = true;
        }
      }
      for (uint32 id = 0; id < injections.capture_count (); id++) {
        uint32 length;
        unowned string name = injections.capture_name_for_id (id, out length);
        if (name == "injection.content") {
          injection_content_capture = id;
        } else if (name == "injection.language") {
          injection_language_capture = id;
        }
      }
    }

    /**
     * Done once per theme, not per highlighted token: a query has a few
     * dozen captures, a file has thousands of tokens. Says whether a
     * capture moved between styled and unstyled — the one change that
     * can move a span's boundary or its winner (see Languages.set_style_keys).
     */
    internal bool resolve_styles (CaptureStyles styles) {
      var resolved = new string?[highlight_captures.length];
      for (uint32 id = 0; id < resolved.length; id++) {
        resolved[id] = styles.resolve (highlight_captures[id], package.name);
      }
      bool coverage_changed = highlight_styles != null && coverage_differs (highlight_styles, resolved);
      highlight_styles = resolved;
      return coverage_changed;
    }

    private static bool coverage_differs (string?[] before, string?[] after) {
      for (int id = 0; id < before.length; id++) {
        if ((before[id] == null) != (after[id] == null)) {
          return true;
        }
      }
      return false;
    }

  }
}
