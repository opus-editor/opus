namespace Syntax {
  /**
   * Says what is wrong with a language package, the way its author
   * needs to hear it: every problem at once, each naming the file it
   * is in. What Opus does with a broken package while running — log it
   * and carry on without the language — is right for a user and
   * useless to whoever is writing the package.
   */
  public class LanguageChecker : Object {
    private const string[] QUERY_NAMES = { "highlights", "injections", "locals", "indents" };

    private string[] language_directories;
    private GrammarLoader grammars;
    private GrammarBuilder? builder;

    /** `language_directories` are where the packages a query may `; inherits:` from live. Without a `builder`, a grammar that was never compiled is itself a problem. */
    public LanguageChecker (string[] language_directories, GrammarLoader grammars, GrammarBuilder? builder = null) {
      this.language_directories = language_directories;
      this.grammars = grammars;
      this.builder = builder;
    }

    /** Every problem found in the package at `directory` — empty when it is sound. */
    public string[] check (string directory) {
      LanguagePackage package;
      try {
        package = LanguagePackage.load (directory);
      } catch (PackageError e) {
        if (e is PackageError.UNREADABLE) {
          // Its message already names the file.
          return { e.message };
        }
        return { "%s: %s".printf (LanguagePackage.MANIFEST, e.message) };
      }
      if (package.grammar == null) {
        // Nothing to compile its queries against: they are only ever
        // read into the packages that inherit them.
        return {};
      }

      unowned TreeSitter.Language grammar;
      try {
        grammar = grammar_of (package);
      } catch (Error e) {
        return { "grammar: %s".printf (e.message) };
      }
      return query_problems (package, grammar);
    }

    private unowned TreeSitter.Language grammar_of (LanguagePackage package) throws Error {
      try {
        return grammars.load (package.grammar);
      } catch (GrammarError e) {
        if (!(e is GrammarError.NOT_FOUND) || builder == null) {
          throw e;
        }
      }
      builder.build (package.grammar);
      return grammars.load (package.grammar);
    }

    private string[] query_problems (LanguagePackage package, TreeSitter.Language grammar) {
      // The package's own parent last, so it is checked as written even
      // when an installed package has the same name.
      string[] directories = language_directories;
      directories += Path.get_dirname (package.directory);
      var queries = new QuerySource (new LanguageRegistry (directories));

      string[] problems = {};
      foreach (unowned string query_name in QUERY_NAMES) {
        var source = queries.read (package.name, query_name);
        if (source == null) {
          continue;
        }
        try {
          new QueryPredicates (QuerySource.compile (grammar, source));
        } catch (QueryError e) {
          problems += "queries/%s.scm: %s".printf (query_name, e.message);
        }
      }
      return problems;
    }
  }
}
