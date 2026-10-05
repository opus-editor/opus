namespace Syntax {
  public errordomain LanguageError {
    UNUSABLE,
  }

  /**
   * A language package made ready to work with: its grammar loaded and
   * its highlights and injections queries compiled. Building one is the expensive step
   * — {@link Languages} does it once per language and shares it.
   */
  public class LoadedLanguage : Object {
    public LanguagePackage package { get; private set; }
    public unowned TreeSitter.Language grammar { get; private set; }
    public QueryPredicates highlight_predicates { get; private set; }

    internal TreeSitter.Query highlights;
    // Indexed by capture id — null for a capture no style key covers.
    internal string?[] highlight_styles;

    // Null for a language that embeds no other.
    internal TreeSitter.Query? injections;
    internal QueryPredicates? injection_predicates;
    // The ids of `@injection.content` and `@injection.language` in
    // `injections`; -1 when the query never uses the capture.
    internal int64 injection_content_capture = -1;
    internal int64 injection_language_capture = -1;

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
      } catch (GrammarError e) {
        throw new LanguageError.UNUSABLE ("%s", e.message);
      } catch (QueryError e) {
        throw new LanguageError.UNUSABLE ("language \"%s\", highlights query: %s", package.name, e.message);
      }
      language.resolve_styles (styles);
      language.load_injections (queries.read (package.name, "injections"));
      return language;
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

    /** Done once per theme, not per highlighted token: a query has a few dozen captures, a file has thousands of tokens. */
    internal void resolve_styles (CaptureStyles styles) {
      var resolved = new string?[highlights.capture_count ()];
      for (uint32 id = 0; id < resolved.length; id++) {
        uint32 length;
        resolved[id] = styles.resolve (highlights.capture_name_for_id (id, out length));
      }
      highlight_styles = resolved;
    }
  }
}
