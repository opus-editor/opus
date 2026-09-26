/**
 * One `[pattern]` section of a parsed .editorconfig file: the glob it
 * matches against, compiled once up front, and the lowercase key/value
 * properties declared under it.
 */
private class EditorConfigSection : Object {
    public Regex pattern;
    public HashTable<string, string> properties = new HashTable<string, string> (str_hash, str_equal);
}

/**
 * Parses a .editorconfig file and resolves its `indent_size` for a given
 * path — the piece {@link EditorView.TextEditorSourceView}'s future indent
 * guides need to know how many columns one indent level is.
 *
 * Only ever reads the .editorconfig at the linked workspace folder's own
 * root, not the full upward directory walk (each ancestor directory up to
 * a `root = true` file) the real spec does per edited file — every file
 * Opus opens lives under that one linked root already, so a single file
 * there covers the common case without needing a per-file search.
 *
 * A file can declare more than one `indent_size` — a global `[*]` section
 * plus per-language overrides like `[*.py]` — so sections are matched in
 * file order and, same as the real spec, a later matching section wins
 * over an earlier one for the same property.
 */
public class EditorConfig : Object {
    private GenericArray<EditorConfigSection> sections = new GenericArray<EditorConfigSection> ();

    private EditorConfig () {}

    /** Null when `folder_path` has no `.editorconfig`, or it can't be read. */
    public static EditorConfig? load (string folder_path) {
        var path = Path.build_filename (folder_path, ".editorconfig");
        if (!FileUtils.test (path, FileTest.EXISTS)) {
            return null;
        }

        string contents;
        try {
            FileUtils.get_contents (path, out contents);
        } catch (Error e) {
            return null;
        }

        return parse (contents);
    }

    /** Split out from {@link load} so parsing can be tested directly against fixture text, no temp file needed. */
    public static EditorConfig parse (string contents) {
        var config = new EditorConfig ();
        EditorConfigSection? current = null;

        foreach (unowned string raw_line in contents.split ("\n")) {
            var line = raw_line.strip ();

            if (line.length == 0 || line.has_prefix (";") || line.has_prefix ("#")) {
                continue;
            }

            if (line.has_prefix ("[") && line.has_suffix ("]")) {
                current = new EditorConfigSection ();
                current.pattern = compile_glob (line.slice (1, line.length - 1));
                config.sections.add (current);
                continue;
            }

            if (current == null) {
                continue; // preamble before the first section (e.g. `root = true`) — not a matchable property
            }

            int separator = line.index_of ("=");
            if (separator < 0) {
                continue;
            }

            var key = line.substring (0, separator).strip ().down ();
            var value = line.substring (separator + 1).strip ().down ();
            current.properties[key] = value;
        }

        return config;
    }

    /**
     * The resolved `indent_size` for `relative_path` (relative to the
     * linked folder), or null if no matching section sets it. `indent_size
     * = tab` resolves to that same section chain's `tab_width` instead,
     * per spec — and null if that isn't set either.
     */
    public int? indent_size_for (string relative_path) {
        string? indent_size = resolve_property (relative_path, "indent_size");
        if (indent_size == null) {
            return null;
        }
        if (indent_size == "tab") {
            string? tab_width = resolve_property (relative_path, "tab_width");
            if (tab_width == null) {
                return null;
            }
            return int.parse (tab_width);
        }
        return int.parse (indent_size);
    }

    /** "space" resolves to true, "tab" (or any other value) to false, null if no matching section sets `indent_style` at all. */
    public bool? insert_spaces_for (string relative_path) {
        string? indent_style = resolve_property (relative_path, "indent_style");
        if (indent_style == null) {
            return null;
        }
        return indent_style == "space";
    }

    /** The resolved value of `key` for `relative_path` — sections matched in file order, last match wins, same rule `indent_size_for`/`insert_spaces_for` both need. Null if none of them set `key`. */
    private string? resolve_property (string relative_path, string key) {
        string? value = null;

        for (int i = 0; i < sections.length; i++) {
            var section = sections[i];
            if (!section.pattern.match (relative_path)) {
                continue;
            }
            if (section.properties.contains (key)) {
                value = section.properties[key];
            }
        }

        return value;
    }

    /**
     * Translates the restricted glob syntax .editorconfig section headers
     * use into a real Regex, anchored to a full match against a path
     * relative to the linked folder (always `/`-separated, same as the
     * spec mandates regardless of platform):
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
    private static Regex compile_glob (string raw_pattern) {
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

        try {
            return new Regex (regex_text.str);
        } catch (RegexError e) {
            error ("unreachable: EditorConfig-generated regex failed to compile: %s (pattern: %s)", e.message, regex_text.str);
        }
    }
}
