namespace Syntax {
  /** One language to parse out of the middle of another: which, and over which stretches of the text. */
  internal class Injection {
    public LoadedLanguage language;
    public TreeSitter.Range[] ranges = {};
  }

  /**
   * Reads a parsed layer's injections query: where it embeds other
   * languages. The conventions are tree-sitter's own, as Helix uses
   * them — `@injection.content` is the text, the language comes from
   * `(#set! injection.language "css")` or the text `@injection.language`
   * captured, `injection.combined` parses every match of a pattern as
   * one document (the Ruby scattered through an ERB file), and a
   * content node's children are left out unless
   * `injection.include-children` says otherwise.
   */
  namespace SyntaxInjections {
    internal GenericArray<Injection> find (LoadedLanguage host, TreeSitter.Tree tree, Languages languages, NodeTextFunc node_text) {
      var found = new GenericArray<Injection> ();
      if (host.injections == null || host.injection_content_capture < 0) {
        return found;
      }

      // One per pattern that set `injection.combined`, by pattern index and language.
      var combined = new HashTable<string, Injection> (str_hash, str_equal);
      var cursor = new TreeSitter.QueryCursor ();
      cursor.exec (host.injections, tree.root_node ());

      TreeSitter.QueryMatch match;
      while (cursor.next_match (out match)) {
        if (!host.injection_predicates.accepts (match, node_text)) {
          continue;
        }
        var language = language_of (host, match, languages, node_text);
        if (language != null) {
          add_match (host, match, language, combined, found);
        }
      }
      return with_ranges (found);
    }

    private LoadedLanguage? language_of (LoadedLanguage host, TreeSitter.QueryMatch match, Languages languages, NodeTextFunc node_text) {
      var name = host.injection_predicates.property (match.pattern_index, "injection.language");
      if (name == null) {
        foreach (var capture in match.captures) {
          if (capture.index == host.injection_language_capture) {
            name = node_text (capture.node);
          }
        }
      }
      return name == null ? null : languages.for_injection (name.strip ());
    }

    private void add_match (LoadedLanguage host, TreeSitter.QueryMatch match, LoadedLanguage language, HashTable<string, Injection> combined, GenericArray<Injection> found) {
      var injection = injection_for (host, match, language, combined, found);
      foreach (var capture in match.captures) {
        if (capture.index == host.injection_content_capture) {
          add_content (host, match.pattern_index, capture.node, injection);
        }
      }
    }

    private Injection injection_for (LoadedLanguage host, TreeSitter.QueryMatch match, LoadedLanguage language, HashTable<string, Injection> combined, GenericArray<Injection> found) {
      bool is_combined = host.injection_predicates.property (match.pattern_index, "injection.combined") != null;
      var key = "%u:%s".printf (match.pattern_index, language.package.name);
      if (is_combined && combined.contains (key)) {
        return combined[key];
      }

      var injection = new Injection ();
      injection.language = language;
      found.add (injection);
      if (is_combined) {
        combined[key] = injection;
      }
      return injection;
    }

    private void add_content (LoadedLanguage host, uint pattern, TreeSitter.Node content, Injection injection) {
      var predicates = host.injection_predicates;
      if (predicates.property (pattern, "injection.include-children") != null) {
        add_range (injection, content.start_byte (), content.start_point (), content.end_byte (), content.end_point ());
        return;
      }

      // Helix's own extension: keep the unnamed children (punctuation, keywords), drop only the named ones.
      bool keep_unnamed = predicates.property (pattern, "injection.include-unnamed-children") != null;
      uint32 from_byte = content.start_byte ();
      var from_point = content.start_point ();
      for (uint32 i = 0; i < content.child_count (); i++) {
        var child = content.child (i);
        if (keep_unnamed && !child.is_named ()) {
          continue;
        }
        add_range (injection, from_byte, from_point, child.start_byte (), child.start_point ());
        from_byte = child.end_byte ();
        from_point = child.end_point ();
      }
      add_range (injection, from_byte, from_point, content.end_byte (), content.end_point ());
    }

    private void add_range (Injection injection, uint32 start_byte, TreeSitter.Point start_point, uint32 end_byte, TreeSitter.Point end_point) {
      if (start_byte >= end_byte) {
        return;
      }
      injection.ranges += TreeSitter.Range () {
        start_byte = start_byte,
        start_point = start_point,
        end_byte = end_byte,
        end_point = end_point,
      };
    }

    private GenericArray<Injection> with_ranges (GenericArray<Injection> injections) {
      var kept = new GenericArray<Injection> ();
      foreach (var injection in injections) {
        if (injection.ranges.length > 0) {
          kept.add (injection);
        }
      }
      return kept;
    }
  }
}
