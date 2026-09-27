namespace EditorView.EditorPane_ {
  /** One live search match's own [start, end) offsets — see TextEditorSearch.enumerate_matches(). Never exposed past this file. */
  private class MatchRange : Object {
    public int start_offset;
    public int end_offset;
  }

  /**
   * Find/Replace mechanics, split out of TextEditor the same way
   * TextEditorCursors/TextEditorDragSelection already are — matches VS
   * Code's own real split too: findModel.ts/findDecorations.ts (the actual
   * search mechanics over the buffer) are separate files from
   * findWidget.ts (the visual bar) and findController.ts (the mediator).
   * Composed by TextEditor, alongside cursors/drag_selection — all three
   * only ever need text_view/source_buffer, nothing about them overlaps.
   *
   * This is the "text-editor side" only — the actual search bar
   * (EditorView.FindBar) is a completely separate top-level View, not
   * something this class or TextEditor own. Whatever composes both wires
   * them directly (this class's own search_position_changed to FindBar's
   * match counter, FindBar's own text/option/next/previous signals to
   * TextEditor's pass-through methods below) — the same shape TabBar<->
   * FileTree's "Reveal in Sidebar" already uses in main.vala today, no
   * Controller in between.
   *
   * Reacts to Adw.StyleManager for its own two tags' colors directly —
   * same shape VS Code's own registerThemingParticipant gets, right in
   * viewCursors.ts (checked its source): each concern styles only what it
   * itself owns, no separate "theme" object reaching into siblings.
   */
  public class TextEditorSearch : Object {
    private const string SEARCH_MATCH_TAG_NAME = "search-match";
    private const string SEARCH_CURRENT_MATCH_TAG_NAME = "search-current-match";

    private TextEditorSourceView text_view;
    private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }

    private GtkSource.SearchSettings search_settings;
    private GtkSource.SearchContext search_context;
    private Gtk.TextTag search_match_tag;
    private Gtk.TextTag search_current_match_tag;

    // Anchors the current match's range through buffer edits, so Next/
    // Previous knows where to resume searching from. Null when there's no
    // current match right now.
    private Gtk.TextMark? current_match_start_mark = null;
    private Gtk.TextMark? current_match_end_mark = null;

    // A second, independent pair — set alongside current_match_start/
    // end_mark whenever a match is actually found, but never cleared just
    // because the live search state itself clears. select_last_match()
    // is what this pair is still there for once the bar has closed.
    private Gtk.TextMark? last_match_start_mark = null;
    private Gtk.TextMark? last_match_end_mark = null;

    /** The live Find search's current match moved. `position` is 1-based, `count` the total live occurrence count; both 0 once nothing matches. */
    public signal void search_position_changed (int position, int count);

    public TextEditorSearch (TextEditorSourceView text_view) {
      this.text_view = text_view;

      // GtkSourceSearchContext's own real doc comment is explicit: "the
      // concept of 'current match' doesn't exist yet" — one match_style
      // for every occurrence, no second color for the current one. Its own
      // highlighting is left off entirely (set_highlight (false)) and both
      // colors are painted by hand instead, through two tags of our own.
      search_settings = new GtkSource.SearchSettings ();
      search_settings.set_wrap_around (true);
      search_context = new GtkSource.SearchContext (source_buffer, search_settings);
      search_context.set_highlight (false);
      search_context.notify["occurrences-count"].connect (() => refresh_search_match_tags ());

      search_match_tag = new Gtk.TextTag (SEARCH_MATCH_TAG_NAME);
      search_match_tag.background_set = true;
      source_buffer.tag_table.add (search_match_tag);
      // Added after search_match_tag, so it wins the tie for whichever
      // range is both a match and *the* current one — a tag's priority is
      // its position in the tag table, highest priority last added.
      search_current_match_tag = new Gtk.TextTag (SEARCH_CURRENT_MATCH_TAG_NAME);
      search_current_match_tag.background_set = true;
      source_buffer.tag_table.add (search_current_match_tag);

      // Own registration, same shape VS Code's registerThemingParticipant
      // gets in viewCursors.ts (checked its source) — this class reacts to
      // the app's theme for its own two tags' colors, no separate "theme"
      // object reaching in from outside.
      var style_manager = Adw.StyleManager.get_default ();
      style_manager.notify["dark"].connect (() => apply_theme_colors (style_manager.dark));
      apply_theme_colors (style_manager.dark);
    }

    /**
     * A light desaturation (not cursors' own full grayscale) — enough to
     * read as visually distinct from the accent-colored selection, without
     * draining the accent away entirely. Dark gets double light's amount:
     * the same darker background these highlights sit on already reads
     * any given desaturation as more washed-out, so it needs more of it to
     * look equally "toned down".
     */
    private void apply_theme_colors (bool dark) {
      // .to_rgba() here, not chained further: search_match_background/
      // search_current_match_background each need their own independent
      // alpha off this same base — a plain Gdk.RGBA (a value type) copies
      // safely on assignment, where branching two .transparentize() calls
      // off the same SystemColor instance would mutate one shared object
      // instead.
      var search_base = SystemColor.from_accent ().desaturate (dark ? 0.10f : 0.05f).to_rgba ();
      var search_match_background = search_base;
      search_match_background.alpha = 0.30f;
      var search_current_match_background = search_base;
      search_current_match_background.alpha = 0.60f;
      search_match_tag.background_rgba = search_match_background;
      search_current_match_tag.background_rgba = search_current_match_background;
    }

    /** Nothing to unregister — same reasoning as TextEditor.close(), see its own comment. */
    public void close () {
    }

    /** "" clears the search (no match, no highlight) rather than matching everything. Also re-lands on the nearest match from the real caret. */
    public void set_search_text (string text) {
      search_settings.set_search_text (text == "" ? null : text);
      jump_to_nearest_match ();
    }

    /** Regular Expressions/Case Sensitive/Match Whole Word Only changed — re-lands on the nearest match, since any of the three can change which text now counts as a match. */
    public void set_search_options (bool regex, bool case_sensitive, bool whole_word) {
      search_settings.set_regex_enabled (regex);
      search_settings.set_case_sensitive (case_sensitive);
      search_settings.set_at_word_boundaries (whole_word);
      jump_to_nearest_match ();
    }

    /** Next Match — wraps to the first occurrence past the end of the buffer, via search_settings.set_wrap_around(true) above (not GtkSourceSearchContext's own default, which is false — see the constructor's own comment on that call). */
    public void search_next () {
      move_to_match (true);
    }

    /** Previous Match. */
    public void search_previous () {
      move_to_match (false);
    }

    /** Builds the one TextEdit needed to replace the current match with `replacement` — null if there's no current match right now. Purely computes; whoever calls this applies the result. */
    public TextEdit? compute_replace_current_match (string replacement) {
      Gtk.TextIter start;
      Gtk.TextIter end;
      if (!get_current_match (out start, out end)) {
        return null;
      }

      var pattern = ReplacePattern.parse (replacement, search_settings.get_regex_enabled ());
      return build_replace_edit (start.get_offset (), end.get_offset (), pattern);
    }

    /** Builds one TextEdit per live match. Empty with no active search/no matches. */
    public TextEdit[] compute_replace_all (string replacement) {
      var ranges = enumerate_matches ();
      var pattern = ReplacePattern.parse (replacement, search_settings.get_regex_enabled ());

      var edits = new TextEdit[ranges.length];
      for (int i = 0; i < ranges.length; i++) {
        edits[i] = build_replace_edit (ranges[i].start_offset, ranges[i].end_offset, pattern);
      }
      return edits;
    }

    /** "Replace"'s own follow-up, once the edit compute_replace_current_match() built has actually been applied: lands on the next match starting right after the just-inserted replacement text. */
    public void land_after_replace (int replaced_end_offset) {
      Gtk.TextIter from;
      source_buffer.get_iter_at_offset (out from, replaced_end_offset);
      land_on_match (from, true);
    }

    /** Replace All's own follow-up: there's no single "next" match to land on afterward. */
    public void forget_current_match () {
      clear_current_match ();
    }

    /** Closing the Find bar with a match still live-highlighted hands it off to the real selection, with real keyboard focus. A no-op if nothing was ever found this search. */
    public void select_last_match () {
      if (last_match_start_mark == null) {
        return;
      }

      Gtk.TextIter start;
      Gtk.TextIter end;
      source_buffer.get_iter_at_mark (out start, last_match_start_mark);
      source_buffer.get_iter_at_mark (out end, last_match_end_mark);
      source_buffer.select_range (end, start);
      text_view.grab_focus ();

      source_buffer.delete_mark (last_match_start_mark);
      source_buffer.delete_mark (last_match_end_mark);
      last_match_start_mark = null;
      last_match_end_mark = null;
    }

    /** set_search_text()/set_search_options()'s own shared "land on whatever's nearest" behavior — from the real selection's own start when there is one (not the caret), falling back to the caret with none. */
    private void jump_to_nearest_match () {
      Gtk.TextIter from;
      Gtk.TextIter selection_end;
      if (!source_buffer.get_selection_bounds (out from, out selection_end)) {
        source_buffer.get_iter_at_mark (out from, source_buffer.get_insert ());
      }
      land_on_match (from, true);
    }

    /** Next/Previous — resumes from wherever the current match already ends/starts, falling back to the real caret only when there's no current match yet. */
    private void move_to_match (bool forward) {
      Gtk.TextIter from;
      Gtk.TextIter current_start;
      Gtk.TextIter current_end;
      if (get_current_match (out current_start, out current_end)) {
        from = forward ? current_end : current_start;
      } else {
        source_buffer.get_iter_at_mark (out from, source_buffer.get_insert ());
      }
      land_on_match (from, forward);
    }

    private void land_on_match (Gtk.TextIter from, bool forward) {
      Gtk.TextIter match_start;
      Gtk.TextIter match_end;
      bool wrapped;
      bool found = forward
        ? search_context.forward (from, out match_start, out match_end, out wrapped)
        : search_context.backward (from, out match_start, out match_end, out wrapped);

      if (found) {
        set_current_match (match_start, match_end);
        text_view.scroll_to_iter (match_start, 0.1, false, 0, 0);
        search_position_changed (search_context.get_occurrence_position (match_start, match_end), search_context.get_occurrences_count ());
      } else {
        clear_current_match ();
        search_position_changed (0, search_context.get_occurrences_count ());
      }
    }

    /** Paints `start`..`end` as the one current match and anchors the marks move_to_match()/select_last_match() need. Deliberately never touches the real insert/selection_bound marks: Find navigation is purely visual until select_last_match() deliberately hands it off. */
    private void set_current_match (Gtk.TextIter start, Gtk.TextIter end) {
      Gtk.TextIter buffer_start;
      Gtk.TextIter buffer_end;
      source_buffer.get_start_iter (out buffer_start);
      source_buffer.get_end_iter (out buffer_end);
      source_buffer.remove_tag (search_current_match_tag, buffer_start, buffer_end);
      source_buffer.apply_tag (search_current_match_tag, start, end);

      if (current_match_start_mark == null) {
        current_match_start_mark = source_buffer.create_mark (null, start, true);
        current_match_end_mark = source_buffer.create_mark (null, end, false);
      } else {
        source_buffer.move_mark (current_match_start_mark, start);
        source_buffer.move_mark (current_match_end_mark, end);
      }

      if (last_match_start_mark == null) {
        last_match_start_mark = source_buffer.create_mark (null, start, true);
        last_match_end_mark = source_buffer.create_mark (null, end, false);
      } else {
        source_buffer.move_mark (last_match_start_mark, start);
        source_buffer.move_mark (last_match_end_mark, end);
      }
    }

    private void clear_current_match () {
      if (current_match_start_mark != null) {
        source_buffer.delete_mark (current_match_start_mark);
        source_buffer.delete_mark (current_match_end_mark);
        current_match_start_mark = null;
        current_match_end_mark = null;
      }

      Gtk.TextIter buffer_start;
      Gtk.TextIter buffer_end;
      source_buffer.get_start_iter (out buffer_start);
      source_buffer.get_end_iter (out buffer_end);
      source_buffer.remove_tag (search_current_match_tag, buffer_start, buffer_end);
    }

    private bool get_current_match (out Gtk.TextIter start, out Gtk.TextIter end) {
      if (current_match_start_mark == null) {
        start = Gtk.TextIter ();
        end = Gtk.TextIter ();
        return false;
      }

      source_buffer.get_iter_at_mark (out start, current_match_start_mark);
      source_buffer.get_iter_at_mark (out end, current_match_end_mark);
      return true;
    }

    /** Re-tags every live occurrence — run whenever search_context's own occurrences-count changes (a fresh search, an option toggle, or the buffer being edited while the bar is open all invalidate its internal scan the same way). */
    private void refresh_search_match_tags () {
      Gtk.TextIter buffer_start;
      Gtk.TextIter buffer_end;
      source_buffer.get_start_iter (out buffer_start);
      source_buffer.get_end_iter (out buffer_end);
      source_buffer.remove_tag (search_match_tag, buffer_start, buffer_end);

      foreach (var range in enumerate_matches ()) {
        Gtk.TextIter start;
        Gtk.TextIter end;
        source_buffer.get_iter_at_offset (out start, range.start_offset);
        source_buffer.get_iter_at_offset (out end, range.end_offset);
        source_buffer.apply_tag (search_match_tag, start, end);
      }
    }

    /** Every live match's own [start, end) offsets, in document order — there's no bulk "every match" API (SearchContext only exposes forward/backward), so this collects them one at a time, stopping once the walk cycles back to wherever it started. */
    private MatchRange[] enumerate_matches () {
      var result = new GenericArray<MatchRange> ();
      if (search_settings.get_search_text () == null) {
        return {};
      }

      Gtk.TextIter buffer_start;
      source_buffer.get_start_iter (out buffer_start);

      var iter = buffer_start;
      int first_match_offset = -1;
      while (true) {
        Gtk.TextIter match_start;
        Gtk.TextIter match_end;
        bool wrapped;
        if (!search_context.forward (iter, out match_start, out match_end, out wrapped)) {
          break;
        }
        if (first_match_offset == -1) {
          first_match_offset = match_start.get_offset ();
        } else if (match_start.get_offset () == first_match_offset) {
          break;
        }

        var range = new MatchRange ();
        range.start_offset = match_start.get_offset ();
        range.end_offset = match_end.get_offset ();
        result.add (range);

        iter = match_end;
      }

      var arr = new MatchRange[result.length];
      for (uint i = 0; i < result.length; i++) {
        arr[i] = result[i];
      }
      return arr;
    }

    private TextEdit build_replace_edit (int start_offset, int end_offset, ReplacePattern pattern) {
      Gtk.TextIter start;
      Gtk.TextIter end;
      source_buffer.get_iter_at_offset (out start, start_offset);
      source_buffer.get_iter_at_offset (out end, end_offset);
      string matched_text = source_buffer.get_text (start, end, false);

      string[] groups;
      if (pattern.has_replacement_patterns) {
        groups = capture_groups (matched_text);
      } else {
        groups = { matched_text };
      }

      var edit = new TextEdit ();
      edit.start_offset = start_offset;
      edit.end_offset = end_offset;
      edit.old_text = matched_text;
      edit.new_text = pattern.build (groups);
      return edit;
    }

    /** Re-matches `matched_text` against the live search pattern with GLib.Regex to recover its own capture groups — GtkSourceSearchContext only ever hands back a match's overall range, never its submatches. */
    private string[] capture_groups (string matched_text) {
      var search_text = search_settings.get_search_text ();
      if (search_text == null) {
        return { matched_text };
      }

      try {
        var flags = search_settings.get_case_sensitive () ? 0 : RegexCompileFlags.CASELESS;
        var regex = new Regex (search_text, flags);
        MatchInfo match_info;
        if (!regex.match (matched_text, 0, out match_info)) {
          return { matched_text };
        }

        var groups = new string[match_info.get_match_count ()];
        for (int i = 0; i < groups.length; i++) {
          groups[i] = match_info.fetch (i) ?? "";
        }
        return groups;
      } catch (RegexError e) {
        return { matched_text };
      }
    }
  }
}
