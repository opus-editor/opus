namespace Functions.Native {
  /** The functions written in Vala, in the same list as the packages: one that needs the syntax model has no way to be a script yet. */
  public GenericArray<Function> catalog () {
    var functions = new GenericArray<Function> ();
    functions.add (new Function ("reindent", _("Reindent"), _("Every line's indentation redone from the syntax"), Scope.DOCUMENT, {}, new Reindent ()));
    functions.add (new Function ("trim-trailing-whitespace", _("Trim trailing whitespace"), _("The blanks at the end of every line, gone"), Scope.BOTH, {}, new TrimTrailingWhitespace ()));
    // Only ever worth running on save: nothing to pick from a list.
    functions.add (new Function ("insert-final-newline", _("Insert final newline"), _("A newline at the end of the file, when it lacks one"), Scope.DOCUMENT, {}, new InsertFinalNewline ()) { hidden = true });
    return functions;
  }

  /**
   * Re-derives each line's indentation from the one above it, the way
   * Enter and a typed closer already do: a line goes in by what the
   * previous line opened (SyntaxDocument.new_line_indent_change) and
   * comes out by what it starts with (outdent_change). Blank lines are
   * emptied. Refused where whitespace is the syntax, since the tree
   * would only ever confirm the indentation as it is.
   */
  public class Reindent : Object, IRunner {
    // Just: a recipe's body is whatever is indented under its header.
    private const string[] WHITESPACE_LANGUAGES = { "python", "yaml", "markdown", "just" };

    public string[] run (Input input) throws FunctionError {
      var languages = Syntax.Languages.instance;
      var language = input.language == "" || languages == null ? null : languages.by_name (input.language);
      if (language == null) {
        throw new FunctionError.UNSUPPORTED ("Reindent needs a language with an indent query, and this file has no language");
      }
      if (input.language in WHITESPACE_LANGUAGES || !language.indents_lines) {
        throw new FunctionError.UNSUPPORTED ("Reindent can't tell where lines go in %s", language.package.title);
      }
      var text = input.segments[0].text;
      var document = new Syntax.SyntaxDocument (language, languages);
      document.set_text (text);
      // A tree with an error in it says where lines go only up to the
      // error, and makes everything after it up: not worth a whole file.
      int error_line = document.syntax_error_line ();
      if (error_line > 0) {
        throw new FunctionError.UNSUPPORTED ("Reindent needs a file %s can read: there is a syntax error at line %d", language.package.title, error_line);
      }
      return { reindented (document, text, input.insert_spaces, input.indent_size) };
    }

    /** How many characters of blank space start `line`. */
    private static int leading_blank (string line) {
      int count = 0;
      int index = 0;
      unichar c;
      while (line.get_next_char (ref index, out c) && c.isspace ()) {
        count++;
      }
      return count;
    }

    private static string reindented (Syntax.SyntaxDocument document, string text, bool insert_spaces, int indent_size) {
      var lines = text.split ("\n");
      // Asking for every row's highlights parses the languages embedded
      // in the text (a <script> in a page), whose own indent rules the
      // lines inside them follow.
      document.highlights (0, (uint32) lines.length);
      int[] levels = new int[lines.length];
      int[] starts = new int[lines.length];
      int offset = 0;
      for (int i = 0; i < lines.length; i++) {
        starts[i] = offset;
        offset += lines[i].char_count () + 1;
      }

      int previous = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].strip () == "") {
          continue;
        }
        if (previous < 0) {
          levels[i] = 0;
          previous = i;
          continue;
        }
        int break_offset = starts[previous] + lines[previous].char_count ();
        int change = document.new_line_indent_change (break_offset);
        int outdent_levels;
        if (document.outdent_change_at (starts[i] + leading_blank (lines[i]), starts[previous], out outdent_levels)) {
          change = outdent_levels;
        }
        levels[i] = int.max (0, levels[previous] + change);
        previous = i;
      }

      var result = new StringBuilder ();
      for (int i = 0; i < lines.length; i++) {
        if (i > 0) {
          result.append_c ('\n');
        }
        var content = lines[i].strip ();
        if (content == "") {
          continue;
        }
        result.append (insert_spaces ? string.nfill (levels[i] * indent_size, ' ') : string.nfill (levels[i], '\t'));
        result.append (content);
      }
      return result.str;
    }
  }
}
