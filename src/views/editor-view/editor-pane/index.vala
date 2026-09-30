/**
 * Composes TabBar + TextEditor directly — the SFC-style replacement for
 * the real EditorController, which used to sit between them as a
 * separate Controller object holding both from outside. No Controller
 * left: this class owns the open Document list itself and wires TabBar's
 * signals straight to TextEditor's methods (and vice versa) in its own
 * method bodies. TabBar's own "Reveal in Sidebar" is the one signal this
 * re-emits rather than handling itself — its target (ExplorerPane) is a
 * sibling this class has no reference to; MainWindow, which composes both,
 * is what actually wires it through.
 *
 * Assembles its own widget — a vertical Box, TabBar's own widget on top,
 * a divider, TextEditor's own widget below (vexpand) — rather than
 * exposing the two separately for MainWindow to place into different
 * regions of its own window template: they were never actually placed
 * in different regions (both already sat in the same vertical Box in
 * MainWindow's own Blueprint), so MainWindow reaching in for each one
 * independently was only ever indirection, not a real layout need.
 *
 * External file-watching (start_watching/stop_watching's own
 * Gio.FileMonitor lifecycle) is split into its own EditorPaneFileWatcher
 * — see its own doc comment for why.
 *
 * Opus.Dev.DevServer's own methods (open_paths, active_content,
 * set_active_content, set_active_cursors, get_active_cursors) are ported
 * above with the same plain names the real EditorController used — no
 * "simulate"/"test" framing, they're genuinely what they say. select_all
 * lives directly on TextEditor instead (see its own doc comment), reached
 * through the public `text_editor` property below rather than wrapped in
 * a forwarding method here.
 */
namespace EditorView {
  public class EditorPane : Object {
    // No `.editorconfig`, or none of its sections match a given file —
    // VS Code's own default `tabSize`, and a reasonable one on its own.
    private const int DEFAULT_INDENT_SIZE = 4;
    // Matches current native behavior — Tab only switches to inserting
    // spaces once a file's own .editorconfig explicitly says so.
    private const bool DEFAULT_INSERT_SPACES = false;

    // The one widget actually exposed via `widget` below — its own
    // `.child` toggles between `content` (tab bar + editor) and
    // `empty_state`, kept in sync with has_open_tabs_changed right in
    // the constructor, so whoever hosts `widget` never needs to touch
    // it again after placing it once.
    private Adw.Bin container;
    private Gtk.Box content;
    private Adw.StatusPage empty_state;
    // TextEditor is one shared widget reused across every real file tab
    // — this Bin is what lets the Find Results tab swap in a completely
    // different widget (EditorPane_.FindResults) instead, without
    // TextEditor itself needing any notion of a "results" mode.
    private Adw.Bin editor_area_bin;
    private EditorPane_.TabBar tab_bar;
    private EditorPaneFileWatcher file_watcher;
    private string root_path;
    private EditorConfig? editor_config;

    private HashTable<string, Document> documents = new HashTable<string, Document> (str_hash, str_equal);
    private string? active_path = null;
    private int untitled_counter = 0;

    // Owned by MainWindow (outlives a single linked folder — see
    // GIT_STATUS_PLUGIN_PLAN.md's own "Host wiring" section), handed here
    // via set_decorations() so every open tab, not just the active one,
    // can be tinted — null with no folder linked, same nullable pattern
    // ExplorerPane's own ExplorerPane? field on MainWindow already uses.
    private FileDecoration.Registry? decorations = null;

    // Same "owned by MainWindow, handed in via a setter" shape as
    // `decorations` above, but unlike it, only the active document's
    // hunks are ever rendered (one shared TextEditorSourceView buffer,
    // not one per tab) — so `diff_tracker` is a single instance, reset on
    // every tab switch, not a per-document map.
    private GitDiff.DocumentTracker diff_tracker = new GitDiff.DocumentTracker ();
    private GitDiff.IBaseProvider? diff_base_provider = null;

    // Find in Files' own synthetic tab — reuses the plain string-keyed
    // documents/tab_bar machinery exactly like new_untitled()'s
    // "Untitled-N" already does, rather than inventing a second tab
    // concept. find_results is created lazily (first search only).
    private const string FIND_RESULTS_TAB_URI = "opus://find-in-files-results";
    // Only the very first search ever run (find_results doesn't exist
    // yet to read its own context_lines off) — every search after that
    // reads the live value straight from FindResults' own control.
    private const int DEFAULT_FIND_IN_FILES_CONTEXT_LINES = 1;
    private EditorPane_.FindResults? find_results = null;
    // The most recently run Find in Files query — re-issued as-is when
    // FindResults' own context_lines_changed fires, so adjusting that
    // control re-searches without the user retyping anything.
    private FindInFilesQuery? last_find_in_files_query = null;
    // Bumped on every new search_in_files() call (and once more on
    // close()) so a search still running when a newer one starts, or
    // the window closes, never renders its own stale result afterward.
    private int search_generation = 0;

    public Gtk.Widget widget { get { return container; } }

    /** The real TextEditor itself, not just its widget — Opus.Dev.DevServer's own way to reach test-only entry points (e.g. select_all()) directly, without EditorPane wrapping each one in a forwarding method of its own. */
    public EditorPane_.TextEditor text_editor { get; private set; }

    /** Whether at least one tab is open — `widget` itself already reacts to this (see the constructor); still re-emitted for whoever hosts it to gate its own tab-dependent behavior (MainWindow's own Ctrl+F/Ctrl+H). */
    public signal void has_open_tabs_changed (bool has_tabs);

    /** The active tab, or its dirty state, changed — null `path` means no tab is active (`dirty` is meaningless then). */
    public signal void active_state_changed (string? path, bool dirty);

    /** A tab for `path` just started existing (opened permanent or preview) — unlike active_state_changed, this fires once per tab regardless of focus, for whoever needs to know a specific path is open at all rather than merely active (MainWindow's own settings.json live-reload watch). */
    public signal void tab_opened (string path);

    /** A tab for `path` just stopped existing (closed, discarded, or evicted as an old preview) — see tab_opened()'s own doc comment. */
    public signal void tab_closed (string path);

    /** Re-emitted from TextEditor's own search sub-component — see FindBar's own "N of M" counter, wired to this wherever both are composed (MainWindow). */
    public signal void search_position_changed (int position, int count);

    /** Re-emitted from TabBar's own "Reveal in Sidebar" — whoever composes this alongside ExplorerPane (MainWindow) is the one with a reference to both. */
    public signal void reveal_in_sidebar_requested (string path);

    public EditorPane (string root_path) {
      this.root_path = root_path;
      editor_config = EditorConfig.load (root_path);

      tab_bar = new EditorPane_.TabBar ();
      text_editor = new EditorPane_.TextEditor ();
      file_watcher = new EditorPaneFileWatcher ();

      content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
      content.append (tab_bar.widget);
      content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { css_classes = { "content-divider" } });
      editor_area_bin = new Adw.Bin () { child = text_editor.widget, vexpand = true };
      content.append (editor_area_bin);

      // Generic on purpose, not "…from the sidebar": a blank/file-only
      // window (no folder linked) has no sidebar to speak of at all.
      empty_state = new Adw.StatusPage () {
        title = _("No File Open"),
        description = _("Open a file or folder to start editing."),
        icon_name = "document-open-symbolic",
      };

      // No tab open yet at construction, so there's nothing to show
      // besides the empty state — stays this way until has_open_tabs_changed
      // says otherwise.
      container = new Adw.Bin () { child = empty_state };
      has_open_tabs_changed.connect ((has_tabs) => {
        container.child = has_tabs ? (Gtk.Widget) content : (Gtk.Widget) empty_state;
      });

      text_editor.text_changed.connect (on_text_changed);
      tab_bar.tab_selected.connect (on_tab_selected);
      tab_bar.tab_double_clicked.connect (on_tab_double_clicked);
      tab_bar.tab_close_requested.connect ((path) => close_tab.begin (path));
      tab_bar.preview_demoted.connect (on_preview_demoted);
      tab_bar.close_others_requested.connect (close_others);
      tab_bar.close_all_requested.connect (close_all);
      // Copy Path / Reveal in Sidebar only ever mean something for a
      // real file — tab_bar's own key is a uri, so each is resolved back
      // to the document's real pathname (falling back to the uri itself,
      // which should never actually happen for these two menu items —
      // TabBar only offers them at all for tabs backed by a real file).
      tab_bar.copy_path_requested.connect ((uri) => tab_bar.copy_to_clipboard (documents[uri]?.pathname ?? uri));
      tab_bar.copy_relative_path_requested.connect ((uri) => tab_bar.copy_to_clipboard (relative_path (documents[uri]?.pathname ?? uri)));
      tab_bar.new_file_requested.connect (new_untitled);
      tab_bar.reveal_in_sidebar_requested.connect ((uri) => reveal_in_sidebar_requested (documents[uri]?.pathname ?? uri));
      text_editor.reload_requested.connect (on_reload_requested);
      text_editor.search_position_changed.connect ((position, count) => search_position_changed (position, count));
      file_watcher.file_changed.connect (on_file_changed);
      diff_tracker.hunks_changed.connect (() => text_editor.set_hunks (diff_tracker.hunks ()));
    }

    /** "Open Folder…" swaps the sidebar to a new root, in the same window — open tabs stay open, only future "Copy Relative Path" calls resolve against the new root. */
    public void set_root_path (string root_path) {
      this.root_path = root_path;
      editor_config = EditorConfig.load (root_path);
    }

    /** MainWindow calls this in lockstep with linking/unlinking a folder — null on "Close Folder" (or a window that never had one), clearing every open tab's own tint the same way it applied one. */
    public void set_decorations (FileDecoration.Registry? new_decorations) {
      if (decorations != null) {
        decorations.changed.disconnect (refresh_tab_decorations);
      }
      decorations = new_decorations;
      if (decorations != null) {
        decorations.changed.connect (refresh_tab_decorations);
      }
      refresh_tab_decorations ();
    }

    /** MainWindow calls this in lockstep with linking/unlinking a folder — null on "Close Folder" (or a window that never had one), or if the plugin providing it goes away. Unlike set_decorations(), only the active tab's hunks need recomputing — there's no per-tab map to refresh. */
    public void set_diff_base_provider (GitDiff.IBaseProvider? new_provider) {
      diff_base_provider = new_provider;
      if (active_path != null) {
        var document = documents[active_path];
        diff_tracker.set_document.begin (document.pathname, document.content, diff_base_provider);
      }
    }

    /** Re-stamps every open tab (not just the active one — a background tab whose file changes elsewhere still needs its own tint to update) from the current `decorations` snapshot. */
    private void refresh_tab_decorations () {
      foreach (var document in documents.get_values ()) {
        stamp_tab_decoration (document);
      }
    }

    /** A synthetic tab (Untitled-N, Find Results — no real `pathname`) never has anything to decorate. `decorations == null` (no folder linked) explicitly clears rather than skipping, so a tab tinted before "Close Folder" doesn't keep showing a stale tint afterward. */
    private void stamp_tab_decoration (Document document) {
      if (document.pathname == null) {
        return;
      }
      tab_bar.mark_decoration (document.uri, decorations == null ? null : decorations.decoration_for (document.pathname, false));
    }

    /**
     * Opens `path`, as a preview tab or a permanent one, reusing an
     * existing tab if already open. A permanent open also moves
     * keyboard focus into the editor.
     */
    public void open (string path, bool as_permanent) throws Error {
      var existing = find_by_title (path);
      if (existing != null) {
        if (as_permanent) {
          promote (existing);
        }
        activate (existing.uri);
      } else if (as_permanent) {
        open_permanent (path);
      } else {
        open_preview (path);
      }

      if (as_permanent) {
        text_editor.grab_focus ();
      }
    }

    /** Opens a brand-new, not-yet-saved-anywhere tab named "Untitled-N" — a permanent tab, focused immediately. Saving it goes through the Save As flow regardless of "Save" or "Save as…", since there's nowhere on disk yet for a plain Save to write to. */
    public void new_untitled () {
      untitled_counter++;
      var name = "Untitled-%d".printf (untitled_counter);

      var document = Document.untitled (untitled_counter.to_string (), name);
      documents[document.uri] = document;
      tab_bar.add_tab (document.uri, document.name, "", false, document.title);
      if (documents.size () == 1) {
        has_open_tabs_changed (true);
      }
      activate (document.uri);
      text_editor.grab_focus ();
    }

    /**
     * Find in Files — searches the whole linked workspace folder for
     * `query.text` and shows the results in the "Find Results" tab
     * (opened, or refreshed in place if already open). A no-op with an
     * empty query. `search_generation` is bumped before awaiting the
     * actual search so a second call started before the first
     * finishes supersedes it outright — whichever finishes last simply
     * discards its own result instead of clobbering a newer one, and
     * close() bumps it once more so a search still running when the
     * window closes never touches a torn-down pane either.
     */
    public async void search_in_files (FindInFilesQuery query) {
      if (query.text == "") {
        return;
      }
      last_find_in_files_query = query;
      int generation = ++search_generation;

      // find_results doesn't exist yet on the very first search ever
      // run — every search after that reads its own live control instead
      // of this default.
      int context_lines = find_results != null ? find_results.context_lines : DEFAULT_FIND_IN_FILES_CONTEXT_LINES;

      FindInFilesResult? result = null;
      Error? error = null;
      try {
        result = yield FindInFilesSearch.run_async (root_path, query, context_lines);
      } catch (Error e) {
        error = e;
      }
      if (generation != search_generation) {
        return;
      }

      if (find_results == null) {
        find_results = new EditorPane_.FindResults ();
        // Re-issues last_find_in_files_query as-is — adjusting context
        // lines re-searches without the user retyping anything. Replace
        // All has no equivalent hookup here: FindResults reconciles its
        // own last-shown result and re-renders itself once
        // FindInFilesReplace.run() lands — re-running the original
        // search afterward would search for the *old* term, no longer
        // there to find.
        find_results.context_lines_changed.connect (() => search_in_files.begin (last_find_in_files_query));
      }
      if (error != null) {
        find_results.show_error (query, error.message);
      } else {
        find_results.show_results (result);
      }
      open_or_focus_find_results_tab ();
    }

    private void open_or_focus_find_results_tab () {
      if (!documents.contains (FIND_RESULTS_TAB_URI)) {
        var document = Document.internal_tab ("find-in-files-results", _("Find Results"));
        documents[FIND_RESULTS_TAB_URI] = document;
        tab_bar.add_tab (FIND_RESULTS_TAB_URI, document.name, "", false, document.title);
        tab_opened (FIND_RESULTS_TAB_URI);
        if (documents.size () == 1) {
          has_open_tabs_changed (true);
        }
      }
      activate (FIND_RESULTS_TAB_URI);
    }

    /** Saves the active document, if any and if dirty — see save_uri(). */
    public async void save_active () {
      if (active_path != null) {
        yield save_uri (active_path);
      }
    }

    /** "Save As" on the active document, if any — see save_as_path(). */
    public async void save_as_active () {
      if (active_path != null) {
        yield save_as_path (active_path);
      }
    }

    /** Closes the active tab, if any — same unsaved-changes flow as its own close button. */
    public void close_active () {
      if (active_path != null) {
        close_tab.begin (active_path);
      }
    }

    /** Whether `path` is currently open as a tab with unsaved changes. */
    public bool is_dirty (string path) {
      var document = find_by_title (path);
      return document != null && document.dirty;
    }

    /** The active tab's own clean, user-facing name — its real path for a file, a plain display name otherwise — or null if none. Opus.Dev.DevServer's own GetActiveTab. */
    public string? active_document_path {
      owned get { return active_path == null ? null : documents[active_path].title; }
    }

    /** The currently linked folder — MainWindow's own "Add Folder…" (FindInFilesBar's where_entry) reads this to validate a chosen folder is actually inside it before appending anything. */
    public string linked_folder_path {
      get { return root_path; }
    }

    /** The query behind the "Find Results" tab, but only while that's actually the active tab — null otherwise, even if a "Find Results" tab still exists somewhere in the background. MainWindow's own Ctrl+Shift+F reads this to decide whether reopening FindInFilesBar should restore the last search or start blank. */
    public FindInFilesQuery? current_find_in_files_query {
      get { return active_path != null && is_find_results_tab (active_path) ? last_find_in_files_query : null; }
    }

    /**
     * MainWindow's own Ctrl+H reads this first to decide whether to open
     * this tab's own inline Find/Replace row (open_internal_replace())
     * instead of the regular FindBar (see editor-pane-tab-dispatch.md,
     * root — this is exactly the kind of per-internal-tab special case
     * that file's proposed registry would take over once a second
     * internal tab kind exists; one `if` here isn't worth pulling that
     * forward yet).
     */
    public bool is_find_results_active () {
      return active_path != null && is_find_results_tab (active_path);
    }

    /** Opens the Find Results tab's own inline Find/Replace row — a no-op if that tab isn't actually open/active, same as every other action method here (save_active(), close_active(), ...) trusting its own guard over the caller's. */
    public void open_internal_replace () {
      if (!is_find_results_active () || find_results == null) {
        return;
      }

      find_results.open_replace_row ();
    }

    /** Every currently open tab's own clean, user-facing name — Opus.Dev.DevServer's own ListOpenTabs, no UI caller today. */
    public string[] open_paths () {
      string[] paths = {};
      foreach (var document in documents.get_values ()) {
        paths += document.title;
      }
      return paths;
    }

    /** The active document's current buffer content, or "" if none — Opus.Dev.DevServer's own GetActiveText, the reverse of set_active_content(). */
    public string active_content {
      owned get { return active_path == null ? "" : documents[active_path].content; }
    }

    /**
     * Replaces the active document's content wholesale, as if the user
     * had retyped the whole buffer — Opus.Dev.DevServer's own
     * SetActiveText, no UI caller today (a person editing for real goes
     * through on_text_changed() instead). Unlike that path, this also
     * has to push the new text into the real buffer itself: the UI path
     * runs the other way around (buffer changes first, content follows),
     * so nothing else does that half of the job here.
     */
    public void set_active_content (string text) {
      if (active_path == null) {
        return;
      }

      var document = documents[active_path];
      document.content = text;
      if (document.is_preview) {
        promote (document);
      }
      text_editor.set_text (text, document.pathname ?? active_path);
      tab_bar.mark_modified (document.uri, document.dirty);
      notify_active_state ();
    }

    /**
     * Replaces the active document's cursor set and renders it — Opus.Dev.DevServer's
     * own SetActiveCursors, still handy for the system-test DSL to seed a
     * multi-cursor starting state without typing/clicking it into place
     * first. `anchors[i]`/`positions[i]` pair up into one cursor each; a
     * collapsed cursor has `anchors[i] == positions[i]`. A no-op if the
     * two arrays don't have the same length, or if there's no active tab.
     */
    public void set_active_cursors (int[] anchors, int[] positions) {
      if (active_path == null || anchors.length != positions.length) {
        return;
      }

      var document = documents[active_path];
      var cursor_set = new Cursor[anchors.length];
      for (int i = 0; i < anchors.length; i++) {
        var cursor = new Cursor (anchors[i]);
        cursor.position_offset = positions[i];
        cursor_set[i] = cursor;
      }

      document.cursors.set_cursors (cursor_set);
      text_editor.render_cursors (document.cursors.snapshot ());
    }

    /**
     * The active document's current cursor set — Opus.Dev.DevServer's own
     * GetActiveCursors, the reverse of set_active_cursors(). Each `out`
     * array is empty when there's no active tab.
     */
    public void get_active_cursors (out int[] anchors, out int[] positions) {
      if (active_path == null) {
        anchors = {};
        positions = {};
        return;
      }

      var cursor_set = documents[active_path].cursors.snapshot ();
      anchors = new int[cursor_set.length];
      positions = new int[cursor_set.length];
      for (int i = 0; i < cursor_set.length; i++) {
        anchors[i] = cursor_set[i].anchor_offset;
        positions[i] = cursor_set[i].position_offset;
      }
    }

    /** Applies a Replace/Replace All result, computed by text_editor.compute_replace_current_match()/compute_replace_all(). Not cursor-driven, so it goes through TextEditor's own external-edit path. A no-op with no active tab, or an empty `edits`. */
    public void apply_external_edits (TextEdit[] edits) {
      if (active_path == null || edits.length == 0) {
        return;
      }
      text_editor.apply_external_edits (edits);
    }

    // The rest of this section is pure forwarding onto text_editor's own
    // search API — MainWindow (FindBar's owner) talks to EditorPane as
    // the one facade for "the editor," never reaching into TextEditor
    // directly, the same reason apply_external_edits() above exists
    // rather than exposing text_editor itself.

    /** Whether the editor currently holds keyboard focus — MainWindow's own "was the user actually in the editor when they pressed Ctrl+F" check. */
    public bool has_focus {
      get { return text_editor.has_focus; }
    }

    /** The editor's own current primary selection text, "" if empty/collapsed — MainWindow's own Ctrl+F prefill. */
    public string primary_selection_text {
      owned get { return text_editor.primary_selection_text; }
    }

    public void grab_focus () {
      text_editor.grab_focus ();
    }

    public void set_search_text (string text) {
      text_editor.set_search_text (text);
    }

    public void set_search_options (bool regex, bool case_sensitive, bool whole_word) {
      text_editor.set_search_options (regex, case_sensitive, whole_word);
    }

    public void search_next () {
      text_editor.search_next ();
    }

    public void search_previous () {
      text_editor.search_previous ();
    }

    public TextEdit? compute_replace_current_match (string replacement) {
      return text_editor.compute_replace_current_match (replacement);
    }

    public TextEdit[] compute_replace_all (string replacement) {
      return text_editor.compute_replace_all (replacement);
    }

    public void land_after_replace (int replaced_end_offset) {
      text_editor.land_after_replace (replaced_end_offset);
    }

    public void forget_current_match () {
      text_editor.forget_current_match ();
    }

    public void select_last_match () {
      text_editor.select_last_match ();
    }

    /** See TextEditorCursors.select_all_occurrences()'s own doc comment. */
    public void select_all_occurrences () {
      text_editor.select_all_occurrences ();
    }

    /**
     * Closes `path`'s tab outright, no unsaved-changes prompt — for when
     * the file itself is already gone (deleted from the sidebar) and
     * there's nothing left to save it to. No-op if `path` isn't open.
     */
    public void discard_tab (string path) {
      var document = find_by_title (path);
      if (document != null) {
        finish_close (document.uri);
      }
    }

    /**
     * `old_path` moved to `new_path` on disk (a sidebar Rename, or a
     * Cut+Paste actually moving rather than copying). Only ever matches a
     * path that was directly opened as its own tab — same structural
     * guarantee as discard_tab() above, since both arguments are always
     * real OS paths.
     */
    public void file_moved (string old_path, string new_path) {
      var old_uri = Document.uri_for_path (old_path);
      var document = documents[old_uri];
      if (document == null) {
        return;
      }

      file_watcher.stop_watching (old_path);
      document.move_to (new_path);
      var new_uri = document.uri;
      documents.remove (old_uri);
      documents[new_uri] = document;
      file_watcher.start_watching (new_path);

      tab_bar.rename_tab (old_uri, new_uri, document.name, folder_name_of (new_path), document.title);
      stamp_tab_decoration (document);

      if (active_path == old_uri) {
        active_path = new_uri;
      }
      notify_active_state ();
    }

    /** Cascades to the file-watcher sub-component's own close(). */
    public void close () {
      file_watcher.close ();
      // Discards any Find in Files search still in flight — see
      // search_in_files()'s own doc comment for what search_generation
      // guards against.
      search_generation++;
    }

    private void open_preview (string path) throws Error {
      var existing_preview = find_preview ();
      if (existing_preview != null) {
        tab_bar.remove_tab (existing_preview.uri);
        documents.remove (existing_preview.uri);
        file_watcher.stop_watching (existing_preview.pathname);
        tab_closed (existing_preview.uri);
      }

      var document = Document.load (path);
      document.is_preview = true;
      documents[document.uri] = document;
      tab_bar.add_tab (document.uri, document.name, folder_name_of (path), true, document.title);
      stamp_tab_decoration (document);
      file_watcher.start_watching (path);
      tab_opened (document.uri);
      if (documents.size () == 1) {
        has_open_tabs_changed (true);
      }
      activate (document.uri);
    }

    private void open_permanent (string path) throws Error {
      var document = Document.load (path);
      document.is_preview = false;
      documents[document.uri] = document;
      tab_bar.add_tab (document.uri, document.name, folder_name_of (path), false, document.title);
      stamp_tab_decoration (document);
      file_watcher.start_watching (path);
      tab_opened (document.uri);
      if (documents.size () == 1) {
        has_open_tabs_changed (true);
      }
      activate (document.uri);
    }

    /**
     * `path` itself was deleted, or came back, or changed content —
     * same interpretation the real EditorController's own
     * on_file_changed() did, just reading the raw event from
     * file_watcher.file_changed instead of a Gio.FileMonitor directly.
     * The RENAMED-onto-`path` ambiguity (a plain resave looks
     * identical at the GIO level to a delete-then-recreate) is
     * resolved the same way: by whether this document was already
     * known deleted.
     */
    private void on_file_changed (string path, FileMonitorEvent event_type, string? other_file_path) {
      var document = documents[Document.uri_for_path (path)];
      if (document == null) {
        return;
      }

      switch (event_type) {
        case FileMonitorEvent.DELETED:
        case FileMonitorEvent.MOVED_OUT:
          mark_file_deleted (document, true);
          break;
        case FileMonitorEvent.CREATED:
          mark_file_deleted (document, false);
          break;
        case FileMonitorEvent.RENAMED:
          if (other_file_path == null || other_file_path != path) {
            break;
          }
          if (document.is_deleted) {
            mark_file_deleted (document, false);
          } else {
            mark_externally_modified (document);
          }
          break;
        case FileMonitorEvent.CHANGED:
          mark_externally_modified (document);
          break;
        default:
          break;
      }
    }

    /**
     * `document`'s content changed on disk. is_externally_modified is a
     * sticky "unsynchronized" state: once set, `document` stays
     * unsynchronized through any number of further external changes,
     * only resolved by an explicit choice (Discard and Reload, or a
     * Save that overwrites disk with this tab's own content).
     *
     * Only on the *first* transition into this state does dirty
     * actually matter: a clean tab has nothing of its own at stake, so
     * it's just silently reloaded instead of ever becoming
     * unsynchronized at all; a dirty one shows the banner (if `document`
     * is the active tab).
     */
    private void mark_externally_modified (Document document) {
      if (document.is_externally_modified) {
        return;
      }

      if (!document.dirty) {
        reload_document (document);
        return;
      }

      document.is_externally_modified = true;
      tab_bar.mark_unsynchronized (document.uri, true);
      if (document.uri == active_path) {
        text_editor.set_change_banner_visible (true);
      }
    }

    /** "Discard Changes and Reload" — always wins over in-memory content, dirty or not; the banner itself is already the user's confirmation. */
    private void on_reload_requested () {
      if (active_path == null) {
        return;
      }

      var document = documents[active_path];
      if (document == null) {
        return;
      }

      reload_document (document);
    }

    /** Discards `document`'s in-memory content in favor of what's on disk right now. Only touches the editor buffer itself if it's the active tab; the tab pill's own state updates either way. */
    private void reload_document (Document document) {
      try {
        document.reload ();
      } catch (Error e) {
        warning ("failed to reload %s: %s", document.pathname, e.message);
        return;
      }

      if (document.uri == active_path) {
        show_in_editor (document.uri);
      }
      tab_bar.mark_modified (document.uri, document.dirty);
      tab_bar.mark_deleted (document.uri, false);
      tab_bar.mark_unsynchronized (document.uri, false);
      notify_active_state ();
    }

    private void mark_file_deleted (Document document, bool deleted) {
      if (document.is_deleted == deleted) {
        return;
      }

      document.is_deleted = deleted;
      tab_bar.mark_deleted (document.uri, deleted);
      tab_bar.mark_modified (document.uri, document.dirty);
      notify_active_state ();
    }

    /** The tab-bar label's folder suffix: the file's immediate parent directory name, or "" if it has none. */
    private string folder_name_of (string path) {
      var folder_name = Path.get_basename (Path.get_dirname (path));
      return folder_name == "." || folder_name == Path.DIR_SEPARATOR_S ? "" : folder_name;
    }

    private Document? find_preview () {
      foreach (var document in documents.get_values ()) {
        if (document.is_preview) {
          return document;
        }
      }
      return null;
    }

    /**
     * Finds the open document whose own external-facing identity — a
     * real file's `pathname`, or a synthetic one's plain name, e.g.
     * "Untitled-1"/"Find Results" — is exactly `title`. The one lookup
     * behind every path-taking public method here that's also reachable
     * from Opus.Dev.DevServer (`open`, `is_dirty`, `discard_tab`,
     * `save_path`): the system-test DSL addresses a tab by the very same
     * string `open_paths()`/`active_document_path` hand back to it,
     * synthetic or not — never by this class's own internal `uri` key,
     * which it has no reason to know about.
     */
    private Document? find_by_title (string title) {
      foreach (var document in documents.get_values ()) {
        if (document.title == title) {
          return document;
        }
      }
      return null;
    }

    private void activate (string path) {
      active_path = path;
      tab_bar.set_active (path);
      show_in_editor (path);
      notify_active_state ();
    }

    /** Recomputes and re-emits active_state_changed from the current active_path/documents state — safe to call defensively any time either could have changed, even if it turns out neither did. */
    private void notify_active_state () {
      if (active_path == null) {
        active_state_changed (null, false);
      } else {
        active_state_changed (active_path, documents[active_path].dirty);
      }
    }

    private bool is_find_results_tab (string uri) {
      return uri == FIND_RESULTS_TAB_URI;
    }

    private void show_in_editor (string uri) {
      if (is_find_results_tab (uri)) {
        editor_area_bin.child = find_results.widget;
        // Reset TextEditor's own buffer/active_document rather than
        // leaving it showing whatever real file was open before —
        // otherwise Ctrl+F/search_next() while this tab is active would
        // silently operate on that hidden buffer instead of doing
        // nothing, same as finish_close() already resets it once
        // there's no tab left at all.
        text_editor.set_text ("", "");
        text_editor.set_active_document (null);
        text_editor.set_change_banner_visible (false);
        diff_tracker.set_document.begin (null, "", null);
        return;
      }
      editor_area_bin.child = text_editor.widget;

      var document = documents[uri];
      // document.pathname ?? uri: an Untitled tab has no real path for
      // GtkSource's own language-guessing to key off of, same as before
      // this split — falling back to its uri (no extension either way)
      // rather than ever handing it a raw file:// one for a real file.
      var display_path = document.pathname ?? uri;
      if (document.readable) {
        text_editor.set_text (document.content, display_path);
        text_editor.clear_placeholder ();
      } else {
        text_editor.set_placeholder (_("This file can't be displayed."));
      }
      text_editor.set_change_banner_visible (document.is_externally_modified);

      var indent_size = editor_config?.indent_size_for (relative_path (display_path)) ?? DEFAULT_INDENT_SIZE;
      var insert_spaces = editor_config?.insert_spaces_for (relative_path (display_path)) ?? DEFAULT_INSERT_SPACES;
      text_editor.set_indent_size (indent_size);
      text_editor.set_indent_config (indent_size, insert_spaces);

      text_editor.set_active_document (document);
      diff_tracker.set_document.begin (document.pathname, document.content, diff_base_provider);
    }

    private void promote (Document document) {
      document.is_preview = false;
      tab_bar.mark_preview (document.uri, false);
    }

    /** The tab bar already demoted the tab itself; just keep the model in sync. */
    private void on_preview_demoted (string uri) {
      var document = documents[uri];
      if (document != null) {
        document.is_preview = false;
      }
    }

    private void on_text_changed (string new_text) {
      if (active_path == null) {
        return;
      }

      var document = documents[active_path];
      document.content = new_text;
      diff_tracker.notify_text_changed (new_text);
      if (document.is_preview) {
        promote (document);
      }
      tab_bar.mark_modified (document.uri, document.dirty);
      notify_active_state ();
    }

    private void on_tab_selected (string uri) {
      activate (uri);
    }

    private void on_tab_double_clicked (string uri) {
      var document = documents[uri];
      if (document != null && document.is_preview) {
        promote (document);
      }
    }

    private async void close_tab (string uri) {
      var document = documents[uri];
      if (document == null) {
        return;
      }

      if (!document.dirty) {
        finish_close (uri);
        return;
      }

      var choice = yield tab_bar.confirm_unsaved_close (document.name);
      switch (choice) {
        case DiscardChoice.SAVE:
          // An untitled document has nowhere to plain-save() to —
          // save_as_path() prompts for one and, on success,
          // re-keys it to the new uri it renamed the tab to,
          // which is what actually needs closing now, not the
          // old key.
          if (document.is_untitled) {
            var new_uri = yield save_as_path (uri);
            if (new_uri != null) {
              finish_close (new_uri);
            }
          } else if (save_document (document)) {
            finish_close (uri);
          }
          break;
        case DiscardChoice.DISCARD:
          finish_close (uri);
          break;
        case DiscardChoice.CANCEL:
          break;
      }
    }

    /**
     * A clean, synchronized document has nothing to write — but
     * "clean" alone isn't enough to skip this: a document can be
     * clean and still unsynchronized at once (e.g. Ctrl+Z undoing
     * back to a clean state while the "File Has Changed on Disk"
     * banner is still up). Save is one of the two ways that's meant
     * to resolve — writing this tab's own content back to disk either
     * way — so it has to actually run even then. Returns whether the
     * document is clean afterwards (i.e. the save, if attempted,
     * succeeded).
     */
    private bool save_document (Document? document) {
      if (document == null || (!document.dirty && !document.is_externally_modified)) {
        return true;
      }

      file_watcher.mark_own_write (document.pathname);
      try {
        document.save ();
      } catch (Error e) {
        file_watcher.discard_own_write (document.pathname); // never wrote, so no event will ever come consume it
        warning ("failed to save %s: %s", document.pathname, e.message);
        return false;
      }

      tab_bar.mark_modified (document.uri, document.dirty);
      tab_bar.mark_deleted (document.uri, document.is_deleted); // save() already reset this to false
      tab_bar.mark_unsynchronized (document.uri, false); // same — save() already reset is_externally_modified too
      if (document.uri == active_path) {
        text_editor.set_change_banner_visible (false);
      }
      notify_active_state ();
      return true;
    }

    private void finish_close (string uri) {
      var document = documents[uri];
      if (document?.pathname != null) {
        file_watcher.stop_watching (document.pathname);
      }
      tab_bar.remove_tab (uri);
      documents.remove (uri);
      tab_closed (uri);

      if (active_path == uri) {
        // Prefer another still-open tab over going empty — the
        // rightmost one, for now.
        var fallback = tab_bar.last_tab_path ();
        if (fallback != null) {
          activate (fallback);
        } else {
          active_path = null;
          text_editor.set_text ("", "");
          text_editor.set_change_banner_visible (false);
          text_editor.set_active_document (null);
          notify_active_state ();
        }
      }

      if (documents.size () == 0) {
        has_open_tabs_changed (false);
      }
    }

    private void close_others (string keep_uri) {
      string[] uris = {};
      foreach (var uri in documents.get_keys ()) {
        if (uri != keep_uri) {
          uris += uri;
        }
      }
      close_paths.begin (uris);
    }

    private void close_all () {
      string[] uris = {};
      foreach (var uri in documents.get_keys ()) {
        uris += uri;
      }
      close_paths.begin (uris);
    }

    /**
     * Closes each of `uris` in turn — one at a time, not
     * concurrently, so an unsaved-changes prompt for one tab never
     * overlaps another's. `owned`, not borrowed: without it, `uris`
     * is only valid for the synchronous part of the call.
     */
    private async void close_paths (owned string[] uris) {
      foreach (var uri in uris) {
        yield close_tab (uri);
      }
    }

    /**
     * A plain Save on `path` specifically, not necessarily the active tab
     * — except for an untitled document, which has nowhere to write to
     * yet and goes through the Save As flow instead. Public for
     * Opus.Dev.DevServer's own SaveTab, which addresses a tab the same
     * way it addresses CloseTab/IsDirty (see find_by_title()) —
     * the UI itself only ever reaches this through save_active()/
     * save_as_active(), always on whichever tab is active.
     */
    public async void save_path (string path) {
      var document = find_by_title (path);
      if (document != null) {
        yield save_uri (document.uri);
      }
    }

    /** The actual save-by-identity implementation behind save_path() and save_active() — the public save_path() looks its document up by display name first; save_active() already has a uri (active_path). */
    private async void save_uri (string uri) {
      var document = documents[uri];
      // !is_saveable would otherwise route this into save_as_path() —
      // a real file-save dialog writing out the Find Results tab's own
      // always-empty content (its real text lives only in find_results'
      // own buffer, never in this Document), then renaming the tab away.
      if (document == null || !document.is_saveable) {
        return;
      }

      if (document.is_untitled) {
        yield save_as_path (uri);
      } else {
        save_document (document);
      }
    }

    /**
     * Save As: asks TextEditor for a destination via the system's own
     * file chooser (an untitled document defaults to the workspace
     * root), writes the document there, and re-keys both the document
     * and its tab to the new uri. Also promotes a preview tab.
     * Returns the document's new uri on success, or null if cancelled or
     * the write itself failed.
     */
    private async string? save_as_path (string uri) {
      var document = documents[uri];
      if (document == null || !document.is_saveable) {
        return null;
      }

      // Only a real, already-loaded file has a pathname to default
      // against — an untitled document has nowhere on disk yet, hence
      // root_path instead.
      var old_pathname = document.pathname;
      var initial_folder = document.is_untitled ? root_path : Path.get_dirname (old_pathname);
      var new_path = yield text_editor.choose_save_as_path (document.name, initial_folder);
      if (new_path == null) {
        return null;
      }

      file_watcher.mark_own_write (new_path);
      try {
        document.save_as (new_path);
      } catch (Error e) {
        file_watcher.discard_own_write (new_path); // never wrote, so no event will ever come consume it
        warning ("failed to save %s: %s", new_path, e.message);
        return null;
      }

      var new_uri = document.uri;
      documents.remove (uri);
      documents[new_uri] = document;
      if (old_pathname != null) {
        file_watcher.stop_watching (old_pathname);
      }
      file_watcher.start_watching (new_path);
      bool was_active = active_path == uri;
      if (was_active) {
        active_path = new_uri;
      }

      tab_bar.rename_tab (uri, new_uri, document.name, folder_name_of (new_path), document.title);
      tab_bar.mark_modified (new_uri, false);
      tab_bar.mark_deleted (new_uri, false);
      tab_bar.mark_unsynchronized (new_uri, false); // save_as() already reset is_externally_modified too
      stamp_tab_decoration (document);
      if (was_active) {
        text_editor.set_change_banner_visible (false);
      }
      if (document.is_preview) {
        promote (document);
      }
      notify_active_state ();
      return new_uri;
    }

    /** `path`, relative to the workspace root — `path` itself if it's somehow outside it. */
    private string relative_path (string path) {
      var prefix = root_path + "/";
      return path.has_prefix (prefix) ? path.substring (prefix.length) : path;
    }
  }
}
