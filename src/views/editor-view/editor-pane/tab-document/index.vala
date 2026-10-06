/**
 * The Document tab kind: every real file (and Untitled-N) open in the
 * pane, rendered one at a time in one shared CodeEditor — the same
 * widget reused across every Document tab, rebound on each switch,
 * rather than one editor per tab (CodeEditor's own zoom/font state is
 * display-wide, and diff_tracker below only ever tracks the one
 * showing). Owns the Document list, loading/saving/Save As, the
 * .editorconfig lookup, the git-diff gutter feed, and the on-disk change
 * handling (TabDocumentFileWatcher + TabDocumentChangeBanner).
 *
 * Talks to the pane only through ITabKind's own signals — it never
 * touches TabBar, a sibling it doesn't own.
 */
namespace EditorView.EditorPane {
  public class TabDocument : Object, ITabKind {
    // No `.editorconfig`, or none of its sections match a given file —
    // VS Code's own default `tabSize`, and a reasonable one on its own.
    private const int DEFAULT_INDENT_SIZE = 4;
    // Matches current native behavior — Tab only switches to inserting
    // spaces once a file's own .editorconfig explicitly says so.
    private const bool DEFAULT_INSERT_SPACES = false;

    private Gtk.Box root;
    private TabDocumentChangeBanner change_banner;
    private TabDocumentFileWatcher file_watcher;
    private string root_path;
    private EditorConfig? editor_config;

    private HashTable<string, Document> documents = new HashTable<string, Document> (str_hash, str_equal);
    // The Document currently bound into code_editor, or null while
    // another kind's tab (or none) is active — set by show(), cleared by
    // hide().
    private string? active_uri = null;
    private int untitled_counter = 0;

    // Owned by MainWindow (outlives a single linked folder — see
    // GIT_STATUS_PLUGIN_PLAN.md's own "Host wiring" section), handed here
    // via set_decorations() so every open tab, not just the active one,
    // can be tinted — null with no folder linked.
    private FileDecoration.Registry? decorations = null;

    // Same "owned by MainWindow, handed in via a setter" shape as
    // `decorations` above, but unlike it, only the active document's
    // hunks are ever rendered (one shared CodeEditorSourceView buffer,
    // not one per tab) — so `diff_tracker` is a single instance, reset on
    // every tab switch, not a per-document map.
    private GitDiff.DocumentTracker diff_tracker = new GitDiff.DocumentTracker ();
    private GitDiff.IBaseProvider? diff_base_provider = null;

    public Gtk.Widget widget { get { return root; } }
    public TabCapability capabilities { get { return TabCapability.TEXT_SEARCH; } }
    public CodeEditor? search_editor { get { return code_editor; } }

    /** The real CodeEditor itself, not just its widget — Opus.Dev.DevServer's own way to reach test-only entry points (e.g. select_all()) directly. */
    public CodeEditor code_editor { get; private set; }

    public TabDocument (string root_path, UserSettings user_settings) {
      this.root_path = root_path;
      editor_config = EditorConfig.load (root_path);

      code_editor = new CodeEditor (user_settings);
      change_banner = new TabDocumentChangeBanner ();
      file_watcher = new TabDocumentFileWatcher ();

      root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
      root.append (change_banner.widget);
      code_editor.widget.vexpand = true;
      root.append (code_editor.widget);

      code_editor.text_changed.connect (on_text_changed);
      code_editor.search_position_changed.connect ((position, count) => search_position_changed (position, count));
      change_banner.discard_clicked.connect (on_reload_requested);
      file_watcher.file_changed.connect (on_file_changed);
      diff_tracker.hunks_changed.connect (() => code_editor.set_hunks (diff_tracker.hunks ()));
    }

    /** "Open Folder…" swaps the sidebar to a new root, in the same window — open tabs stay open, only future .editorconfig lookups resolve against the new root. */
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
      var document = active_document ();
      if (document != null) {
        diff_tracker.set_document.begin (document.pathname, document.content, diff_base_provider);
      }
    }

    /** Re-stamps every open tab (not just the active one — a background tab whose file changes elsewhere still needs its own tint to update) from the current `decorations` snapshot. */
    private void refresh_tab_decorations () {
      foreach (var document in documents.get_values ()) {
        stamp_tab_decoration (document);
      }
    }

    /** An Untitled tab (no real `pathname`) never has anything to decorate. `decorations == null` (no folder linked) explicitly clears rather than skipping, so a tab tinted before "Close Folder" doesn't keep showing a stale tint afterward. */
    private void stamp_tab_decoration (Document document) {
      if (document.pathname == null) {
        return;
      }
      tab_decoration_changed (document.uri, decorations == null ? null : decorations.decoration_for (document.pathname, false));
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
          promote_document (existing);
        }
        activate_requested (existing.uri);
      } else if (as_permanent) {
        open_permanent (path);
      } else {
        open_preview (path);
      }

      if (as_permanent) {
        code_editor.grab_focus ();
      }
    }

    /**
     * Find Results' own Ctrl+click-to-navigate — opens `path` as a preview
     * tab (same weight as a single click in the explorer) and, if `line`
     * is not -1 (the skipped-mtime list's own "just open it" case — see
     * TabFindResults.NavTarget's own doc comment), places a collapsed cursor
     * at that (1-based line, 0-based column) and scrolls it into view.
     * Swallows a failed open the same way open_from_explorer() (MainWindow)
     * does — nothing else here is in a position to surface the error.
     */
    public void open_at (string path, int line, int column) {
      try {
        open (path, false);
      } catch (Error e) {
        warning ("failed to open %s: %s", path, e.message);
        return;
      }

      // open()'s own grab_focus() only runs for as_permanent — a preview
      // open here (already-open tabs included) would otherwise sometimes
      // leave focus behind in Find Results' own code_editor instead of
      // following the jump.
      code_editor.grab_focus ();

      if (line >= 0) {
        go_to_line (line, column);
      }
    }

    /**
     * Places a collapsed cursor at (1-based `line`, 0-based `column`) in
     * the active document and scrolls it into view — the Command Bar's
     * own `:30`. Both clamped to the content as it is now (see
     * char_offset_of_line_column). A no-op while no Document tab is
     * active, or with an unreadable one (not valid UTF-8 — see
     * Document.readable): that shows a placeholder, not the file, so
     * nothing in it corresponds to the line.
     */
    public void go_to_line (int line, int column) {
      var document = active_document ();
      if (document == null || !document.readable) {
        return;
      }

      int target_offset = char_offset_of_line_column (document.content, line, column);
      document.cursors.set_cursors ({ new Cursor (target_offset) });
      code_editor.render_cursors (document.cursors.snapshot ());
      code_editor.reveal_offset (target_offset);
    }

    /** The primary cursor's 1-based line and the active document's line count — the Command Bar's own `:` hint. False while no readable Document tab is active. */
    public bool caret_position (out int line, out int line_count) {
      line = 0;
      line_count = 0;
      var document = active_document ();
      if (document == null || !document.readable) {
        return false;
      }

      int caret = document.content.index_of_nth_char (document.cursors.primary.position_offset);
      line = 1 + count_newlines (document.content, caret);
      line_count = 1 + count_newlines (document.content, document.content.length);
      return true;
    }

    /** The Command Bar's own `#` list — what the active document defines, and the line its caret is on. Null while no readable Document tab is active. */
    public CommandBar.DocumentSymbols? active_symbols () {
      int line, line_count;
      if (!caret_position (out line, out line_count)) {
        return null;
      }
      Syntax.Symbol[] symbols;
      bool ready = code_editor.symbols (out symbols);
      return new CommandBar.DocumentSymbols (symbols, code_editor.lists_symbols, ready, line);
    }

    private static int count_newlines (string text, int end_byte) {
      int count = 0;
      for (int i = 0; i < end_byte; i++) {
        if (text[i] == '\n') {
          count++;
        }
      }
      return count;
    }

    /**
     * `line` is 1-based, `column` a 0-based char offset into that line —
     * same convention FindInFilesMatch's own fields use, so its data
     * plugs straight in with no translation at the call site. Both are
     * clamped to the content as it is *now*: a result can be older than
     * the buffer (the file edited since the search, or its tab already
     * open and dirty), and a line past the end or a column past the
     * line must land at the nearest real position, never spill into the
     * next line or past the buffer.
     */
    private int char_offset_of_line_column (string content, int line, int column) {
      var lines = content.split ("\n");
      int line_index = (line - 1).clamp (0, lines.length - 1);
      int offset = 0;
      for (int i = 0; i < line_index; i++) {
        offset += lines[i].char_count () + 1;
      }
      return offset + column.clamp (0, lines[line_index].char_count ());
    }

    /** Opens a brand-new, not-yet-saved-anywhere tab named "Untitled-N" — a permanent tab, focused immediately. Saving it goes through the Save As flow regardless of "Save" or "Save as…", since there's nowhere on disk yet for a plain Save to write to. */
    public void new_untitled () {
      untitled_counter++;
      var name = "Untitled-%d".printf (untitled_counter);

      var document = Document.untitled (untitled_counter.to_string (), name);
      register (document, "", false);
      activate_requested (document.uri);
      code_editor.grab_focus ();
    }

    /** Whether `path` is currently open as a tab with unsaved changes — by title, the way Opus.Dev.DevServer and MainWindow's own delete flow address a tab (see find_by_title()). */
    public bool is_path_dirty (string path) {
      var document = find_by_title (path);
      return document != null && document.dirty;
    }

    public bool is_dirty (string uri) {
      return documents[uri]?.dirty ?? false;
    }

    /** The active document's current buffer content, or "" if none — Opus.Dev.DevServer's own GetActiveText, the reverse of set_active_content(). */
    public string active_content {
      owned get { return active_document ()?.content ?? ""; }
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
      var document = active_document ();
      if (document == null) {
        return;
      }

      document.content = text;
      if (document.is_preview) {
        promote_document (document);
      }
      code_editor.read_only = false;
      code_editor.set_text (text, document.pathname ?? document.uri, document.language_override);
      emit_marks (document);
    }

    /**
     * Replaces the active document's cursor set and renders it — Opus.Dev.DevServer's
     * own SetActiveCursors, still handy for the system-test DSL to seed a
     * multi-cursor starting state without typing/clicking it into place
     * first. `anchors[i]`/`positions[i]` pair up into one cursor each; a
     * collapsed cursor has `anchors[i] == positions[i]`. A no-op if the
     * two arrays don't have the same length, or if there's no active
     * document.
     */
    /** Whether a document tab is the one showing. */
    public bool has_active {
      get { return active_document () != null; }
    }

    /** Whether the active tab's language was picked by hand — false with no tab active. */
    public bool active_has_language_override {
      get {
        var document = active_document ();
        return document != null && document.language_override != null;
      }
    }

    /**
     * Sets the active tab's language by hand: a language package's
     * name, or null to go back to what the file's own name says. Kept
     * on the Document, so it stays with the tab through switching away
     * and back, and through a "Save As". A no-op with no tab active.
     */
    public void set_active_language (string? language_name) {
      var document = active_document ();
      if (document == null) {
        return;
      }
      document.language_override = language_name;
      code_editor.set_language_override (language_name);
    }

    public void set_active_cursors (int[] anchors, int[] positions) {
      var document = active_document ();
      if (document == null || anchors.length != positions.length) {
        return;
      }

      var cursor_set = new Cursor[anchors.length];
      for (int i = 0; i < anchors.length; i++) {
        var cursor = new Cursor (anchors[i]);
        cursor.position_offset = positions[i];
        cursor_set[i] = cursor;
      }

      document.cursors.set_cursors (cursor_set);
      code_editor.render_cursors (document.cursors.snapshot ());
    }

    /**
     * The active document's current cursor set — Opus.Dev.DevServer's own
     * GetActiveCursors, the reverse of set_active_cursors(). Each `out`
     * array is empty when there's no active document.
     */
    public void get_active_cursors (out int[] anchors, out int[] positions) {
      var document = active_document ();
      if (document == null) {
        anchors = {};
        positions = {};
        return;
      }

      var cursor_set = document.cursors.snapshot ();
      anchors = new int[cursor_set.length];
      positions = new int[cursor_set.length];
      for (int i = 0; i < cursor_set.length; i++) {
        anchors[i] = cursor_set[i].anchor_offset;
        positions[i] = cursor_set[i].position_offset;
      }
    }

    /**
     * `old_path` moved to `new_path` on disk (a sidebar Rename, or a
     * Cut+Paste actually moving rather than copying). Only ever matches a
     * path that was directly opened as its own tab — both arguments are
     * always real OS paths.
     */
    public void file_moved (string old_path, string new_path) {
      var old_uri = Document.uri_for_path (old_path);
      var document = documents[old_uri];
      if (document == null) {
        return;
      }

      file_watcher.stop_watching (old_path);
      document.move_to (new_path);
      file_watcher.start_watching (new_path);
      rekey (old_uri, document, folder_name_of (new_path));
      stamp_tab_decoration (document);
    }

    /** Re-keys `document` (already moved/saved to its new uri) from `old_uri` in every map here and announces the rename — the pane re-keys its own registry and TabBar off the signal. */
    private void rekey (string old_uri, Document document, string folder_name) {
      var new_uri = document.uri;
      documents.remove (old_uri);
      documents[new_uri] = document;
      if (active_uri == old_uri) {
        active_uri = new_uri;
      }
      tab_renamed (old_uri, new_uri, document.name, folder_name, document.title, true);
    }

    public void close () {
      file_watcher.close ();
    }

    public bool owns (string uri) {
      return documents.contains (uri);
    }

    /** Binds `uri`'s Document into the shared CodeEditor. */
    public void show (string uri) {
      var document = documents[uri];
      if (document == null) {
        return;
      }
      active_uri = uri;

      // document.pathname ?? uri: an Untitled tab has no real path for
      // GtkSource's own language-guessing to key off of — falling back to
      // its uri (no extension either way) rather than ever handing it a
      // raw file:// one for a real file.
      var display_path = document.pathname ?? uri;
      // An unreadable file shows a placeholder message instead of
      // content, read-only and with no language (a "" path guesses
      // none) — without that, the message would still highlight as the
      // previous file's own language.
      code_editor.read_only = !document.readable;
      code_editor.set_text (document.readable ? document.content : _("This file can't be displayed."),
                            document.readable ? display_path : "",
                            document.readable ? document.language_override : null);
      change_banner.set_visible (document.is_externally_modified);

      var indent_size = editor_config?.indent_size_for (relative_path (display_path)) ?? DEFAULT_INDENT_SIZE;
      var insert_spaces = editor_config?.insert_spaces_for (relative_path (display_path)) ?? DEFAULT_INSERT_SPACES;
      code_editor.set_indent (indent_size, insert_spaces);

      code_editor.bind (document.cursors, document.history);
      diff_tracker.set_document.begin (document.pathname, document.content, diff_base_provider);
    }

    /**
     * Resets the shared CodeEditor's own buffer/cursor state rather than
     * leaving it showing whatever Document was open before — otherwise a
     * keystroke that still reaches the hidden editor (Opus.Dev.DevServer's
     * own KeyPress) could turn into a text_changed() that lands in a
     * Document that isn't showing. Read-only too, for the same reason.
     */
    public void hide () {
      active_uri = null;
      code_editor.read_only = true;
      code_editor.set_text ("", "");
      code_editor.unbind ();
      change_banner.set_visible (false);
      diff_tracker.set_document.begin (null, "", null);
    }

    public async void close_tab (string uri) {
      var document = documents[uri];
      if (document == null) {
        return;
      }

      if (!document.dirty) {
        finish_close (uri);
        return;
      }

      var choice = yield Dialogs.confirm_discard (widget, document.name);
      switch (choice) {
        case DiscardChoice.SAVE:
          // An untitled document has nowhere to plain-save() to —
          // save_as_uri() prompts for one and, on success, re-keys it
          // to the new uri it renamed the tab to, which is what
          // actually needs closing now, not the old key.
          if (document.is_untitled) {
            var new_uri = yield save_as_uri (uri);
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

    /** Closes `uri` outright, no unsaved-changes prompt — for when the file itself is already gone (deleted from the sidebar) and there's nothing left to save it to. */
    public void discard_tab (string uri) {
      if (documents.contains (uri)) {
        finish_close (uri);
      }
    }

    public void zoom_in () {
      code_editor.zoom_in ();
    }

    public void zoom_out () {
      code_editor.zoom_out ();
    }

    public void reset_zoom () {
      code_editor.reset_zoom ();
    }

    public void promote (string uri) {
      var document = documents[uri];
      if (document != null && document.is_preview) {
        promote_document (document);
      }
    }

    /**
     * A plain Save on `path` specifically, not necessarily the active tab
     * — except for an untitled document, which has nowhere to write to
     * yet and goes through the Save As flow instead. Opus.Dev.DevServer's
     * own SaveTab, which addresses a tab the same way it addresses
     * CloseTab/IsDirty (see find_by_title()) — the UI itself only ever
     * reaches this through save_uri()/save_as_uri(), always on whichever
     * tab is active.
     */
    public async void save_path (string path) {
      var document = find_by_title (path);
      if (document != null) {
        yield save_uri (document.uri);
      }
    }

    /** Saves `uri`'s Document, if dirty — the Save As flow instead for an untitled one. A no-op for a uri that isn't one of this kind's. */
    public async void save_uri (string uri) {
      var document = documents[uri];
      if (document == null) {
        return;
      }

      if (document.is_untitled) {
        yield save_as_uri (uri);
      } else {
        save_document (document);
      }
    }

    /**
     * Save As: asks for a destination via the system's own
     * file chooser (an untitled document defaults to the workspace
     * root), writes the document there, and re-keys both the document
     * and its tab to the new uri. Also promotes a preview tab.
     * Returns the document's new uri on success, or null if cancelled or
     * the write itself failed.
     */
    public async string? save_as_uri (string uri) {
      var document = documents[uri];
      if (document == null) {
        return null;
      }

      // Only a real, already-loaded file has a pathname to default
      // against — an untitled document has nowhere on disk yet, hence
      // root_path instead.
      var old_pathname = document.pathname;
      var initial_folder = document.is_untitled ? root_path : Path.get_dirname (old_pathname);
      var new_path = yield choose_save_as_path (document.name, initial_folder);
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

      if (old_pathname != null) {
        file_watcher.stop_watching (old_pathname);
      }
      file_watcher.start_watching (new_path);
      rekey (uri, document, folder_name_of (new_path));
      // save_as() already reset every flag emit_marks() reads.
      emit_marks (document);
      stamp_tab_decoration (document);
      if (document.uri == active_uri) {
        change_banner.set_visible (false);
      }
      if (document.is_preview) {
        promote_document (document);
      }
      return document.uri;
    }

    /** Shows the system's own Save-As file chooser, pre-filled with `suggested_name` in `current_folder`. Returns the chosen path, or null if cancelled or the dialog/portal itself failed. */
    private async string? choose_save_as_path (string suggested_name, string current_folder) {
      var dialog = new Gtk.FileDialog ();
      dialog.initial_name = suggested_name;
      dialog.initial_folder = File.new_for_path (current_folder);

      try {
        var file = yield dialog.save (root.get_root () as Gtk.Window, null);
        return file != null ? file.get_path () : null;
      } catch (Error e) {
        return null;
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
    private bool save_document (Document document) {
      if (!document.dirty && !document.is_externally_modified) {
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

      // save() already reset is_deleted/is_externally_modified too.
      emit_marks (document);
      if (document.uri == active_uri) {
        change_banner.set_visible (false);
      }
      return true;
    }

    /**
     * Loads first, evicts the previous preview tab second: the other way
     * round, a failed load would lose the old preview for nothing, and
     * tab_removed for a still-active tab would make the pane fall back
     * to some unrelated tab for an instant before the new one lands.
     */
    private void open_preview (string path) throws Error {
      var document = Document.load (path);
      document.is_preview = true;
      var previous_preview = find_preview ();
      register (document, folder_name_of (path), true);
      activate_requested (document.uri);

      if (previous_preview != null) {
        finish_close (previous_preview.uri);
      }
    }

    private void open_permanent (string path) throws Error {
      var document = Document.load (path);
      document.is_preview = false;
      register (document, folder_name_of (path), false);
      activate_requested (document.uri);
    }

    /** The one place a new Document enters this kind: its map entry, its tab chrome (tab_added first — the decoration that follows needs the pill to exist), and its disk watch. */
    private void register (Document document, string folder_name, bool preview) {
      documents[document.uri] = document;
      tab_added (document.uri, document.name, folder_name, preview, document.title, document.pathname != null);
      stamp_tab_decoration (document);
      if (document.pathname != null) {
        file_watcher.start_watching (document.pathname);
      }
    }

    /** A tab with a file behind it closed, and where its cursor was — what Ctrl+Shift+T brings back. `line` is 1-based, `column` 0-based, as open_at() takes them. */
    public signal void file_tab_closed (string path, int line, int column);

    private void finish_close (string uri) {
      var document = documents[uri];
      if (document == null) {
        return;
      }
      if (document.pathname != null) {
        file_watcher.stop_watching (document.pathname);
      }
      documents.remove (uri);
      tab_removed (uri);
      if (document.pathname != null) {
        int line, column;
        primary_cursor_position (document, out line, out column);
        file_tab_closed (document.pathname, line, column);
      }
    }

    /** The primary cursor's 1-based line and 0-based column, counted in characters. */
    private static void primary_cursor_position (Document document, out int line, out int column) {
      int caret = document.content.index_of_nth_char (document.cursors.primary.position_offset);
      line = 1 + count_newlines (document.content, caret);
      int line_start = document.content.substring (0, caret).last_index_of_char ('\n') + 1;
      column = document.content.substring (line_start, caret - line_start).char_count ();
    }

    /**
     * `path` itself was deleted, or came back, or changed content —
     * reading the raw event from file_watcher.file_changed. The
     * RENAMED-onto-`path` ambiguity (a plain resave looks identical at
     * the GIO level to a delete-then-recreate) is resolved by whether
     * this document was already known deleted.
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
      emit_marks (document);
      if (document.uri == active_uri) {
        change_banner.set_visible (true);
      }
    }

    /** "Discard Changes and Reload" — always wins over in-memory content, dirty or not; the banner itself is already the user's confirmation. */
    private void on_reload_requested () {
      var document = active_document ();
      if (document != null) {
        reload_document (document);
      }
    }

    /** Discards `document`'s in-memory content in favor of what's on disk right now. Only touches the editor buffer itself if it's the active tab; the tab pill's own state updates either way. */
    private void reload_document (Document document) {
      try {
        document.reload ();
      } catch (Error e) {
        warning ("failed to reload %s: %s", document.pathname, e.message);
        return;
      }

      if (document.uri == active_uri) {
        show (document.uri);
      }
      emit_marks (document);
    }

    private void mark_file_deleted (Document document, bool deleted) {
      if (document.is_deleted == deleted) {
        return;
      }

      document.is_deleted = deleted;
      emit_marks (document);
    }

    /** `document`'s pill state, straight off its own flags — the pane also derives the active tab's dirty state from this. */
    private void emit_marks (Document document) {
      tab_marks_changed (document.uri, document.dirty, document.is_deleted, document.is_externally_modified);
    }

    private void promote_document (Document document) {
      document.is_preview = false;
      tab_preview_changed (document.uri, false);
    }

    private void on_text_changed (string new_text) {
      var document = active_document ();
      if (document == null) {
        return;
      }

      document.content = new_text;
      diff_tracker.notify_text_changed (new_text);
      if (document.is_preview) {
        promote_document (document);
      }
      emit_marks (document);
    }

    private Document? active_document () {
      return active_uri == null ? null : documents[active_uri];
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
     * real file's `pathname`, or an untitled one's plain name, e.g.
     * "Untitled-1" — is exactly `title`. The one lookup behind every
     * path-taking public method here that's also reachable from
     * Opus.Dev.DevServer (`open`, `is_path_dirty`, `save_path`): the
     * system-test DSL addresses a tab by the very same string the pane's
     * open_paths()/active_document_path hand back to it, synthetic or
     * not — never by this class's own internal `uri` key, which it has
     * no reason to know about.
     */
    private Document? find_by_title (string title) {
      foreach (var document in documents.get_values ()) {
        if (document.title == title) {
          return document;
        }
      }
      return null;
    }

    /** `path`, relative to the workspace root — `path` itself if it's somehow outside it. */
    private string relative_path (string path) {
      var prefix = root_path + "/";
      return path.has_prefix (prefix) ? path.substring (prefix.length) : path;
    }
  }
}
