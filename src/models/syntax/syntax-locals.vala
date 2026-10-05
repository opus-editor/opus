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
   * definition, each with the style its definition asked for. Read by
   * highlighting twice over: a resolved reference is painted as its
   * definition's class rather than as whatever `highlights.scm` made
   * of the bare identifier, and `(#is-not? local)` patterns skip it.
   */
  internal class LocalReferences {
    // Parallel, in document order.
    private uint32[] start_bytes = {};
    private uint32[] end_bytes = {};
    private TreeSitter.Point[] start_points = {};
    private TreeSitter.Point[] end_points = {};
    private string?[] styles = {};

    public int length { get { return start_bytes.length; } }

    internal void add (TreeSitter.Node node, string? style) {
      start_bytes += node.start_byte ();
      end_bytes += node.end_byte ();
      start_points += node.start_point ();
      end_points += node.end_point ();
      styles += style;
    }

    public bool contains (TreeSitter.Node node) {
      int index = first_from (node.start_byte ());
      return index < length && start_bytes[index] == node.start_byte () && end_bytes[index] == node.end_byte ();
    }

    /** The index of the first reference starting on `row` or later. */
    public int first_on_row (uint32 row) {
      int low = 0;
      int high = length;
      while (low < high) {
        int middle = (low + high) / 2;
        if (start_points[middle].row < row) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      return low;
    }

    public TreeSitter.Point start_of (int index) {
      return start_points[index];
    }

    public TreeSitter.Point end_of (int index) {
      return end_points[index];
    }

    /** Null for a definition class no style key covers: the reference is local all the same, just not repainted. */
    public unowned string? style_of (int index) {
      return styles[index];
    }

    private int first_from (uint32 start_byte) {
      int low = 0;
      int high = length;
      while (low < high) {
        int middle = (low + high) / 2;
        if (start_bytes[middle] < start_byte) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      return low;
    }
  }

  private class LocalScope {
    public uint32 start;
    public uint32 end;
    /** False for a scope that hides what encloses it — a Ruby method body sees none of the locals around it. */
    public bool inherits = true;
    public HashTable<string, int> definitions = new HashTable<string, int> (str_hash, str_equal);
  }

  private class LocalName {
    public TreeSitter.Node node;
    public LocalRole role;
    public uint16 pattern;
    /** For a definition: its capture id, which is what the reference's style is looked up by. */
    public uint32 capture;
  }

  /**
   * Resolves a layer's locals query, Helix's way: `@local.scope` nodes
   * bound where a definition is visible, `@local.definition.<class>`
   * introduces a name, and a `@local.reference` whose text matches a
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
          stack[stack.length - 1].definitions[node_text (name.node)] = (int) name.capture;
        } else if (name.role == LocalRole.REFERENCE && !discarded (names, i)) {
          int capture = definition_visible_from (stack, node_text (name.node));
          if (capture >= 0) {
            references.add (name.node, language.local_definition_styles[capture]);
          }
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
          name.capture = capture.index;
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

    /** The capture id of the definition of `text` nearest to the innermost scope, or -1. */
    private int definition_visible_from (GenericArray<LocalScope> stack, string text) {
      for (int i = stack.length - 1; i >= 0; i--) {
        if (stack[i].definitions.contains (text)) {
          return stack[i].definitions[text];
        }
        if (!stack[i].inherits) {
          return -1;
        }
      }
      return -1;
    }
  }
}
