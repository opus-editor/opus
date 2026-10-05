namespace Glob {
  /**
   * Translates the restricted glob syntax .editorconfig section headers
   * use (language packages' `file-types` globs share it) into a real
   * Regex, anchored to a full match against a `/`-separated path:
   *
   *   `*`        any run of characters except `/`
   *   `**`       any run of characters, `/` included
   *   `?`        one character except `/`
   *   `[abc]`    one character out of the set
   *   `[!abc]`   one character NOT in the set
   *   `{a,b,c}`  one of the given alternatives (literal text each)
   *
   * `{n1..n2}` numeric ranges aren't supported — real-world
   * .editorconfig files essentially never use them, everything else
   * above covers the common `[*.py]`/`[*.{js,ts}]`/`[Makefile]` shapes.
   *
   * A pattern with no `/` at all matches at any depth (the spec's own
   * rule: it gets an implicit "any directory" prefix) — `*.py` matches
   * `src/models/foo.py`, not just a top-level file.
   */
  public Regex compile (string raw_pattern) throws RegexError {
    var pattern = raw_pattern;
    bool any_depth = !pattern.contains ("/");
    if (pattern.has_prefix ("/")) {
      pattern = pattern.substring (1);
    }

    var regex_text = new StringBuilder ("^");
    // Zero or more leading path segments, not one-or-more — a bare
    // `**/` textually prepended to the pattern would force a literal
    // `/` into the regex and stop `[*.py]` (no `/` of its own) from
    // ever matching a top-level `foo.py` at all.
    if (any_depth) {
      regex_text.append ("(?:.*/)?");
    }

    int n = pattern.length;
    int i = 0;
    while (i < n) {
      char c = pattern[i];

      if (c == '\\' && i + 1 < n) {
        regex_text.append (Regex.escape_string (pattern[i + 1].to_string ()));
        i += 2;
        continue;
      }

      if (c == '*' && i + 1 < n && pattern[i + 1] == '*') {
        regex_text.append (".*");
        i += 2;
        continue;
      }

      if (c == '*') {
        regex_text.append ("[^/]*");
        i += 1;
        continue;
      }

      if (c == '?') {
        regex_text.append ("[^/]");
        i += 1;
        continue;
      }

      if (c == '[') {
        int close = pattern.index_of ("]", i + 1);
        if (close < 0) {
          regex_text.append ("\\[");
          i += 1;
          continue;
        }
        var set_body = pattern.slice (i + 1, close);
        if (set_body.has_prefix ("!")) {
          set_body = "^" + set_body.substring (1);
        }
        regex_text.append ("[").append (set_body).append ("]");
        i = close + 1;
        continue;
      }

      if (c == '{') {
        int close = pattern.index_of ("}", i + 1);
        if (close < 0) {
          regex_text.append ("\\{");
          i += 1;
          continue;
        }
        var alternatives = pattern.slice (i + 1, close).split (",");
        regex_text.append ("(?:");
        for (int a = 0; a < alternatives.length; a++) {
          if (a > 0) {
            regex_text.append ("|");
          }
          regex_text.append (Regex.escape_string (alternatives[a]));
        }
        regex_text.append (")");
        i = close + 1;
        continue;
      }

      regex_text.append (Regex.escape_string (c.to_string ()));
      i += 1;
    }
    regex_text.append ("$");

    return new Regex (regex_text.str);
  }
}
