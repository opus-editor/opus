/**
 * What the per-language tests ask of a bundled language package: how
 * far Enter indents, whether a typed closer pulls its line out, what a
 * word is painted as, which symbols a file lists. Each answers for the real package in languages/,
 * compiled grammar and all — OPUS_LANGUAGES_DIR and OPUS_GRAMMARS_DIR
 * are set by tests/meson.build.
 *
 * A text marks where the cursor is with `<|>`.
 */
namespace LanguageProbe {
    private const string CURSOR = "<|>";

    // One for the whole binary: reading forty packages again for every
    // question would make a language's tests take seconds.
    private Syntax.Languages? languages = null;

    private Syntax.SyntaxDocument document (string file_name, string text) {
        if (languages == null) {
            // The styles a test may see: every capture falls back to one of these, as it would to a theme's.
            string[] styles = { "attribute", "comment", "constant", "function", "keyword", "string", "tag", "type", "variable" };
            languages = new Syntax.Languages ({ Environment.get_variable ("OPUS_LANGUAGES_DIR") }, { Environment.get_variable ("OPUS_GRAMMARS_DIR") }, styles);
        }
        var language = languages.detect (file_name);
        if (language == null) {
            error ("no bundled language claims %s", file_name);
        }
        var document = new Syntax.SyntaxDocument (language, languages);
        document.set_text (text);
        return document;
    }

    private string without_cursor (string marked, out int offset) {
        int at = marked.index_of (CURSOR);
        if (at < 0) {
            error ("the text has no %s marking the cursor: %s", CURSOR, marked);
        }
        offset = marked.substring (0, at).char_count ();
        return marked.substring (0, at) + marked.substring (at + CURSOR.length);
    }

    /** How many levels Enter at the cursor adds to the new line, beyond the line it leaves. */
    public int enter (string file_name, string marked) {
        int offset;
        var text = without_cursor (marked, out offset);
        return document (file_name, text).new_line_indent_change (offset);
    }

    /**
     * Whether the cursor has just finished typing something that
     * closes a block, first on its line — and then how many `levels`
     * that line should have beyond the nearest line above with text.
     */
    public bool closes (string file_name, string marked, out int levels) {
        int offset;
        var text = without_cursor (marked, out offset);
        return document (file_name, text).outdent_change (offset, line_above_with_text (text, offset), out levels);
    }

    /** The character offset of the start of the nearest non-blank line above the one `offset` is on — what CursorCollection measures an outdent from. */
    private int line_above_with_text (string text, int offset) {
        var lines = text.split ("\n");
        int row = 0;
        int consumed = 0;
        while (consumed + lines[row].char_count () < offset) {
            consumed += lines[row].char_count () + 1;
            row++;
        }
        for (int above = row - 1; above >= 0; above--) {
            consumed -= lines[above].char_count () + 1;
            if (lines[above].strip () != "") {
                return consumed;
            }
        }
        error ("no line with text above the cursor");
    }

    /**
     * What the `#` list would show for `text`, a line per symbol in
     * the order of the file: `name: kind`, or `name: kind · container`
     * for one defined inside another.
     */
    public string[] symbols (string file_name, string text) {
        string[] lines = {};
        foreach (var symbol in document (file_name, text).symbols ()) {
            lines += symbol.container == ""
                ? "%s: %s".printf (symbol.name, symbol.kind)
                : "%s: %s · %s".printf (symbol.name, symbol.kind, symbol.container);
        }
        return lines;
    }

    /** The style `word` is painted with where it first appears in `text` — "" when it is left plain. */
    public string style_of (string file_name, string text, string word) {
        int at = text.index_of (word);
        if (at < 0) {
            error ("\"%s\" is not in the text", word);
        }
        uint32 row = 0;
        uint32 column = 0;
        for (int i = 0; i < at; i++) {
            if (text[i] == '\n') {
                row++;
                column = 0;
            } else {
                column++;
            }
        }

        // Held until the style is copied out: a span's style belongs to the document's language.
        var held = document (file_name, text);
        string style = "";
        foreach (var span in held.highlights (row, row)) {
            if (span.start_row == row && span.start_column <= column && column < span.end_column) {
                style = span.style;
            }
        }
        return style;
    }
}
