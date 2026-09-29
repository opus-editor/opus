/**
 * Renders one FindInFilesSearch.run() result as read-only text — per
 * file a header line and its own matched blocks, each line prefixed
 * with its own line number. The "N results in M files" count lives in
 * `header_label` above the body, not duplicated as its own opening
 * line. Its own structural styling (filename/line-number-prefix/match)
 * is plain manual Gtk.TextTag application, the same technique
 * text-editor/_search.vala already uses for match highlighting — no
 * custom GtkSourceView `.lang` grammar file, since one wouldn't add any
 * real capability here (the per-file code coloring below has to be
 * manual tag copying regardless, see FindResultsLanguageHighlighter's
 * own doc comment for why).
 *
 * A brand-new View, not a read-only mode bolted onto the shared
 * TextEditor: EditorPane's TextEditor is one widget reused across every
 * tab with no header slot at all, and this tab needs its own (the
 * results count, plus Replace's own dialog trigger and context_lines'
 * controls; a real "Where" scope filter is still a later part of this
 * same feature — see `_language-highlighter.vala`'s own directory for
 * where a further split, `_header.vala`, would live if this grows).
 */
namespace EditorView.EditorPane_ {
  public class FindResults : Object {
    private Gtk.Box root;
    private Gtk.Label header_label;
    private Gtk.Button replace_button;
    private Gtk.Entry context_lines_entry;
    private Gtk.ToggleButton context_lines_toggle;
    private Gtk.ScrolledWindow scrolled_window;
    private GtkSource.View results_view;
    private GtkSource.Buffer results_buffer { get { return (GtkSource.Buffer) results_view.buffer; } }
    private FindResultsLanguageHighlighter language_highlighter;

    private Gtk.TextTag filename_tag;
    private Gtk.TextTag line_number_tag;
    private Gtk.TextTag match_highlight_tag;

    // Whichever of these two is non-null drives render() — kept around
    // so a theme change alone (no new search) can re-render with fresh
    // colors, same reasoning as TextEditorSearch's own apply_theme_colors().
    private FindInFilesResult? last_result = null;
    private FindInFilesQuery? last_error_query = null;
    private string? last_error_message = null;

    public Gtk.Widget widget { get { return root; } }

    /**
     * Lines of context (above and below a match) the *next* search
     * should use — read by EditorPane.search_in_files() when it (re)runs.
     * No upper bound: checked VS Code's own real equivalent
     * (search.searchEditor.defaultNumberOfContextLines/contextLinesInput
     * in searchWidget.ts) — neither its settings schema nor its
     * increment/decrement command impose one either, only a floor at 0
     * (a "-" in the entry gets reset the same way). 0 whenever
     * context_lines_toggle is off, same "unchecked doesn't clear the
     * number, just searches with none" split as VS Code's own
     * showContextToggle.
     */
    public int context_lines {
      get { return context_lines_toggle.active ? int.max (0, int.parse (context_lines_entry.text)) : 0; }
    }

    /** The entry's value or the toggle changed — EditorPane re-runs the last search with the new context_lines. */
    public signal void context_lines_changed ();

    // Non-null exactly while showing a "just ran Replace All" summary
    // instead of a plain search result — the paths FindInFilesReplace.
    // run() left untouched (modified after the search ran), read by
    // render() to skip them from the file listing (their own last-known
    // blocks are no longer guaranteed to match what's on disk — see
    // FindInFilesResult.searched_at's own doc comment) and to show which
    // outcome text applies. Reset back to null by the next real search
    // (show_results()/show_error()) — a fresh search is what a plain
    // result goes back to showing.
    private GenericArray<string>? replace_summary_skipped_paths = null;

    public FindResults () {
      var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/editor-view/editor-pane/find-results/index.ui");
      root = (Gtk.Box) builder.get_object ("root");
      header_label = (Gtk.Label) builder.get_object ("header_label");
      replace_button = (Gtk.Button) builder.get_object ("replace_button");
      context_lines_entry = (Gtk.Entry) builder.get_object ("context_lines_entry");
      context_lines_toggle = (Gtk.ToggleButton) builder.get_object ("context_lines_toggle");
      scrolled_window = (Gtk.ScrolledWindow) builder.get_object ("scrolled_window");

      replace_button.clicked.connect (() => on_replace_button_clicked.begin ());

      // Only on Enter, not on every keystroke like VS Code's own
      // onDidChange — a fresh cross-file disk search per digit typed
      // would be a real, felt cost here (no ripgrep backing this one,
      // see the conversation this came out of on search performance).
      context_lines_entry.activate.connect (() => context_lines_changed ());
      context_lines_toggle.toggled.connect (() => context_lines_changed ());
      // Same floor as VS Code's own contextLinesInput — a typed "-"
      // resets to "0" immediately rather than letting a negative value
      // sit there until Enter is pressed.
      context_lines_entry.changed.connect (() => {
        if (context_lines_entry.text.contains ("-")) {
          context_lines_entry.text = "0";
        }
      });

      results_view = new GtkSource.View () {
        editable = false,
        cursor_visible = false,
        monospace = true,
        top_margin = 8,
        bottom_margin = 8,
        left_margin = 8,
        right_margin = 8,
        wrap_mode = Gtk.WrapMode.NONE,
      };
      scrolled_window.set_child (results_view);

      language_highlighter = new FindResultsLanguageHighlighter (results_buffer);
      install_css ();

      filename_tag = new Gtk.TextTag (null);
      line_number_tag = new Gtk.TextTag (null);
      match_highlight_tag = new Gtk.TextTag (null);
      results_buffer.tag_table.add (filename_tag);
      results_buffer.tag_table.add (line_number_tag);
      results_buffer.tag_table.add (match_highlight_tag);

      var style_manager = Adw.StyleManager.get_default ();
      style_manager.notify["dark"].connect (() => apply_style_scheme (style_manager.dark));
      apply_style_scheme (style_manager.dark);
    }

    public void show_results (FindInFilesResult result) {
      last_result = result;
      last_error_query = null;
      last_error_message = null;
      replace_summary_skipped_paths = null;
      // A fresh search's own matches are real again (unlike whatever's
      // currently tracked after a replace, which repeating Replace All
      // as-is can't safely act on yet — see the conversation this came
      // out of) — hidden below once Replace All actually runs, back for
      // a real new search.
      replace_button.visible = true;
      render ();
    }

    public void show_error (FindInFilesQuery query, string message) {
      last_result = null;
      last_error_query = query;
      last_error_message = message;
      replace_summary_skipped_paths = null;
      replace_button.visible = true;
      render ();
    }

    /** Rules themselves live in styles/find-results.css, not here — see GlobalCss.install_from_resource()'s own doc comment for why. */
    private void install_css () {
      GlobalCss.install_from_resource ("/io/github/nowaos/Opus/styles/find-results.css");
    }

    /**
     * A centered Adw.AlertDialog, same pattern as every other modal in
     * this app (TabBar/ExplorerPane's own confirm_* dialogs, MainWindow's
     * show_error()) — not a Gtk.Popover bubble anchored to the button.
     * A no-op with nothing currently shown (no result to replace into).
     */
    private async void on_replace_button_clicked () {
      if (last_result == null) {
        return;
      }

      var dialog = new Adw.AlertDialog (_("Replace All"), replace_all_body_text (last_result));
      var entry = new Gtk.Entry () {
        placeholder_text = _("Replace"),
        // Routes plain Return in this entry to the dialog's own default
        // response below, the same way any GTK dialog's body already
        // works — no signal wiring of our own needed for that.
        activates_default = true,
      };
      dialog.extra_child = entry;
      dialog.add_response ("cancel", _("Cancel"));
      dialog.add_response ("replace", _("Replace All"));
      dialog.set_response_appearance ("replace", Adw.ResponseAppearance.SUGGESTED);
      dialog.set_default_response ("replace");
      dialog.set_close_response ("cancel");
      // Adw.AlertDialog otherwise focuses its own default response
      // button once shown — grabbed here, after mapping (so this runs
      // after that default focus assignment, not before it), to win the
      // typing focus for the entry instead.
      dialog.map.connect (() => entry.grab_focus ());

      var response = yield dialog.choose (widget, null);
      if (response != "replace") {
        return;
      }

      try {
        var outcome = FindInFilesReplace.run (last_result, entry.text);
        apply_replace_outcome (outcome);
      } catch (Error e) {
        show_replace_error (e.message);
      }
    }

    /** Same shape as MainWindow.show_error()/ExplorerPane's own error dialogs — a plain OK-only Adw.AlertDialog. */
    private void show_replace_error (string message) {
      var dialog = new Adw.AlertDialog (_("Error"), message);
      dialog.add_response ("ok", _("OK"));
      dialog.present (widget);
    }

    /**
     * Reconciles `last_result` in place with what FindInFilesReplace.
     * run() actually wrote, then re-renders showing the outcome — no
     * round-trip through EditorPane needed: everything this touches
     * already lives on last_result, and re-running the original search
     * afterward would search for the *old* term, no longer there to find.
     * Each updated file's own blocks are refreshed straight off disk
     * (not re-derived from the edit itself) so what renders next is
     * guaranteed to match what's really written, per FindInFilesReplace's
     * own new_matches_by_path — see its doc comment for why that's
     * already exactly where each replacement landed, no re-search needed.
     */
    private void apply_replace_outcome (FindInFilesReplaceResult outcome) {
      foreach (var file in last_result.files) {
        if (path_in (outcome.skipped_paths, file.path)) {
          continue;
        }

        string contents;
        try {
          FileUtils.get_contents (file.path, out contents);
        } catch (Error e) {
          continue; // vanished/unreadable right after our own write — leave its last-known blocks as-is
        }
        var fresh_lines = contents.split ("\n");
        var new_matches = outcome.new_matches_by_path[file.path];

        foreach (var block in file.blocks) {
          int slice_start = block.start_line - 1;
          if (slice_start >= fresh_lines.length) {
            continue;
          }
          int slice_end = int.min (slice_start + block.lines.length, fresh_lines.length);
          block.lines = fresh_lines[slice_start:slice_end];

          var block_matches = new GenericArray<FindInFilesMatch> ();
          if (new_matches != null) {
            foreach (var match in new_matches) {
              if (match.line_number >= block.start_line && match.line_number < block.start_line + block.lines.length) {
                block_matches.add (match);
              }
            }
          }
          block.matches = block_matches;
        }
      }

      replace_summary_skipped_paths = outcome.skipped_paths;
      // Clicking Replace All again right now would silently do nothing
      // — result.query's own regex was already matched against and
      // replaced, so it no longer matches what's here (repeating a
      // replace against the *new* tracked text is a real feature, just
      // not this one yet — see the conversation this came out of).
      // Hidden until the next real search brings it back.
      replace_button.visible = false;
      render ();
    }

    private bool path_in (GenericArray<string> paths, string path) {
      for (uint i = 0; i < paths.length; i++) {
        if (paths[i] == path) {
          return true;
        }
      }
      return false;
    }

    /** "This will replace “<query>” N times in M files." — same pluralization style as summary_label_for()'s own "N results in M files". */
    private string replace_all_body_text (FindInFilesResult result) {
      return _("This will replace “%s” %d %s in %d %s.").printf (
        result.query.text,
        result.total_match_count, result.total_match_count == 1 ? _("time") : _("times"),
        result.file_count, result.file_count == 1 ? _("file") : _("files")
      );
    }

    private void apply_style_scheme (bool dark) {
      var scheme_id = dark ? "Adwaita-dark" : "Adwaita";
      results_buffer.style_scheme = GtkSource.StyleSchemeManager.get_default ().get_scheme (scheme_id);

      filename_tag.weight = Pango.Weight.BOLD;

      // Dims toward the pane's own real (theme-resolved) text color,
      // rather than a hardcoded gray, so it reads correctly in both
      // light and dark without its own light/dark branch.
      var line_number_color = results_view.get_color ();
      line_number_color.alpha = dark ? 0.75f : 0.55f;
      line_number_tag.foreground_rgba = line_number_color;

      // Same technique TextEditorSearch's own apply_theme_colors() uses
      // for its match highlight, for visual consistency with in-file Find.
      var match_background = SystemColor.from_accent ().desaturate (dark ? 0.10f : 0.05f).to_rgba ();
      match_background.alpha = 0.30f;
      match_highlight_tag.background_rgba = match_background;

      // Re-render with the new colors if there's anything currently shown.
      if (last_result != null || last_error_message != null) {
        render ();
      }
    }

    private class TagRange : Object {
      public int start;
      public int end;
      public Gtk.TextTag tag;
    }

    private class PendingHighlight : Object {
      public string path;
      public string snippet;
      public int[] line_start_offsets;
    }

    private void render () {
      language_highlighter.clear ();

      if (last_error_message != null) {
        header_label.label = last_error_query.text;
        results_buffer.text = last_error_message;
        return;
      }
      if (last_result == null) {
        header_label.label = "";
        results_buffer.text = "";
        return;
      }

      var result = last_result;
      header_label.label = summary_label_for (result);

      var text = new StringBuilder ();
      var structural_ranges = new GenericArray<TagRange> ();
      var match_ranges = new GenericArray<TagRange> ();
      var pending_highlights = new GenericArray<PendingHighlight> ();
      int offset = 0;

      if (replace_summary_skipped_paths != null) {
        offset = append_replace_summary (text, structural_ranges, offset, replace_summary_skipped_paths);
      }

      foreach (var file in result.files) {
        // Its own blocks are the pre-replace ones — no longer guaranteed
        // to match what's on disk (that's exactly why it was skipped —
        // see FindInFilesResult.searched_at's own doc comment), so it's
        // named in the skipped list above instead of shown here.
        if (replace_summary_skipped_paths != null && path_in (replace_summary_skipped_paths, file.path)) {
          continue;
        }

        int filename_start = offset;
        text.append (file.path);
        offset += file.path.char_count ();
        structural_ranges.add (new TagRange () { start = filename_start, end = offset, tag = filename_tag });
        text.append (":\n");
        offset += 2;

        for (uint block_index = 0; block_index < file.blocks.length; block_index++) {
          var block = file.blocks[block_index];
          var line_start_offsets = new int[block.lines.length];
          for (int i = 0; i < block.lines.length; i++) {
            var line_number = block.start_line + i;
            var prefix = "  %d: ".printf (line_number);
            int prefix_start = offset;
            text.append (prefix);
            offset += prefix.char_count ();
            structural_ranges.add (new TagRange () { start = prefix_start, end = offset, tag = line_number_tag });

            line_start_offsets[i] = offset;
            text.append (block.lines[i]);
            offset += block.lines[i].char_count ();
            text.append ("\n");
            offset += 1;
          }

          var highlight_request = new PendingHighlight ();
          highlight_request.path = file.path;
          highlight_request.snippet = string.joinv ("\n", block.lines);
          highlight_request.line_start_offsets = line_start_offsets;
          pending_highlights.add (highlight_request);

          foreach (var match in block.matches) {
            var line_index = match.line_number - block.start_line;
            if (line_index < 0 || line_index >= line_start_offsets.length) {
              continue;
            }
            match_ranges.add (new TagRange () {
              start = line_start_offsets[line_index] + match.start_column,
              end = line_start_offsets[line_index] + match.end_column,
              tag = match_highlight_tag,
            });
          }

          // A blank line always separates files, but only separates two
          // blocks within the *same* file when there's real context to
          // show — with none, every match in a file is already a flat
          // list (same as VS Code's own Search Editor with "Show
          // Context Lines" off; a blank line there would just read as
          // gaps between hits that aren't actually there).
          bool is_last_block_in_file = block_index == file.blocks.length - 1;
          if (is_last_block_in_file || result.context_lines > 0) {
            text.append ("\n");
            offset += 1;
          }
        }
      }

      results_buffer.text = text.str;

      foreach (var range in structural_ranges) {
        apply_range (range);
      }
      foreach (var request in pending_highlights) {
        language_highlighter.highlight (request.path, request.snippet, request.line_start_offsets);
      }
      foreach (var range in match_ranges) {
        apply_range (range);
      }

      // Wins any background-color collision against a per-file language
      // tag — this is about matches, not per-file language, so it stays
      // here, not in the highlighter.
      match_highlight_tag.set_priority (results_buffer.tag_table.get_size () - 1);
    }

    /**
     * The Replace All outcome, prepended above the (filtered) file
     * listing — two variants, matching whether anything had to be
     * skipped. Returns the offset past whatever it appended, same
     * "in, mutate, return the new cursor" shape every other section of
     * render() already threads offset through.
     */
    private int append_replace_summary (StringBuilder text, GenericArray<TagRange> structural_ranges, int offset, GenericArray<string> skipped_paths) {
      string intro = skipped_paths.length == 0
        ? _("All files were updated.")
        : _("Some files were modified after the search and were left untouched:");

      int intro_start = offset;
      text.append (intro);
      offset += intro.char_count ();
      structural_ranges.add (new TagRange () { start = intro_start, end = offset, tag = filename_tag });
      text.append ("\n\n");
      offset += 2;

      if (skipped_paths.length == 0) {
        return offset;
      }

      foreach (var path in skipped_paths) {
        var line = "  - %s\n".printf (path);
        text.append (line);
        offset += line.char_count ();
      }
      text.append ("\n");
      offset += 1;

      string updated_intro = _("The following files were updated:");
      int updated_start = offset;
      text.append (updated_intro);
      offset += updated_intro.char_count ();
      structural_ranges.add (new TagRange () { start = updated_start, end = offset, tag = filename_tag });
      text.append ("\n\n");
      offset += 2;

      return offset;
    }

    /** "N results in M files" — the header's own line now; previously duplicated as the results body's own opening line. */
    private string summary_label_for (FindInFilesResult result) {
      return "%d %s in %d %s%s".printf (
        result.total_match_count, result.total_match_count == 1 ? _("result") : _("results"),
        result.file_count, result.file_count == 1 ? _("file") : _("files"),
        result.truncated ? _(" (truncated)") : ""
      );
    }

    private void apply_range (TagRange range) {
      Gtk.TextIter start_iter;
      Gtk.TextIter end_iter;
      results_buffer.get_iter_at_offset (out start_iter, range.start);
      results_buffer.get_iter_at_offset (out end_iter, range.end);
      results_buffer.apply_tag (range.tag, start_iter, end_iter);
    }
  }
}
