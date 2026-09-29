namespace EditorView.EditorPane_ {
  /**
   * Paints one file's own real language syntax highlighting onto a
   * range of FindResults' own results buffer — the narrow, engine-
   * agnostic seam a future swap to a different highlighting engine
   * (e.g. tree-sitter-highlight) would only need to reimplement, not
   * ripple through FindResults itself: the public surface below is
   * `path` + plain text + an `int[]` of line offsets, nothing from the
   * search Model and no `GtkSource.Language` leaks through.
   *
   * GtkSourceView can't apply a *different*, dynamically-chosen
   * language's highlighting to a sub-range of one buffer via its own
   * `.lang` grammar mechanism (checked directly — its `<context ref=
   * "css:css"/>`-style embedding is authored statically into a
   * grammar, triggered by that grammar's own literal pattern match, not
   * parameterizable at runtime). The working alternative, used here: a
   * reusable scratch GtkSource.Buffer gets `path`'s own guessed
   * Language, is fed just that one snippet, and GtkSourceView's real
   * engine highlights it (ensure_highlight); this class then copies
   * the *resolved visual attributes* of whatever tags land on each run
   * (foreground/background/weight/style/underline/strikethrough) onto
   * a deduplicated tag on the real buffer.
   *
   * Not the tag's own name: confirmed directly against GtkSourceView's
   * real gtksourcecontextengine.c (create_tag()) that its highlighting
   * engine creates ANONYMOUS tags (gtk_text_buffer_create_tag(buffer,
   * NULL, NULL)) and never stores the style id on them — tag.name is
   * always null. get_context_classes_at_iter() doesn't help either;
   * those are just comment/string/no-spell-check/path, not style
   * identities. Deliberately not copying paragraph_background (would
   * paint the whole line, gutter prefix included) or scale (breaks
   * monospace alignment).
   */
  public class FindResultsLanguageHighlighter : Object {
    private GtkSource.Buffer target;
    // One, reused across every highlight() call — not one per block:
    // building a fresh GtkSource.Buffer (and its own highlight engine)
    // per block would be needless churn for what's really just a
    // scratch pad.
    private GtkSource.Buffer scratch;
    private HashTable<string, Gtk.TextTag> tags_by_style_key = new HashTable<string, Gtk.TextTag> (str_hash, str_equal);
    private GenericArray<Gtk.TextTag> owned_tags = new GenericArray<Gtk.TextTag> ();

    public FindResultsLanguageHighlighter (GtkSource.Buffer target) {
      this.target = target;
      scratch = new GtkSource.Buffer (null);
      scratch.highlight_syntax = true;
      // Avoid noise tags unrelated to language styling.
      scratch.highlight_matching_brackets = false;
    }

    /**
     * Paints `snippet` (one block's own lines joined with "\n", no
     * gutter prefix) as `path`'s own language, onto `target` at the
     * offsets `line_start_offsets` gives — `line_start_offsets[i]` is
     * where snippet line `i`'s own content begins in `target`. A
     * no-op when no language matches `path`. A run spanning several
     * scratch lines (e.g. a block comment) is sliced per line against
     * `line_start_offsets` rather than painted as one contiguous
     * range — the "  N: " gutter prefix sits between consecutive
     * lines in `target`, so a straight offset shift would paint clean
     * through it otherwise.
     */
    public void highlight (string path, string snippet, int[] line_start_offsets) {
      var language = GtkSource.LanguageManager.get_default ().guess_language (path, null);
      if (language == null) {
        return;
      }

      scratch.language = language;
      scratch.style_scheme = target.style_scheme;
      scratch.text = snippet;

      Gtk.TextIter bounds_start;
      Gtk.TextIter bounds_end;
      scratch.get_bounds (out bounds_start, out bounds_end);
      scratch.ensure_highlight (bounds_start, bounds_end);

      Gtk.TextIter iter;
      scratch.get_start_iter (out iter);
      while (!iter.is_end ()) {
        var run_start = iter;
        var tags = iter.get_tags ();
        if (!iter.forward_to_tag_toggle (null)) {
          break; // defensive only — not observed to trigger before is_end() does
        }
        if (tags.length () > 0) {
          paint_run_if_styled (run_start, iter, tags, line_start_offsets);
        }
      }
    }

    /** Drops every tag this instance ever added to target.tag_table — call before every re-render (theme change included), or duplicate-looking anonymous tags pile up release over release. */
    public void clear () {
      foreach (var tag in owned_tags) {
        target.tag_table.remove (tag);
      }
      owned_tags = new GenericArray<Gtk.TextTag> ();
      tags_by_style_key.remove_all ();
    }

    private void paint_run_if_styled (Gtk.TextIter run_start, Gtk.TextIter run_end, SList<weak Gtk.TextTag> tags, int[] line_start_offsets) {
      var tag = merged_tag_for (tags);
      if (tag != null) {
        paint_run (run_start, run_end, line_start_offsets, tag);
      }
    }

    /** Resolves every tag in `tags` down to one combined, deduplicated Gtk.TextTag — null if none of them actually set a visual attribute (e.g. only a context-classes marker tag). Later tags in `tags` win a given attribute over earlier ones, matching how GTK itself layers multiple tags' effects by priority. */
    private Gtk.TextTag? merged_tag_for (SList<weak Gtk.TextTag> tags) {
      bool foreground_set = false;
      Gdk.RGBA foreground = {};
      bool background_set = false;
      Gdk.RGBA background = {};
      bool weight_set = false;
      int weight = 0;
      bool style_set = false;
      Pango.Style style = Pango.Style.NORMAL;
      bool underline_set = false;
      Pango.Underline underline = Pango.Underline.NONE;
      bool strikethrough_set = false;
      bool strikethrough = false;

      foreach (var scratch_tag in tags) {
        if (scratch_tag.foreground_set) {
          foreground_set = true;
          foreground = scratch_tag.foreground_rgba;
        }
        if (scratch_tag.background_set) {
          background_set = true;
          background = scratch_tag.background_rgba;
        }
        if (scratch_tag.weight_set) {
          weight_set = true;
          weight = scratch_tag.weight;
        }
        if (scratch_tag.style_set) {
          style_set = true;
          style = scratch_tag.style;
        }
        if (scratch_tag.underline_set) {
          underline_set = true;
          underline = scratch_tag.underline;
        }
        if (scratch_tag.strikethrough_set) {
          strikethrough_set = true;
          strikethrough = scratch_tag.strikethrough;
        }
      }

      if (!foreground_set && !background_set && !weight_set && !style_set && !underline_set && !strikethrough_set) {
        return null;
      }

      var key = "%s|%s|%s|%s|%s|%s".printf (
        foreground_set ? foreground.to_string () : "-",
        background_set ? background.to_string () : "-",
        weight_set ? weight.to_string () : "-",
        style_set ? style.to_string () : "-",
        underline_set ? underline.to_string () : "-",
        strikethrough_set ? strikethrough.to_string () : "-"
      );

      var existing = tags_by_style_key[key];
      if (existing != null) {
        return existing;
      }

      var tag = new Gtk.TextTag (null);
      if (foreground_set) tag.foreground_rgba = foreground;
      if (background_set) tag.background_rgba = background;
      if (weight_set) tag.weight = weight;
      if (style_set) tag.style = style;
      if (underline_set) tag.underline = underline;
      if (strikethrough_set) tag.strikethrough = strikethrough;

      target.tag_table.add (tag);
      owned_tags.add (tag);
      tags_by_style_key[key] = tag;
      return tag;
    }

    /** Applies `tag` to `target`, mapping [run_start, run_end) from the scratch buffer's own line/column coordinates to target's real offsets via `line_start_offsets` — one line at a time, so a run spanning several scratch lines never paints across the gutter prefix sitting between them in `target`. */
    private void paint_run (Gtk.TextIter run_start, Gtk.TextIter run_end, int[] line_start_offsets, Gtk.TextTag tag) {
      int first_line = run_start.get_line ();
      int last_line = run_end.get_line ();

      for (int line_index = first_line; line_index <= last_line; line_index++) {
        if (line_index >= line_start_offsets.length) {
          continue;
        }

        int start_column = (line_index == first_line) ? run_start.get_line_offset () : 0;
        int end_column;
        if (line_index == last_line) {
          end_column = run_end.get_line_offset ();
        } else {
          Gtk.TextIter line_end;
          scratch.get_iter_at_line (out line_end, line_index);
          line_end.forward_to_line_end ();
          end_column = line_end.get_line_offset ();
        }

        if (end_column <= start_column) {
          continue;
        }

        int target_start = line_start_offsets[line_index] + start_column;
        int target_end = line_start_offsets[line_index] + end_column;

        Gtk.TextIter target_start_iter;
        Gtk.TextIter target_end_iter;
        target.get_iter_at_offset (out target_start_iter, target_start);
        target.get_iter_at_offset (out target_end_iter, target_end);
        target.apply_tag (tag, target_start_iter, target_end_iter);
      }
    }
  }
}
