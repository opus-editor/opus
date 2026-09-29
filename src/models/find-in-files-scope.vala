/**
 * Parses the "Where" field's own raw text into an include/exclude glob
 * filter — same pattern grammar as a real `.gitignore` (checked
 * git-scm.com/docs/gitignore): comma-separated patterns, a leading "/"
 * anchors a pattern to the search root (matching a "/" anywhere else
 * in it does the same — only a pure basename with no "/" at all gets
 * to match starting at any depth), a trailing "/" matches only
 * directories (and everything under them), "**" matches any number of
 * whole path segments, "*"/"?" the usual glob wildcards (neither ever
 * crosses a "/").
 *
 * Deliberately the *opposite* polarity of a real .gitignore's own bare-
 * pattern-excludes/"!"-re-includes rule: here a bare pattern
 * *restricts* the search to only paths matching at least one of them
 * (an inclusion list — empty means "everything"), and "!" is what
 * excludes instead. Checked against Pulsar's own real "Where" field
 * (@pulsar-edit/scandal's path-filter.js, extracted straight from its
 * shipped app.asar): its own sanitizePaths() does the exact same
 * split, moving any "!"-prefixed entry from its inclusions into a
 * separate exclusions list — the natural shape for a single "Where"
 * field that still wants both directions without two separate fields
 * (VS Code's own approach, checked too — it never needed this split
 * at all, since exclude already has its own field there).
 *
 * Not backed by a real `git` invocation, unlike FindInFilesSearch's own
 * gitignore_enabled path: these patterns are typed ad hoc into one
 * field, not read from a real .gitignore file on disk, and matching
 * them is a much smaller problem (one flat pattern list, no nested
 * per-directory files, no multiple exclude sources to merge) — not
 * worth a second subprocess round-trip for.
 *
 * Known v1 simplifications, neither exercised by any pattern this was
 * actually designed against: bracket ranges (`[a-zA-Z]`, real gitignore
 * supports these) are treated as literal characters, not parsed as a
 * character class; a "**" that neither leads nor trails nor sits
 * between two "/"s (e.g. a bare "a**b" with no separators at all) falls
 * back to plain "match any characters" rather than anything gitignore-
 * spec-exact for that malformed shape.
 */
public class FindInFilesScope : Object {
  private Regex[] inclusion_patterns;
  private Regex[] exclusion_patterns;

  public FindInFilesScope (string where_text) throws RegexError {
    var inclusions = new GenericArray<Regex> ();
    var exclusions = new GenericArray<Regex> ();

    foreach (var raw in where_text.split (",")) {
      var pattern = raw.strip ();
      if (pattern == "") {
        continue;
      }

      bool is_exclusion = pattern.has_prefix ("!");
      if (is_exclusion) {
        pattern = pattern.substring (1);
      }

      var regex = compile_pattern (pattern);
      if (is_exclusion) {
        exclusions.add (regex);
      } else {
        inclusions.add (regex);
      }
    }

    inclusion_patterns = to_array (inclusions);
    exclusion_patterns = to_array (exclusions);
  }

  /** Whether `relative_path` (root-relative, "/"-separated, no leading "/") passes this scope: none of the exclusions match it, and either there are no inclusions at all or at least one does. */
  public bool is_path_included (string relative_path) {
    foreach (var pattern in exclusion_patterns) {
      if (pattern.match (relative_path)) {
        return false;
      }
    }
    if (inclusion_patterns.length == 0) {
      return true;
    }
    foreach (var pattern in inclusion_patterns) {
      if (pattern.match (relative_path)) {
        return true;
      }
    }
    return false;
  }

  private static Regex[] to_array (GenericArray<Regex> list) {
    var result = new Regex[list.length];
    for (uint i = 0; i < list.length; i++) {
      result[i] = list[i];
    }
    return result;
  }

  /** Translates one gitignore-style pattern (already had its own leading "!" stripped, if any) into a Regex matching a root-relative path — see the class's own doc comment for the exact rules. */
  private static Regex compile_pattern (string pattern) throws RegexError {
    string body = pattern;
    bool anchored = body.has_prefix ("/");
    if (anchored) {
      body = body.substring (1);
    }
    bool directory_only = body.has_suffix ("/");
    if (directory_only) {
      body = body.substring (0, body.length - 1);
    }
    // Any "/" left in the body — leading already stripped above — still
    // anchors the pattern per real gitignore rules; only a pure
    // basename (no "/" anywhere) gets to match starting at any depth.
    anchored = anchored || body.contains ("/");

    var regex_body = glob_body_to_regex (body);
    string full_pattern = (anchored ? "^" : "(?:^|.*/)") + regex_body;
    // A pattern with no trailing "/" can match either a file with that
    // exact name, or (if it names a directory instead) anything under
    // it — same "matches both files and directories" rule real
    // gitignore documents for the no-trailing-slash case. A trailing
    // "/" is stricter: only ever a directory, so it must have *some*
    // real path segment after it — a same-named bare file doesn't
    // count as "inside" anything.
    full_pattern += directory_only ? "/.*$" : "(?:/.*)?$";
    return new Regex (full_pattern);
  }

  /** Segment-by-segment glob->regex translation for one pattern's own body (anchoring/directory-only already resolved by compile_pattern()) — a lone "*"/"?" never crosses a "/", "**" always can. */
  private static string glob_body_to_regex (string body) {
    if (body == "") {
      return "";
    }
    if (body == "**") {
      return ".*";
    }

    var segments = body.split ("/");
    var result = new StringBuilder ();
    for (int i = 0; i < segments.length; i++) {
      if (segments[i] == "**") {
        // Zero or more whole path segments, each including its own
        // trailing "/" — folds the "/" a neighboring segment would
        // otherwise need into this same group, so nothing extra is
        // emitted for that join on either side (confirmed against
        // "a/**/b" matching "a/b", "a/x/b", "a/x/y/b" — see the class's
        // own tests).
        result.append ("(?:.*/)?");
      } else {
        if (i > 0 && segments[i - 1] != "**") {
          result.append ("/");
        }
        result.append (translate_segment (segments[i]));
      }
    }
    return result.str;
  }

  private static string translate_segment (string segment) {
    var result = new StringBuilder ();
    unowned string iter = segment;
    while (iter.length > 0) {
      unichar c = iter.get_char ();
      if (c == '*') {
        result.append ("[^/]*");
      } else if (c == '?') {
        result.append ("[^/]");
      } else {
        result.append (Regex.escape_string (c.to_string ()));
      }
      iter = iter.next_char ();
    }
    return result.str;
  }
}
