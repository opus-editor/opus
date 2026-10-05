namespace Syntax {
  // Public only because valac declares an internal enum twice over when
  // a library's files share it; nothing outside this namespace uses it.
  public enum LocalRole {
    /** A capture that is none of the three below: it only cancels a reference on the same node. */
    DISCARD,
    SCOPE,
    DEFINITION,
    REFERENCE,
  }

  /**
   * The references one parsed layer's locals query resolved to a local
   * definition. All highlighting asks of it is whether a node is one:
   * that is what `(#is-not? local)` and `(#is? local)` test.
   *
   * Helix goes one step further and repaints a resolved reference in
   * its definition's class, so a parameter is colored as one wherever
   * it is used. Opus deliberately doesn't: a name is colored where it
   * is declared, by `highlights.scm`, and its uses stay plain.
   */
  internal class LocalReferences {
    // Parallel, in document order.
    private uint32[] start_bytes = {};
    private uint32[] end_bytes = {};

    internal void add (TreeSitter.Node node) {
      start_bytes += node.start_byte ();
      end_bytes += node.end_byte ();
    }

    public bool contains (TreeSitter.Node node) {
      uint32 start = node.start_byte ();
      int low = 0;
      int high = start_bytes.length;
      while (low < high) {
        int middle = (low + high) / 2;
        if (start_bytes[middle] < start) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      return low < start_bytes.length && start_bytes[low] == start && end_bytes[low] == node.end_byte ();
    }
  }

  private class LocalScope {
    public uint32 start;
    public uint32 end;
    /** False for a scope that hides what encloses it — a Ruby method body sees none of the locals around it. */
    public bool inherits = true;
    public GenericSet<string> definitions = new GenericSet<string> (str_hash, str_equal);
  }

  private class LocalName {
    public TreeSitter.Node node;
    public LocalRole role;
    public uint16 pattern;
  }

  /**
   * Resolves a layer's locals query, Helix's way: `@local.scope` nodes
   * bound where a definition is visible, `@local.definition.<class>`
   * introduces a name (the class is Helix's, unused here — see
   * LocalReferences), and a `@local.reference` whose text matches a
   * definition visible from where it stands is that local. A scope
   * sees the definitions of the scopes around it unless it sets
   * `local.scope-inherits` to false; an inner definition shadows an
   * outer one. Any other capture on a node cancels a reference there
   * when its pattern comes later in the query.
   */
  namespace SyntaxLocals {
    internal LocalReferences resolve (LoadedLanguage language, TreeSitter.Tree tree, NodeTextFunc node_text) {
      var scopes = new GenericArray<LocalScope> ();
      var names = new GenericArray<LocalName> ();
      collect (language, tree, node_text, scopes, names);

      // Outermost first among scopes starting together, so the stack below nests them properly.
      scopes.sort ((a, b) => a.start != b.start ? (a.start < b.start ? -1 : 1) : (a.end > b.end ? -1 : (a.end < b.end ? 1 : 0)));
      // A definition ahead of a reference on the same node: a parameter is both, and has to exist before it can resolve to itself.
      names.sort ((a, b) => by_position_then_role (a, b));

      var references = new LocalReferences ();
      var root = new LocalScope ();
      root.end = uint32.MAX;
      var stack = new GenericArray<LocalScope> ();
      stack.add (root);
      int next_scope = 0;

      for (int i = 0; i < names.length; i++) {
        var name = names[i];
        uint32 position = name.node.start_byte ();
        while (stack.length > 1 && stack[stack.length - 1].end <= position) {
          stack.remove_index (stack.length - 1);
        }
        while (next_scope < scopes.length && scopes[next_scope].start <= position) {
          if (scopes[next_scope].end > position) {
            stack.add (scopes[next_scope]);
          }
          next_scope++;
        }

        if (name.role == LocalRole.DEFINITION) {
          stack[stack.length - 1].definitions.add (node_text (name.node));
        } else if (name.role == LocalRole.REFERENCE && !discarded (names, i) && defined_in (stack, node_text (name.node))) {
          references.add (name.node);
        }
      }
      return references;
    }

    private void collect (LoadedLanguage language, TreeSitter.Tree tree, NodeTextFunc node_text, GenericArray<LocalScope> scopes, GenericArray<LocalName> names) {
      var cursor = new TreeSitter.QueryCursor ();
      cursor.exec (language.locals, tree.root_node ());

      TreeSitter.QueryMatch match;
      while (cursor.next_match (out match)) {
        if (!language.local_predicates.accepts (match, node_text)) {
          continue;
        }
        bool inherits = language.local_predicates.property (match.pattern_index, "local.scope-inherits") != "false";
        foreach (var capture in match.captures) {
          var role = language.local_roles[capture.index];
          if (role == LocalRole.SCOPE) {
            var scope = new LocalScope ();
            scope.start = capture.node.start_byte ();
            scope.end = capture.node.end_byte ();
            scope.inherits = inherits;
            scopes.add (scope);
            continue;
          }
          var name = new LocalName ();
          name.node = capture.node;
          name.role = role;
          name.pattern = match.pattern_index;
          names.add (name);
        }
      }
    }

    private int by_position_then_role (LocalName a, LocalName b) {
      uint32 a_start = a.node.start_byte ();
      uint32 b_start = b.node.start_byte ();
      if (a_start != b_start) {
        return a_start < b_start ? -1 : 1;
      }
      bool a_defines = a.role == LocalRole.DEFINITION;
      bool b_defines = b.role == LocalRole.DEFINITION;
      if (a_defines != b_defines) {
        return a_defines ? -1 : 1;
      }
      return 0;
    }

    /** Whether another capture on the very same node, from a later pattern, takes the reference at `index` back. Same-node entries sit next to each other in the sorted list. */
    private bool discarded (GenericArray<LocalName> names, int index) {
      var reference = names[index];
      for (int i = index - 1; i >= 0 && same_node (names[i], reference); i--) {
        if (names[i].role == LocalRole.DISCARD && names[i].pattern > reference.pattern) {
          return true;
        }
      }
      for (int i = index + 1; i < names.length && same_node (names[i], reference); i++) {
        if (names[i].role == LocalRole.DISCARD && names[i].pattern > reference.pattern) {
          return true;
        }
      }
      return false;
    }

    private bool same_node (LocalName a, LocalName b) {
      return a.node.start_byte () == b.node.start_byte () && a.node.end_byte () == b.node.end_byte ();
    }

    /** Whether a definition of `text` is visible from the innermost scope of `stack`. */
    private bool defined_in (GenericArray<LocalScope> stack, string text) {
      for (int i = stack.length - 1; i >= 0; i--) {
        if (stack[i].definitions.contains (text)) {
          return true;
        }
        if (!stack[i].inherits) {
          return false;
        }
      }
      return false;
    }
  }
}
