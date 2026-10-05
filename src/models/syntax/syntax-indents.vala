namespace Syntax {
  // Public for the same valac reason as LocalRole.
  public enum IndentRole {
    /** A capture the indent rules below don't read (`@align`, `@extend`, …). */
    NONE,
    INDENT,
    INDENT_ALWAYS,
    OUTDENT,
    OUTDENT_ALWAYS,
  }

  /** What the indent query says of one line, before it is turned into a number of levels. */
  private class IndentLevel {
    public int indent;
    public int indent_always;
    public int outdent;
    public int outdent_always;

    public int net () {
      return indent + indent_always - outdent - outdent_always;
    }
  }

  private class IndentCaptures {
    public bool indent;
    public bool indent_always;
    public bool outdent;
    public bool outdent_always;
    /** `(#set! "scope" "header")`: the scope opens on the parent's first line, not the node's own. */
    public bool header;
  }

  /**
   * Reads a layer's indents query, by Helix's rules. The level of a
   * line is the number of `@indent` scopes containing it, a scope
   * running from the line after its node's first to the node's last;
   * scopes opening on one same line count once. `@outdent` takes a
   * level off the line its node starts on. The `.always` forms don't
   * collapse, and a node captured as both indent and outdent counts
   * as neither.
   *
   * Everything here answers in levels *relative to another line*,
   * never as an absolute indentation: the difference is added to what
   * that line really has, so a file indented its own way, or a query
   * that misses a case, shifts a line by a level at most instead of
   * rewriting its indentation.
   *
   * Not read: `@align`/`@anchor`, `@extend` and `@opaque` (what the
   * last one is for, {@link in_literal} gets from the highlights).
   *
   * A line is usually broken while the code around it is unfinished —
   * right after `def foo(arg)`, with no `end` yet — and that is where
   * the rules above need help: an `@indent` node the parser had to
   * close by itself (its last child is a token nobody typed, or an
   * empty body) is taken to go on past the break. What the parser
   * makes of unfinished code still varies with everything around it,
   * so SyntaxDocument also asks about the line on its own.
   */
  namespace SyntaxIndents {
    /**
     * How many levels a line broken off at byte `position` should have
     * beyond the line it is broken from. 0 when the break is in the
     * line's leading whitespace: there is nothing on the line yet for
     * the tree to say anything about.
     */
    internal int new_line_change (LoadedLanguage language, TreeSitter.Tree tree, string text, NodeTextFunc node_text, uint32 position) {
      uint32 line_start = start_of_line (text, position);
      uint32 first = first_non_blank (text, line_start);
      if (first >= position) {
        return 0;
      }
      uint32 last = position - 1;
      while (last > first && is_blank (text[last])) {
        last--;
      }

      var root = tree.root_node ();
      uint32 row = root.descendant_for_byte_range (first, first).start_point ().row;
      var broken_from = level_at (language, tree, node_text, first, row, -1);
      var broken_off = level_at (language, tree, node_text, last, row + 1, position);
      int change = broken_off.net () - broken_from.net ();

      if (change <= 0 && opens_a_bracket (root.descendant_for_byte_range (last, last))) {
        // The line ends on a bracket nothing closes yet, which a tree
        // rarely shows as the list it will become.
        return 1;
      }
      return change;
    }

    /**
     * Whether a line broken off at byte `position` starts inside a
     * string or a comment: text, where a line reading `def foo` opens
     * nothing. Told by the highlights query, which marks both in every
     * language — the same nodes Helix's indent queries call `@opaque`,
     * for the ones that bother to.
     *
     * Inside, not at the end: after the last character of a comment
     * the next line is code again.
     */
    internal bool in_literal (LoadedLanguage language, TreeSitter.Tree tree, NodeTextFunc node_text, uint32 position) {
      if (position == 0) {
        return false;
      }
      var cursor = new TreeSitter.QueryCursor ();
      cursor.set_byte_range (position - 1, position);
      cursor.exec (language.highlights, tree.root_node ());

      TreeSitter.QueryMatch match;
      while (cursor.next_match (out match)) {
        if (!language.highlight_predicates.accepts (match, node_text)) {
          continue;
        }
        foreach (var capture in match.captures) {
          if (language.highlight_literal_captures[capture.index]
              && capture.node.start_byte () < position && position < capture.node.end_byte ()) {
            return true;
          }
        }
      }
      return false;
    }

    private bool opens_a_bracket (TreeSitter.Node token) {
      unowned string type = token.type ();
      return !token.is_named () && (type == "(" || type == "[" || type == "{");
    }

    /**
     * Whether the line holding byte `position` has just come to start
     * with something that closes a block (`end`, `}`, `else`), and if
     * so how many levels it should have beyond the line at byte
     * `reference` — an earlier line with something on it. "Just come
     * to": `position` is right after that first token, with nothing
     * else typed on the line yet.
     */
    internal bool outdent_change (LoadedLanguage language, TreeSitter.Tree tree, string text, NodeTextFunc node_text, uint32 position, uint32 reference, out int levels) {
      levels = 0;
      uint32 first = first_non_blank (text, start_of_line (text, position));
      if (first >= position || !opens_with_outdent (language, tree, node_text, first, position)) {
        return false;
      }

      var root = tree.root_node ();
      uint32 reference_first = first_non_blank (text, start_of_line (text, reference));
      var line = level_at (language, tree, node_text, first, root.descendant_for_byte_range (first, first).start_point ().row, -1);
      var reference_line = level_at (language, tree, node_text, reference_first, root.descendant_for_byte_range (reference_first, reference_first).start_point ().row, -1);
      levels = line.net () - reference_line.net ();
      return true;
    }

    /** Whether the token at `first`, or a node it opens, is an `@outdent` — and ends exactly at `position`. */
    private bool opens_with_outdent (LoadedLanguage language, TreeSitter.Tree tree, NodeTextFunc node_text, uint32 first, uint32 position) {
      var captures = captures_around (language, tree, node_text, first, -1);
      var node = tree.root_node ().descendant_for_byte_range (first, first);
      if (node.end_byte () != position) {
        return false;
      }
      while (!node.is_null () && node.start_byte () == first) {
        var found = captures[node.id];
        if (found != null && (found.outdent || found.outdent_always)) {
          return true;
        }
        node = node.parent ();
      }
      return false;
    }

    /**
     * The level of row `target_row`, read off the ancestors of the
     * node at byte `at`. With `new_line_byte` not negative, rows are
     * the ones the text will have once a line break is inserted there
     * — so `target_row` can be the row that doesn't exist yet.
     */
    private IndentLevel level_at (LoadedLanguage language, TreeSitter.Tree tree, NodeTextFunc node_text, uint32 at, uint32 target_row, int64 new_line_byte) {
      var captures = captures_around (language, tree, node_text, at, new_line_byte);
      var level = new IndentLevel ();
      var counted_rows = new GenericSet<uint?> ((row) => row, (a, b) => a == b);

      for (var node = tree.root_node ().descendant_for_byte_range (at, at); !node.is_null (); node = node.parent ()) {
        var found = captures[node.id];
        if (found == null || ((found.indent || found.indent_always) && (found.outdent || found.outdent_always))) {
          continue;
        }

        uint32 node_row = QueryPredicates.start_row (node, new_line_byte);
        uint32 opens_on = node_row;
        if (found.header && !node.parent ().is_null ()) {
          opens_on = QueryPredicates.start_row (node.parent (), new_line_byte);
        }
        bool reaches = target_row <= QueryPredicates.end_row (node, new_line_byte)
          || (new_line_byte >= 0 && node.end_byte () > at && left_open (node));
        bool contains = opens_on < target_row && reaches;

        if (found.indent && contains && !counted_rows.contains (opens_on)) {
          counted_rows.add (opens_on);
          level.indent++;
        }
        if (found.indent_always && contains) {
          level.indent_always++;
        }
        if (found.outdent && node_row == target_row) {
          level.outdent++;
        }
        if (found.outdent_always && node_row == target_row) {
          level.outdent_always++;
        }
      }
      return level;
    }

    /**
     * Whether the parser had to end `node` by itself: its last piece,
     * followed down, is empty — a token that isn't in the text, or a
     * body with nothing in it yet. Or the node is an error, which is
     * unfinished by definition: a query capturing one as `@indent`
     * (Ruby's `(ERROR "do")`, a `do` whose block the parser couldn't
     * build) is saying what it was going to be.
     */
    private bool left_open (TreeSitter.Node node) {
      if (node.type () == "ERROR") {
        return true;
      }
      var last = node;
      while (last.child_count () > 0) {
        last = last.child (last.child_count () - 1);
      }
      return last.is_missing () || (last.id != node.id && last.start_byte () == last.end_byte ());
    }

    /** What the query captured on each node touching byte `at` — which takes in every ancestor of the node there. By node id. */
    private HashTable<void*, IndentCaptures> captures_around (LoadedLanguage language, TreeSitter.Tree tree, NodeTextFunc node_text, uint32 at, int64 new_line_byte) {
      var captures = new HashTable<void*, IndentCaptures> (direct_hash, direct_equal);
      var cursor = new TreeSitter.QueryCursor ();
      cursor.set_byte_range (at, at + 1);
      cursor.exec (language.indents, tree.root_node ());

      TreeSitter.QueryMatch match;
      while (cursor.next_match (out match)) {
        if (!language.indent_predicates.accepts (match, node_text, null, new_line_byte)) {
          continue;
        }
        foreach (var capture in match.captures) {
          var role = language.indent_roles[capture.index];
          if (role == IndentRole.NONE) {
            continue;
          }
          var found = captures[capture.node.id];
          if (found == null) {
            found = new IndentCaptures ();
            captures[capture.node.id] = found;
          }
          found.indent |= role == IndentRole.INDENT;
          found.indent_always |= role == IndentRole.INDENT_ALWAYS;
          found.outdent |= role == IndentRole.OUTDENT;
          found.outdent_always |= role == IndentRole.OUTDENT_ALWAYS;
          found.header |= language.indent_header_patterns[match.pattern_index];
        }
      }
      return captures;
    }

    private uint32 start_of_line (string text, uint32 position) {
      uint32 start = position;
      while (start > 0 && text[start - 1] != '\n') {
        start--;
      }
      return start;
    }

    /** The first byte from `line_start` on that isn't a space or a tab — the line's end, or the text's, when there is none. */
    private uint32 first_non_blank (string text, uint32 line_start) {
      uint32 first = line_start;
      while (is_blank (text[first])) {
        first++;
      }
      return first;
    }

    private bool is_blank (char byte) {
      return byte == ' ' || byte == '\t';
    }
  }
}
