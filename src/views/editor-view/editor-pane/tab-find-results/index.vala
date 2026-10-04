/**
 * Renders one FindInFilesSearch.run() result as read-only text — per
 * file a header line and its own matched blocks, each line prefixed
 * with its own line number. The "N results in M files" count lives in
 * `header_label` above the body, not duplicated as its own opening
 * line. Its own structural styling (filename/line-number-prefix/match)
 * is plain manual Gtk.TextTag application, the same technique
 * code-editor/_search.vala already uses for match highlighting — no
 * custom GtkSourceView `.lang` grammar file, since one wouldn't add any
 * real capability here (the per-file code coloring below has to be
 * manual tag copying regardless, see TabFindResultsLanguageHighlighter's
 * own doc comment for why).
 *
 * Its own header and Find/Replace row (the results count, the
 * confirmation dialog, context_lines' controls) around an embedded
 * read-only CodeEditor — the same component the file editor is, so
 * multi-cursor selection and copying several result snippets at once
 * work here exactly as they do there, with the editor font and zoom;
 * only editing is refused (see CodeEditor.read_only). Line numbers and
 * indent guides are off: results carry their own "  N: " prefixes.
 */
namespace EditorView.EditorPane {
  public class TabFindResults : Object, ITabKind {
    // Find in Files' own synthetic tab — one per pane, keyed like any
    // other tab so the pane's registry/TabBar machinery needs no second
    // tab concept for it.
    private const string TAB_URI = "opus://find-in-files-results";
    // Only the very first search ever run (no control exists yet to read
    // its own context_lines off) — every search after that reads the
    // live value straight from this tab's own control.
    private const int DEFAULT_CONTEXT_LINES = 1;

    // render()'s own "  N: " line-number prefix pads every number in a
    // file's own listing to at least this many digits (right-aligned),
    // widening per file if its own largest line number needs more —
    // keeps every ":" in that file's block lined up instead of drifting
    // with each digit a line number gains, without doing it globally
    // across unrelated files that have no reason to share a column.
    private const int MIN_LINE_NUMBER_WIDTH = 3;

    private Gtk.Box root;
    private Gtk.Label header_label;
    private Gtk.ToggleButton replace_button;
    private Gtk.Revealer replace_revealer;
    private Gtk.Text find_text;
    private Gtk.Box find_icons;
    private Gtk.Text replace_text;
    private Gtk.Button replace_confirm_button;
    private Gtk.Entry context_lines_entry;
    private Gtk.ToggleButton context_lines_toggle;
    private CodeEditor code_editor;
    /** The editor's own buffer — for the tags below and the highlighter only; content goes in through code_editor.set_text(). */
    private GtkSource.Buffer results_buffer { get { return code_editor.buffer; } }
    private TabFindResultsLanguageHighlighter language_highlighter;

    private Gtk.TextTag filename_tag;
    private Gtk.TextTag line_number_tag;
    private Gtk.TextTag match_highlight_tag;

    /** One real Gtk.TextTag per clickable span (a filename header, a result line, a skipped-mtime path) — carries no styling of its own, just a NavTarget via set_data(), so a click/hover only has to ask "what tag is at this offset" instead of keeping a side index in sync with render(). */
    private class NavTarget : Object {
      public string path;
      // -1 means "just open the file, don't move the caret" — the
      // skipped-mtime list's own last-known position isn't trustworthy
      // (that's exactly why it was skipped).
      public int line;
      // Used as-is for a filename header (jumps to the first occurrence,
      // nothing under the click itself maps to a file position) or a
      // skipped-mtime path (ignored — line is already -1). A result
      // line instead derives its real column from *where inside the
      // span* the click landed (see on_link_click()) — this field is 0
      // and unused for those, since the span's code text is a verbatim
      // copy of the file's own line, so offset-into-code already *is*
      // the column, exactly like VS Code's own Search Editor (clicking
      // a result line lands the caret under the actual character
      // clicked, not just at the match's start).
      public int column;
      public bool column_from_click;
      // A result line's span is the *whole* line — the "  N: " prefix,
      // the code, and the newline — so clicking the number, or the empty
      // area right of a short line, still navigates (VS Code's own
      // Search Editor treats the prefix as a "convenience location" for
      // column 0 the same way). These two say where the code sits inside
      // that span: `code_start` chars in, `code_length` chars long.
      public int code_start;
      public int code_length;
    }

    /** Every per-span nav tag render() has created so far — dropped from the tag table at the top of the next render(), same reason TabFindResultsLanguageHighlighter.clear() exists: a fresh render() replaces the text wholesale, so the previous pass's tags would otherwise just pile up unused. */
    private GenericArray<Gtk.TextTag> nav_tags = new GenericArray<Gtk.TextTag> ();

    /** A Ctrl+click landed on a filename or result line — `line` is -1 for "just open" (see NavTarget's own doc comment). The pane wires this to TabDocument.open_at() — opening/jumping is that kind's job, not this one's. */
    public signal void navigate_requested (string path, int line, int column);

    // Recreated on every apply_style_scheme() — the Find/Replace row's own
    // background has to match the editor's *real* GtkSource.StyleScheme
    // color, only known at runtime (see its own doc comment in
    // tab-find-results.css). Same "uninstall the previous one first" pattern
    // CodeEditor's own font_provider already uses, and for the same
    // reason: a provider only ever adds rules, it never un-sets one from
    // an earlier install on its own.
    private Gtk.CssProvider? replace_row_provider = null;

    // Whichever of these two is non-null drives render() — kept around
    // so a theme change alone (no new search) can re-render with fresh
    // colors, same reasoning as CodeEditorSearch's own apply_theme_colors().
    private FindInFilesResult? last_result = null;
    private FindInFilesQuery? last_error_query = null;
    private string? last_error_message = null;

    // The most recently run search, re-issued as-is when the context
    // lines control changes so adjusting it re-searches without the
    // user retyping anything. Replace All has no equivalent hookup:
    // apply_replace_outcome() reconciles last_result in place instead —
    // re-running the original search afterward would search for the
    // *old* term, no longer there to find.
    private string? last_root_path = null;
    private FindInFilesQuery? last_query = null;
    // Bumped on every new search() call (and once more on close()) so a
    // search still running when a newer one starts, or the window
    // closes, never renders its own stale result afterward.
    private int search_generation = 0;
    private bool tab_exists = false;
    private bool is_active = false;

    public Gtk.Widget widget { get { return root; } }
    public TabCapability capabilities { get { return TabCapability.INLINE_REPLACE; } }

    /** The query behind this tab, but only while it's actually the active tab — null otherwise, even if the tab still exists in the background. MainWindow's own Ctrl+Shift+F reads this to decide whether reopening FindInFilesBar should restore the last search or start blank. */
    public FindInFilesQuery? active_query {
      get { return is_active ? last_query : null; }
    }

    /**
     * Lines of context (above and below a match) the *next* search
     * should use — read by search() when it (re)runs.
     * No upper bound: checked VS Code's own real equivalent
     * (search.searchEditor.defaultNumberOfContextLines/contextLinesInput
     * in searchWidget.ts) — neither its settings schema nor its
     * increment/decrement command impose one either, only a floor at 0
     * (a "-" in the entry gets reset the same way). 0 whenever
     * context_lines_toggle is off, same "unchecked doesn't clear the
     * number, just searches with none" split as VS Code's own
     * showContextToggle.
     */
    private int context_lines {
      get { return context_lines_toggle.active ? int.max (0, int.parse (context_lines_entry.text)) : 0; }
    }

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

    public TabFindResults (UserSettings user_settings) {
      var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/editor-view/editor-pane/tab-find-results/index.ui");
      root = (Gtk.Box) builder.get_object ("root");
      header_label = (Gtk.Label) builder.get_object ("header_label");
      replace_button = (Gtk.ToggleButton) builder.get_object ("replace_button");
      replace_revealer = (Gtk.Revealer) builder.get_object ("replace_revealer");
      find_text = (Gtk.Text) builder.get_object ("find_text");
      find_icons = (Gtk.Box) builder.get_object ("find_icons");
      replace_text = (Gtk.Text) builder.get_object ("replace_text");
      replace_confirm_button = (Gtk.Button) builder.get_object ("replace_confirm_button");
      context_lines_entry = (Gtk.Entry) builder.get_object ("context_lines_entry");
      context_lines_toggle = (Gtk.ToggleButton) builder.get_object ("context_lines_toggle");

      replace_button.toggled.connect (on_replace_button_toggled);
      // Mirrors FindBar's own auto-focus-on-reveal (Gtk.SearchBar's real
      // behavior, checked gtksearchbar.c) — fires on every reveal-child
      // flip, but only the closed → open direction has anything worth
      // focusing.
      replace_revealer.notify["reveal-child"].connect (() => {
        if (replace_revealer.reveal_child) {
          replace_text.grab_focus ();
        }
      });

      replace_confirm_button.clicked.connect (() => confirm_and_replace_all.begin ());
      replace_text.activate.connect (() => confirm_and_replace_all.begin ());

      // Escape closes the row and hands focus back to the results —
      // same local, this-widget-only handling _tree-row.vala's own
      // inline-edit entry already uses for its own Escape, not the
      // window-wide IGlobalPanel mechanism (MainWindow's own
      // Escape-closes-whichever-panel-is-open): this row isn't a
      // separate panel, just a sub-part of this already-open tab.
      var replace_text_key_controller = new Gtk.EventControllerKey ();
      replace_text_key_controller.key_pressed.connect ((keyval) => {
        if (keyval != Gdk.Key.Escape) {
          return false;
        }
        replace_button.active = false;
        code_editor.grab_focus ();
        return true;
      });
      replace_text.add_controller (replace_text_key_controller);

      // Only on Enter, not on every keystroke like VS Code's own
      // onDidChange — a fresh cross-file disk search per digit typed
      // would be a real, felt cost here (no ripgrep backing this search).
      context_lines_entry.activate.connect (rerun_last_search);
      context_lines_toggle.toggled.connect (rerun_last_search);
      // Same floor as VS Code's own contextLinesInput — a typed "-"
      // resets to "0" immediately rather than letting a negative value
      // sit there until Enter is pressed.
      context_lines_entry.changed.connect (() => {
        if (context_lines_entry.text.contains ("-")) {
          context_lines_entry.text = "0";
        }
      });

      code_editor = new CodeEditor (user_settings) {
        read_only = true,
        show_line_numbers = false,
        show_indent_guides = false,
      };
      root.append (code_editor.widget);

      language_highlighter = new TabFindResultsLanguageHighlighter (results_buffer);
      install_css ();

      filename_tag = new Gtk.TextTag (null);
      line_number_tag = new Gtk.TextTag (null);
      match_highlight_tag = new Gtk.TextTag (null);
      results_buffer.tag_table.add (filename_tag);
      results_buffer.tag_table.add (line_number_tag);
      results_buffer.tag_table.add (match_highlight_tag);

      code_editor.link_click.connect (on_link_click);

      var style_manager = Adw.StyleManager.get_default ();
      style_manager.notify["dark"].connect (() => apply_style_scheme (style_manager.dark));
      apply_style_scheme (style_manager.dark);
    }

    private void show_results (FindInFilesResult result) {
      last_result = result;
      last_error_query = null;
      last_error_message = null;
      replace_summary_skipped_paths = null;
      // A fresh search's own matches are real again — re-enabled here in
      // case the previous search's own Replace All left them disabled
      // (see apply_replace_outcome()).
      replace_text.sensitive = true;
      replace_confirm_button.sensitive = true;
      context_lines_entry.sensitive = true;
      context_lines_toggle.sensitive = true;
      // A still-open Find/Replace row is talking about the *previous*
      // query — closed here rather than left open with a stale find_text,
      // same reasoning as resetting replace_summary_skipped_paths above.
      // replace_button.active = false first: it's what drives the row
      // via on_replace_button_toggled(), setting reveal_child directly
      // would leave the button's own :checked state stuck showing
      // "pressed" for a row that's actually now closed.
      replace_button.active = false;
      replace_revealer.reveal_child = false;
      render ();
    }

    private void show_error (FindInFilesQuery query, string message) {
      last_result = null;
      last_error_query = query;
      last_error_message = message;
      replace_summary_skipped_paths = null;
      replace_text.sensitive = true;
      replace_confirm_button.sensitive = true;
      context_lines_entry.sensitive = true;
      context_lines_toggle.sensitive = true;
      replace_button.active = false;
      replace_revealer.reveal_child = false;
      render ();
    }

    /** Rules themselves live in styles/tab-find-results.css, not here — see GlobalCss.install_from_resource()'s own doc comment for why. */
    private void install_css () {
      GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/tab-find-results.css");
    }

    /**
     * Find in Files — searches `root_path` for `query.text` and shows
     * the results here, opening this tab (or re-activating it if already
     * open). A no-op with an empty query. `search_generation` is bumped
     * before awaiting the actual search so a second call started before
     * the first finishes supersedes it outright — whichever finishes
     * last simply discards its own result instead of clobbering a newer
     * one.
     */
    public async void search (string root_path, FindInFilesQuery query) {
      if (query.text == "") {
        return;
      }
      last_root_path = root_path;
      last_query = query;
      int generation = ++search_generation;
      int lines = tab_exists ? context_lines : DEFAULT_CONTEXT_LINES;

      FindInFilesResult? result = null;
      Error? error = null;
      try {
        result = yield FindInFilesSearch.run_async (root_path, query, lines);
      } catch (Error e) {
        error = e;
      }
      if (generation != search_generation) {
        return;
      }

      if (error != null) {
        show_error (query, error.message);
      } else {
        show_results (result);
      }
      open_or_focus_tab ();
    }

    private void open_or_focus_tab () {
      if (!tab_exists) {
        tab_exists = true;
        tab_added (TAB_URI, _("Find Results"), "", false, _("Find Results"), false);
      }
      activate_requested (TAB_URI);
    }

    private void rerun_last_search () {
      if (last_query != null) {
        search.begin (last_root_path, last_query);
      }
    }

    public bool owns (string uri) {
      return uri == TAB_URI;
    }

    public bool is_dirty (string uri) {
      return false;
    }

    public void show (string uri) {
      is_active = true;
    }

    public void hide () {
      is_active = false;
    }

    /** Nothing to confirm — the results live only here and are regenerated by the next search. */
    public async void close_tab (string uri) {
      if (!tab_exists) {
        return;
      }
      tab_exists = false;
      is_active = false;
      tab_removed (TAB_URI);
    }

    /** Discards any search still in flight — see search()'s own doc comment for what search_generation guards against. */
    public void close () {
      search_generation++;
    }

    // Zoom is one shared level across every CodeEditor (see its own
    // static zoom_level) — overridden here anyway so this tab *declares*
    // that Ctrl+Plus means its text, rather than relying on that.
    public void zoom_in () {
      code_editor.zoom_in ();
    }

    public void zoom_out () {
      code_editor.zoom_out ();
    }

    public void reset_zoom () {
      code_editor.reset_zoom ();
    }

    /** Ctrl+H while this tab is the active one — same effect as clicking replace_button itself, including its own no-op guard (see on_replace_button_toggled()) when there's nothing currently shown. */
    public void open_replace () {
      replace_button.active = true;
    }

    /**
     * Shows/hides the Find/Replace row and fills find_text/find_icons in
     * from last_result.query — the actual replace happens separately, in
     * confirm_and_replace_all(). replace_button's own :checked state (a
     * ToggleButton) is what reads as "pressed" while the row is open;
     * this just keeps the row itself in sync with it. A no-op — button
     * pressed back up immediately — with nothing currently shown (no
     * query to reference).
     */
    private void on_replace_button_toggled () {
      if (!replace_button.active) {
        replace_revealer.reveal_child = false;
        return;
      }

      if (last_result == null) {
        replace_button.active = false;
        return;
      }

      find_text.text = last_result.query.text;
      populate_find_icons (last_result.query);
      replace_revealer.reveal_child = true;
    }

    /**
     * One icon per toggle `query` actually used, in the same order
     * FindInFilesBar's own regex/case-sensitive/whole-word buttons are
     * laid out — same icon names as those, so a user who already knows
     * that row's own icons recognizes these instead of learning a second
     * set. A toggle that wasn't on contributes no icon at all, rather
     * than a dimmed/inactive one: this row has no interactive toggles of
     * its own, only a record of what the search already used.
     */
    private void populate_find_icons (FindInFilesQuery query) {
      Gtk.Widget? child = find_icons.get_first_child ();
      while (child != null) {
        var next = child.get_next_sibling ();
        find_icons.remove (child);
        child = next;
      }

      if (query.regex_enabled) {
        find_icons.append (find_icon ("regex-symbolic", _("Regular Expression")));
      }
      if (query.case_sensitive_enabled) {
        find_icons.append (find_icon ("case-sensitive-symbolic", _("Case Sensitive")));
      }
      if (query.whole_word_enabled) {
        find_icons.append (find_icon ("whole-word-symbolic", _("Match Whole Word Only")));
      }
    }

    private Gtk.Image find_icon (string icon_name, string tooltip_text) {
      return new Gtk.Image.from_icon_name (icon_name) { tooltip_text = tooltip_text };
    }

    /**
     * The actual Replace All flow — confirms, then runs it. Dialogs.confirm(),
     * not confirm_destructive(): this overwrites files on disk, but not in a
     * way meaningfully riskier than Save itself, so it doesn't need the red
     * "destructive" treatment — and suggesting one specific response over the
     * other isn't warranted either. A no-op with nothing currently shown (no
     * result to replace into).
     */
    private async void confirm_and_replace_all () {
      if (last_result == null) {
        return;
      }

      var confirmed = yield Dialogs.confirm (
        widget,
        _("Replace All"),
        replace_all_body_text (last_result, replace_text.text),
        _("Replace")
      );
      if (!confirmed) {
        return;
      }

      try {
        var outcome = FindInFilesReplace.run (last_result, replace_text.text);
        apply_replace_outcome (outcome);
      } catch (Error e) {
        show_replace_error (e.message);
      }
    }

    private void show_replace_error (string message) {
      Dialogs.show_error (widget, message);
    }

    /**
     * Reconciles `last_result` in place with what FindInFilesReplace.
     * run() actually wrote, then re-renders showing the outcome — no
     * round-trip through the pane needed: everything this touches
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
      // Moved off replace_text *before* disabling/hiding it below — GTK4
      // warns ("GtkText - did not receive a focus-out event") when a
      // focused Gtk.Text is disabled or unmapped without focus leaving it
      // first, same as the Escape handler above already does.
      code_editor.grab_focus ();
      // Clicking Replace All again right now would silently do nothing —
      // result.query's own regex was already matched against and
      // replaced, so it no longer matches what's here (repeating a
      // replace against the *new* tracked text is a real feature, just
      // not this one yet). Disabled, not hidden: replace_button itself
      // stays available so the row (with its still-relevant find_text)
      // can be reopened to look at; only actually replacing again is
      // blocked, until the next real search re-enables it above.
      // replace_button.active = false closes the row itself for now
      // (on_replace_button_toggled reacts to it).
      replace_text.sensitive = false;
      replace_confirm_button.sensitive = false;
      // Also disabled, same reasoning: adjusting context lines here would
      // need to either re-run the original search (which no longer
      // matches anything Replace All just removed) or rebuild blocks off
      // matches this class doesn't keep around — not worth the edge
      // cases either way, so the control itself is just frozen until the
      // next real search re-enables it above.
      context_lines_entry.sensitive = false;
      context_lines_toggle.sensitive = false;
      replace_button.active = false;
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

    /** "Replace N occurrence(s) across M file(s) with "<replacement>"?" — same pluralization style as summary_label_for()'s own "N results in M files". */
    private string replace_all_body_text (FindInFilesResult result, string replacement) {
      return _("Replace %d %s across %d %s with “%s”?").printf (
        result.total_match_count, result.total_match_count == 1 ? _("occurrence") : _("occurrences"),
        result.file_count, result.file_count == 1 ? _("file") : _("files"),
        replacement
      );
    }

    private void apply_style_scheme (bool dark) {
      if (replace_row_provider != null) {
        GlobalCss.uninstall (replace_row_provider);
      }
      replace_row_provider = GlobalCss.install_from_string (
        ".find-results-replace-row { background-color: %s; }".printf (replace_row_background (dark))
      );

      filename_tag.weight = Pango.Weight.BOLD;

      // Dims toward the pane's own real (theme-resolved) text color,
      // rather than a hardcoded gray, so it reads correctly in both
      // light and dark without its own light/dark branch.
      var line_number_color = code_editor.widget.get_color ();
      line_number_color.alpha = dark ? 0.5f : 0.35f;
      line_number_tag.foreground_rgba = line_number_color;

      // Same technique CodeEditorSearch's own apply_theme_colors() uses
      // for its match highlight, for visual consistency with in-file Find.
      var match_background = SystemColor.from_accent ().desaturate (dark ? 0.10f : 0.05f).to_rgba ();
      match_background.alpha = 0.30f;
      match_highlight_tag.background_rgba = match_background;

      // Re-render with the new colors if there's anything currently shown.
      if (last_result != null || last_error_message != null) {
        render ();
      }
    }

    /**
     * The editor's *real* background, straight off the GtkSource.
     * StyleScheme CodeEditor applies for `dark` (get_style("text").
     * background) — same technique its own _source-view.vala uses for
     * the same reason (see its inverted_glyph_color()'s doc comment): a
     * plain CSS background-color on a GtkSourceView is transparent by
     * design in Adwaita, so the scheme's own style is the only real
     * source for this color. Looked up by the same id CodeEditor uses
     * rather than read off its buffer, so this doesn't depend on whose
     * `notify["dark"]` handler ran first. Falls back to Adwaita's own
     * plain light/dark window background only if the scheme has none
     * set — not expected for Adwaita/Adwaita-dark (both real schemes
     * do), just defensive.
     */
    private string replace_row_background (bool dark) {
      var scheme = GtkSource.StyleSchemeManager.get_default ().get_scheme (dark ? "Adwaita-dark" : "Adwaita");
      var style = scheme?.get_style ("text");
      if (style != null && style.background_set) {
        return style.background;
      }
      return dark ? "#1e1e1e" : "#ffffff";
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
      foreach (var tag in nav_tags) {
        results_buffer.tag_table.remove (tag);
      }
      nav_tags = new GenericArray<Gtk.TextTag> ();

      if (last_error_message != null) {
        header_label.label = last_error_query.text;
        code_editor.set_text (last_error_message, "");
        return;
      }
      if (last_result == null) {
        header_label.label = "";
        code_editor.set_text ("", "");
        return;
      }

      var result = last_result;
      header_label.label = summary_label_for (result);

      var text = new StringBuilder ();
      var structural_ranges = new GenericArray<TagRange> ();
      var match_ranges = new GenericArray<TagRange> ();
      var nav_ranges = new GenericArray<TagRange> ();
      var pending_highlights = new GenericArray<PendingHighlight> ();
      int offset = 0;

      if (replace_summary_skipped_paths != null) {
        offset = append_replace_summary (text, structural_ranges, nav_ranges, offset, replace_summary_skipped_paths);
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
        // The whole header line, ":" and newline included — a click past
        // the path's end still means this file.
        nav_ranges.add (new TagRange () { start = filename_start, end = offset, tag = make_nav_tag (file.path, first_match_line (file), first_match_column (file)) });

        int max_line_number = 0;
        foreach (var each_block in file.blocks) {
          max_line_number = int.max (max_line_number, each_block.start_line + each_block.lines.length - 1);
        }
        int line_number_width = int.max (MIN_LINE_NUMBER_WIDTH, max_line_number.to_string ().length);

        for (uint block_index = 0; block_index < file.blocks.length; block_index++) {
          var block = file.blocks[block_index];
          var line_start_offsets = new int[block.lines.length];
          for (int i = 0; i < block.lines.length; i++) {
            var line_number = block.start_line + i;
            var digits = line_number.to_string ();
            var prefix = "  %s%s: ".printf (string.nfill (line_number_width - digits.length, ' '), digits);
            int prefix_start = offset;
            text.append (prefix);
            offset += prefix.char_count ();
            structural_ranges.add (new TagRange () { start = prefix_start, end = offset, tag = line_number_tag });

            line_start_offsets[i] = offset;
            text.append (block.lines[i]);
            int code_length = block.lines[i].char_count ();
            offset += code_length;
            text.append ("\n");
            offset += 1;
            // Prefix, code and newline — see NavTarget.code_start.
            var nav_tag = make_nav_tag (file.path, line_number, 0, true, prefix.char_count (), code_length);
            nav_ranges.add (new TagRange () { start = prefix_start, end = offset, tag = nav_tag });
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

      code_editor.set_text (text.str, "");

      foreach (var range in structural_ranges) {
        apply_range (range);
      }
      foreach (var request in pending_highlights) {
        language_highlighter.highlight (request.path, request.snippet, request.line_start_offsets);
      }
      foreach (var range in match_ranges) {
        apply_range (range);
      }
      foreach (var range in nav_ranges) {
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
    private int append_replace_summary (StringBuilder text, GenericArray<TagRange> structural_ranges, GenericArray<TagRange> nav_ranges, int offset, GenericArray<string> skipped_paths) {
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
        int line_start = offset;
        text.append ("  - ");
        text.append (path);
        text.append ("\n");
        offset += 4 + path.char_count () + 1;
        // -1: its own last-known match position isn't trustworthy — that's
        // exactly why this file was skipped (see NavTarget's own doc
        // comment). The whole line, same as a result line.
        nav_ranges.add (new TagRange () { start = line_start, end = offset, tag = make_nav_tag (path, -1, 0) });
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

    /** "N results in M files" — shown in the header, above the results body. */
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

    /** A fresh, unstyled tag carrying `target` — tracked in nav_tags so the next render() can drop it again (see that field's own doc comment). */
    private Gtk.TextTag make_nav_tag (string path, int line, int column, bool column_from_click = false, int code_start = 0, int code_length = 0) {
      var tag = new Gtk.TextTag (null);
      tag.set_data<NavTarget> ("opus-nav-target", new NavTarget () {
        path = path, line = line, column = column, column_from_click = column_from_click,
        code_start = code_start, code_length = code_length,
      });
      results_buffer.tag_table.add (tag);
      nav_tags.add (tag);
      return tag;
    }

    /** -1 if `file` somehow has no match at all — render() always builds a block around at least one, but nothing stops a future caller from handing over an empty one. */
    private int first_match_line (FindInFilesFileResult file) {
      foreach (var block in file.blocks) {
        if (block.matches.length > 0) {
          return block.matches[0].line_number;
        }
      }
      return -1;
    }

    private int first_match_column (FindInFilesFileResult file) {
      foreach (var block in file.blocks) {
        if (block.matches.length > 0) {
          return block.matches[0].start_column;
        }
      }
      return 0;
    }

    /** The nav tag covering `offset`, if any — CodeEditor's own link_click hands back a raw offset with no opinion on what's there; this is where that gets resolved. The first nav tag found is the only one: render() lays spans out as whole lines that never overlap, so no offset ever carries two. */
    private Gtk.TextTag? nav_tag_at (int offset) {
      if (offset < 0) {
        return null;
      }
      Gtk.TextIter iter;
      results_buffer.get_iter_at_offset (out iter, offset);
      foreach (var tag in iter.get_tags ()) {
        if (tag.get_data<NavTarget?> ("opus-nav-target") != null) {
          return tag;
        }
      }
      return null;
    }

    /** `tag`'s own extent around `offset` — found via its toggle points, not guessed, so it's exact even with adjacent same-length spans. */
    private void tag_span (Gtk.TextTag tag, int offset, out int span_start, out int span_end) {
      Gtk.TextIter start;
      Gtk.TextIter end;
      results_buffer.get_iter_at_offset (out start, offset);
      results_buffer.get_iter_at_offset (out end, offset);
      if (!start.starts_tag (tag)) {
        start.backward_to_tag_toggle (tag);
      }
      if (!end.ends_tag (tag)) {
        end.forward_to_tag_toggle (tag);
      }
      span_start = start.get_offset ();
      span_end = end.get_offset ();
    }

    private void on_link_click (int offset) {
      var tag = nav_tag_at (offset);
      if (tag == null) {
        return;
      }
      var target = tag.get_data<NavTarget?> ("opus-nav-target");

      int column = target.column;
      if (target.column_from_click) {
        int span_start;
        int span_end;
        tag_span (tag, offset, out span_start, out span_end);
        // Anywhere on the prefix is column 0; anywhere past the code's
        // end (the newline, or empty space after a short line) is its
        // end — see NavTarget.code_start.
        column = (offset - span_start - target.code_start).clamp (0, target.code_length);
      }
      navigate_requested (target.path, target.line, column);
    }

  }
}
