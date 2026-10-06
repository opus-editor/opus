/**
 * The pane that hosts every open tab: TabBar on top, the active tab's
 * own widget below, every other tab's widget kept alive behind it in a
 * stack — coming back to a tab shows it as it was left, with nothing to
 * lay out or repaint again. Each tab is its own EditorPane.ITab (a
 * TabDocument per document, the one TabFindResults); this class keeps
 * the registry of them, turns each tab's chrome signals into TabBar
 * calls, routes TabBar's gestures and MainWindow's shortcuts to the
 * active one, and holds what is the folder's rather than any one
 * file's: the one-preview rule, the Untitled numbering, the
 * .editorconfig, the git decorations registry and the diff base
 * provider, handed to each document tab for it to ask about its own
 * file.
 *
 * TabBar's own "Reveal in Sidebar" is the one signal this re-emits
 * rather than handling itself — its target (ExplorerPane) is a sibling
 * this class has no reference to; MainWindow, which composes both, is
 * what actually wires it through.
 */
namespace EditorView {
  public class EditorPaneWidget : Object {
    // The one widget actually exposed via `widget` below — its own
    // `.child` toggles between `content` (tab bar + editor area) and
    // `empty_state`, kept in sync with has_open_tabs_changed right in
    // the constructor, so whoever hosts `widget` never needs to touch
    // it again after placing it once.
    private Adw.Bin container;
    private Gtk.Box content;
    private Adw.StatusPage empty_state;
    // Every open tab's widget, the active one on top. No transition:
    // the whole point is the next tab being there at once.
    private Gtk.Stack stack;
    private EditorPane.TabBar tab_bar;
    private string root_path;
    private UserSettings user_settings;

    private HashTable<string, EditorPane.ITab> tabs = new HashTable<string, EditorPane.ITab> (str_hash, str_equal);
    private EditorPane.ITab? active = null;

    // What is the folder's, not any one file's — see the class comment.
    private int untitled_counter = 0;
    private EditorPane.TabDocument? preview_tab = null;
    private EditorConfig? editor_config;
    private FileDecoration.Registry? decorations = null;
    private GitDiff.IBaseProvider? diff_base_provider = null;
    // One Find query for every document tab's editor: the FindBar's term follows the user from tab to tab.
    private GtkSource.SearchSettings search_settings = new GtkSource.SearchSettings ();

    // Created lazily (first search only) — most windows never run one.
    private EditorPane.TabFindResults? tab_find_results = null;

    public Gtk.Widget widget { get { return container; } }

    /** The active tab, when it is a document — null otherwise (Find Results active, or nothing). */
    public EditorPane.TabDocument? active_document {
      get { return active as EditorPane.TabDocument; }
    }

    /** The active document tab's own CodeEditor, or null — Opus.Dev.DevServer's own KeyPress/SelectAll, and the Command Bar's previews and focus. */
    public CodeEditor? code_editor {
      get { return active_document?.code_editor; }
    }

    /** The editor FindBar acts on — the active tab's own, or null when the active tab has no text search (or there is none). MainWindow and Opus.Dev.DevServer drive CodeEditor's own search API through this directly. */
    public CodeEditor? search_editor {
      get { return active?.search_editor; }
    }

    /** Whether at least one tab is open — `widget` itself already reacts to this (see the constructor); still re-emitted for whoever hosts it to react too (MainWindow closes FindBar once the last tab goes). */
    public signal void has_open_tabs_changed (bool has_tabs);

    /** The active tab, or its dirty state, changed — null `path` means no tab is active (`dirty` is meaningless then). */
    public signal void active_state_changed (string? path, bool dirty);

    /** A tab for `path` just started existing (opened permanent or preview) — unlike active_state_changed, this fires once per tab regardless of focus, for whoever needs to know a specific path is open at all rather than merely active (MainWindow's own settings.json live-reload watch). `path` is the tab's uri. */
    public signal void tab_opened (string path);

    /** A tab for `path` just stopped existing (closed, discarded, or evicted as an old preview) — see tab_opened()'s own doc comment. */
    public signal void tab_closed (string path);
    /** A file tab closed, with where its cursor was — see TabDocument.file_tab_closed. */
    public signal void file_tab_closed (string path, int line, int column);
    /** Anything a saved session would record changed: a tab opened, closed, renamed, reordered, promoted, or made active. */
    public signal void tabs_changed ();

    /** Re-emitted from the active tab's own search — see FindBar's own "N of M" counter, wired to this wherever both are composed (MainWindow). */
    public signal void search_position_changed (int position, int count);

    /** Re-emitted from TabBar's own "Reveal in Sidebar" — whoever composes this alongside ExplorerPane (MainWindow) is the one with a reference to both. */
    public signal void reveal_in_sidebar_requested (string path);

    public EditorPaneWidget (string root_path, UserSettings user_settings) {
      this.root_path = root_path;
      this.user_settings = user_settings;
      editor_config = EditorConfig.load (root_path);
      search_settings.set_wrap_around (true);

      tab_bar = new EditorPane.TabBar ();
      stack = new Gtk.Stack () { vexpand = true, transition_type = Gtk.StackTransitionType.NONE, hhomogeneous = false, vhomogeneous = false };

      content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
      content.append (tab_bar.widget);
      content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { css_classes = { "content-divider" } });
      content.append (stack);

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

      tab_bar.tab_selected.connect (activate);
      tab_bar.tab_double_clicked.connect ((uri) => tabs[uri]?.promote ());
      tab_bar.preview_demoted.connect ((uri) => tabs[uri]?.promote ());
      tab_bar.tab_close_requested.connect ((uri) => close_tabs.begin ({ uri }));
      tab_bar.close_others_requested.connect (close_others);
      tab_bar.close_all_requested.connect (close_all);
      // TabBar only offers Copy Path / Reveal in Sidebar for a tab with a
      // real path, whose title *is* that path — so resolving the uri back
      // to a title is all there is to it.
      tab_bar.copy_path_requested.connect ((uri) => tab_bar.copy_to_clipboard (title_of (uri)));
      tab_bar.copy_relative_path_requested.connect ((uri) => tab_bar.copy_to_clipboard (relative_path (title_of (uri))));
      tab_bar.new_file_requested.connect (new_untitled);
      tab_bar.reordered.connect (() => tabs_changed ());
      tab_bar.reveal_in_sidebar_requested.connect ((uri) => reveal_in_sidebar_requested (title_of (uri)));
    }

    /**
     * Connects `tab`'s chrome signals, once for its lifetime — a tab that
     * can leave and come back (Find Results) is wired once and
     * registered each time. `closed` is where a tab leaves everything
     * here, and is taken apart.
     */
    private void wire_tab (EditorPane.ITab tab) {
      tab.closed.connect (() => {
        if (!tabs.contains (tab.uri)) {
          return;
        }
        var uri = tab.uri;
        tab_bar.remove_tab (uri);
        tabs.remove (uri);
        stack.remove (tab.widget);
        if (tab == preview_tab) {
          preview_tab = null;
        }
        tab_closed (uri);
        on_tab_gone (tab);
        tab.dispose_tab ();
        tabs_changed ();
      });
      tab.renamed.connect ((old_uri) => {
        tabs.remove (old_uri);
        tabs[tab.uri] = tab;
        tab_bar.rename_tab (old_uri, tab.uri, tab.name, tab.folder_name, tab.title, tab.has_pathname);
        notify_active_state ();
        tabs_changed ();
      });
      tab.marks_changed.connect ((modified, deleted, unsynchronized) => {
        tab_bar.mark_modified (tab.uri, modified);
        tab_bar.mark_deleted (tab.uri, deleted);
        tab_bar.mark_unsynchronized (tab.uri, unsynchronized);
        if (tab == active) {
          active_state_changed (tab.uri, modified);
        }
      });
      tab.preview_changed.connect ((preview) => {
        if (!preview && tab == preview_tab) {
          preview_tab = null;
        }
        tab_bar.mark_preview (tab.uri, preview);
        tabs_changed ();
      });
      tab.decoration_changed.connect ((decoration) => tab_bar.mark_decoration (tab.uri, decoration));
      tab.activate_requested.connect (() => activate (tab.uri));
      tab.search_position_changed.connect ((position, count) => {
        if (tab == active) {
          search_position_changed (position, count);
        }
      });
    }

    /** `tab` enters the pane: registry, stack, TabBar (first — the decoration that may follow needs the pill to exist). */
    private void register_tab (EditorPane.ITab tab) {
      tabs[tab.uri] = tab;
      stack.add_child (tab.widget);
      tab_bar.add_tab (tab.uri, tab.name, tab.folder_name, tab.is_preview, tab.title, tab.has_pathname);
      tab_opened (tab.uri);
      if (tabs.size () == 1) {
        has_open_tabs_changed (true);
      }
      tabs_changed ();
    }

    /** A new document tab, with everything the folder lends it, wired and registered — the one place a TabDocument is made. */
    private EditorPane.TabDocument add_document_tab (Document document) {
      var tab = new EditorPane.TabDocument (document, user_settings, search_settings, root_path);
      tab.set_editor_config (editor_config, root_path);
      tab.set_decorations (decorations);
      tab.set_diff_base_provider (diff_base_provider);
      tab.file_tab_closed.connect ((path, line, column) => file_tab_closed (path, line, column));
      wire_tab (tab);
      register_tab (tab);
      return tab;
    }

    /** The clean, user-facing name behind `uri`. Falls back to `uri` itself, which should never actually happen for a tab that exists. */
    private string title_of (string uri) {
      return tabs[uri]?.title ?? uri;
    }

    /** The open tab whose title is `title`, or null — Opus.Dev.DevServer addresses a tab by the very same string open_paths()/active_document_path hand back to it, never by a uri it has no reason to know about. */
    private EditorPane.ITab? tab_for_title (string title) {
      foreach (var tab in tabs.get_values ()) {
        if (tab.title == title) {
          return tab;
        }
      }
      return null;
    }

    private EditorPane.TabDocument? document_tab_for_title (string title) {
      return tab_for_title (title) as EditorPane.TabDocument;
    }

    /** Every document tab, for what the folder hands to all of them. */
    private GenericArray<EditorPane.TabDocument> document_tabs () {
      var found = new GenericArray<EditorPane.TabDocument> ();
      foreach (var tab in tabs.get_values ()) {
        var document_tab = tab as EditorPane.TabDocument;
        if (document_tab != null) {
          found.add (document_tab);
        }
      }
      return found;
    }

    /** "Open Folder…" swaps the sidebar to a new root, in the same window — open tabs stay open, only future "Copy Relative Path"/.editorconfig lookups resolve against the new root. */
    public void set_root_path (string root_path) {
      this.root_path = root_path;
      editor_config = EditorConfig.load (root_path);
      foreach (var tab in document_tabs ()) {
        tab.set_editor_config (editor_config, root_path);
      }
    }

    /** MainWindow calls this in lockstep with linking/unlinking a folder — null on "Close Folder" (or a window that never had one), clearing every open tab's own tint the same way it applied one. */
    public void set_decorations (FileDecoration.Registry? new_decorations) {
      if (decorations != null) {
        decorations.changed.disconnect (restamp_decorations);
      }
      decorations = new_decorations;
      if (decorations != null) {
        decorations.changed.connect (restamp_decorations);
      }
      foreach (var tab in document_tabs ()) {
        tab.set_decorations (decorations);
      }
    }

    /** The registry changed: every tab's own tint may have, not just the active one's. */
    private void restamp_decorations () {
      foreach (var tab in document_tabs ()) {
        tab.restamp_decoration ();
      }
    }

    /** MainWindow calls this in lockstep with linking/unlinking a folder — null on "Close Folder", or if the plugin providing it goes away. */
    public void set_diff_base_provider (GitDiff.IBaseProvider? new_provider) {
      diff_base_provider = new_provider;
      foreach (var tab in document_tabs ()) {
        tab.set_diff_base_provider (new_provider);
      }
    }

    /**
     * Opens `path`, as a preview tab or a permanent one, reusing an
     * existing tab if already open. A permanent open also moves keyboard
     * focus into the editor. A preview replaces the previous preview —
     * loaded first, evicted second: the other way round, a failed load
     * would lose the old preview for nothing, and the pane would fall
     * back to some unrelated tab for an instant before the new one lands.
     */
    public void open (string path, bool as_permanent) throws Error {
      var tab = document_tab_for_title (path);
      if (tab != null) {
        if (as_permanent) {
          tab.promote ();
        }
        activate (tab.uri);
      } else {
        var document = Document.load (path);
        document.is_preview = !as_permanent;
        var previous_preview = preview_tab;
        tab = add_document_tab (document);
        if (!as_permanent) {
          preview_tab = tab;
        }
        activate (tab.uri);
        previous_preview?.discard ();
      }

      if (as_permanent) {
        tab.grab_focus ();
      }
    }

    /**
     * Find Results' own Ctrl+click-to-navigate — opens `path` as a preview
     * tab (same weight as a single click in the explorer) and, if `line`
     * is not -1 (the skipped-mtime list's own "just open it" case — see
     * TabFindResults.NavTarget's own doc comment), places a collapsed
     * cursor at that (1-based line, 0-based column) and scrolls it into
     * view. Swallows a failed open the same way open_from_explorer()
     * (MainWindow) does — nothing else here is in a position to surface
     * the error.
     */
    private void open_at (string path, int line, int column) {
      try {
        open (path, false);
      } catch (Error e) {
        warning ("failed to open %s: %s", path, e.message);
        return;
      }
      // open()'s own grab_focus() only runs for as_permanent — a preview
      // open here would otherwise leave focus behind in Find Results' own
      // editor instead of following the jump.
      active_document?.grab_focus ();
      if (line >= 0) {
        go_to_line (line, column);
      }
    }

    /** Opens a brand-new, not-yet-saved-anywhere tab named "Untitled-N" — a permanent tab, focused immediately. Saving it goes through the Save As flow regardless of "Save" or "Save as…", since there's nowhere on disk yet for a plain Save to write to. */
    public void new_untitled () {
      untitled_counter++;
      var document = Document.untitled (untitled_counter.to_string (), "Untitled-%d".printf (untitled_counter));
      var tab = add_document_tab (document);
      activate (tab.uri);
      tab.grab_focus ();
    }

    /**
     * This pane's tabs as a session would keep them: the file tabs in
     * the bar's order, and which of them is active. `folder` is the
     * session's; the pane doesn't know what is linked.
     */
    public SavedSession session (string folder) {
      var kept = new GenericArray<SessionTab> ();
      string? active_path = null;
      foreach (unowned string uri in tab_bar.paths_in_order ()) {
        var tab = (tabs[uri] as EditorPane.TabDocument)?.session_tab ();
        if (tab == null) {
          continue;
        }
        kept.add (tab);
        if (tabs[uri] == active) {
          active_path = tab.path;
        }
      }
      return new SavedSession (folder, kept, active_path);
    }

    /**
     * Brings a session's tabs back, in its order, and shows the active
     * one — only that one builds its editor; the rest are tabs in the bar
     * until clicked. A tab whose file can't be read is left out.
     */
    public void restore_session (SavedSession session) {
      foreach (var saved in session.tabs) {
        try {
          var document = Document.load (saved.path);
          document.is_preview = saved.preview;
          document.cursors.set_cursors ({ new Cursor (EditorPane.TabDocument.char_offset_of_line_column (document.content, saved.line, saved.column)) });
          document.top_line = saved.top_line;
          var tab = add_document_tab (document);
          if (saved.preview) {
            preview_tab = tab;
          }
        } catch (Error e) {
          Logger.warn ("session: %s not restored: %s".printf (saved.path, e.message));
        }
      }
      var last = tab_bar.last_tab_path ();
      var active_title = session.active ?? (last != null ? title_of (last) : null);
      EditorPane.TabDocument? tab = active_title != null ? document_tab_for_title (active_title) : null;
      if (tab != null) {
        activate (tab.uri);
        tab.grab_focus ();
      }
    }

    /** Whether a tab is open on `path` right now. */
    public bool has_tab_for (string path) {
      return tab_for_title (path) != null;
    }

    /** The Command Bar's own `:30` — see TabDocument.go_to_line(). A no-op with no document active. */
    public void go_to_line (int line, int column) {
      active_document?.go_to_line (line, column);
    }

    /** The Command Bar's own `:` hint — see TabDocument.caret_position(). False with no document active. */
    public bool caret_position (out int line, out int line_count) {
      line = 0;
      line_count = 0;
      return active_document != null && active_document.caret_position (out line, out line_count);
    }

    /** The Command Bar's own `#` list — see TabDocument.symbols(). Null with no document active. */
    public CommandBar.DocumentSymbols? active_symbols () {
      return active_document?.symbols ();
    }

    /** Whether a document tab is the one showing. */
    public bool has_active_document {
      get { return active_document != null; }
    }

    /** Whether the active document's language was picked by hand — false with none active. */
    public bool active_has_language_override {
      get { return active_document != null && active_document.has_language_override; }
    }

    /** Sets the active document's language by hand — see TabDocument.set_language(). A no-op with none active. */
    public void set_active_language (string? language_name) {
      active_document?.set_language (language_name);
    }

    /** The active document's content, "" with none — Opus.Dev.DevServer's own GetActiveText. */
    public string active_content {
      owned get { return active_document?.content ?? ""; }
    }

    /** See TabDocument.set_content(). A no-op with no document active. */
    public void set_active_content (string text) {
      active_document?.set_content (text);
    }

    /** See TabDocument.set_cursors(). A no-op with no document active. */
    public void set_active_cursors (int[] anchors, int[] positions) {
      active_document?.set_cursors (anchors, positions);
    }

    /** See TabDocument.get_cursors(). Both empty with no document active. */
    public void get_active_cursors (out int[] anchors, out int[] positions) {
      if (active_document == null) {
        anchors = {};
        positions = {};
        return;
      }
      active_document.get_cursors (out anchors, out positions);
    }

    /** Find in Files — see TabFindResults.search(). The tab itself is created on the first search only, and registered whenever a search opens it. */
    public async void search_in_files (FindInFilesQuery query) {
      if (tab_find_results == null) {
        tab_find_results = new EditorPane.TabFindResults (user_settings);
        wire_tab (tab_find_results);
        tab_find_results.opened.connect (() => register_tab (tab_find_results));
        tab_find_results.navigate_requested.connect (open_at);
      }
      yield tab_find_results.search (root_path, query);
    }

    /** Saves the active tab, if it's a Document — nothing else has anything to save. */
    public async void save_active () {
      if (active_document != null) {
        yield active_document.save ();
      }
    }

    /** "Save As" on the active tab, if it's a Document — see save_active(). */
    public async void save_as_active () {
      if (active_document != null) {
        yield active_document.save_as ();
      }
    }

    /** A plain Save on `path`'s tab, not necessarily the active one — Opus.Dev.DevServer's own SaveTab. A no-op for a path that isn't open as a document. */
    public async void save_path (string path) {
      var tab = document_tab_for_title (path);
      if (tab != null) {
        yield tab.save ();
      }
    }

    /** Closes the active tab, if any — same unsaved-changes flow as its own close button. */
    public void close_active () {
      if (active != null) {
        active.close.begin ();
      }
    }

    /** Whether `path` is currently open as a tab with unsaved changes. */
    public bool is_dirty (string path) {
      return tab_for_title (path)?.is_dirty ?? false;
    }

    /** The active tab's own clean, user-facing name — its real path for a file, a plain display name otherwise — or null if none. Opus.Dev.DevServer's own GetActiveTab. */
    public string? active_document_path {
      owned get { return active?.title; }
    }

    /** The currently linked folder — MainWindow's own "Add Folder…" (FindInFilesBar's where_entry) reads this to validate a chosen folder is actually inside it before appending anything. */
    public string linked_folder_path {
      get { return root_path; }
    }

    /** See TabFindResults.active_query — null unless the Find Results tab is the active one. */
    public FindInFilesQuery? current_find_in_files_query {
      get { return tab_find_results?.active_query; }
    }

    /** Whether the active tab can do `capability` — false with no tab open, so MainWindow needs no separate "any tab open" gate for the shortcuts this answers for. */
    public bool active_tab_supports (EditorPane.TabCapability capability) {
      return active != null && capability in active.capabilities;
    }

    /** Ctrl+Plus on the active tab — whatever zooming means for it; a no-op with none open. */
    public void zoom_in () {
      active?.zoom_in ();
    }

    /** Ctrl+Minus — see zoom_in(). */
    public void zoom_out () {
      active?.zoom_out ();
    }

    /** Ctrl+0 — see zoom_in(). */
    public void reset_zoom () {
      active?.reset_zoom ();
    }

    /** Opens the active tab's own inline replace row — only meaningful when active_tab_supports(INLINE_REPLACE); a no-op otherwise, same as every other action method here trusting its own guard over the caller's. */
    public void open_replace () {
      active?.open_replace ();
    }

    /** Every currently open tab's own clean, user-facing name — Opus.Dev.DevServer's own ListOpenTabs, no UI caller today. */
    public string[] open_paths () {
      string[] paths = {};
      foreach (var tab in tabs.get_values ()) {
        paths += tab.title;
      }
      return paths;
    }

    /**
     * Closes `path`'s tab outright, no unsaved-changes prompt — for when
     * the file itself is already gone (deleted from the sidebar) and
     * there's nothing left to save it to, and Opus.Dev.DevServer's own
     * CloseTab. No-op if `path` isn't open.
     */
    public void discard_tab (string path) {
      tab_for_title (path)?.discard ();
    }

    /** `old_path` moved to `new_path` on disk — the tab open on it, if any, follows. See TabDocument.move_to(). */
    public void file_moved (string old_path, string new_path) {
      document_tab_for_title (old_path)?.move_to (new_path);
    }

    /** Window teardown: every tab taken apart. */
    public void close () {
      foreach (var tab in tabs.get_values ()) {
        tab.dispose_tab ();
      }
      tab_find_results?.dispose_tab ();
    }

    /** How many document tabs are alive, registered or not — Opus.Dev.DevServer's own GetLiveTabs, to catch a closed tab never taken apart. */
    public int live_document_tabs {
      get { return EditorPane.TabDocument.live_count; }
    }

    private void activate (string uri) {
      var tab = tabs[uri];
      if (tab == null) {
        return;
      }
      if (active != null && active != tab) {
        active.hidden ();
      }
      active = tab;
      tab_bar.set_active (uri);
      stack.visible_child = tab.widget;
      tab.shown ();
      notify_active_state ();
      tabs_changed ();
    }

    /** Recomputes and re-emits active_state_changed from the current active tab — safe to call defensively any time it could have changed, even if it turns out it didn't. */
    private void notify_active_state () {
      if (active == null) {
        active_state_changed (null, false);
      } else {
        active_state_changed (active.uri, active.is_dirty);
      }
    }

    /** The shared tail of any tab's removal: falls back to another tab if the active one just went, and announces the last one leaving. */
    private void on_tab_gone (EditorPane.ITab gone) {
      if (active == gone) {
        // Prefer another still-open tab over going empty — the
        // rightmost one, for now.
        var fallback = tab_bar.last_tab_path ();
        if (fallback != null) {
          activate (fallback);
        } else {
          gone.hidden ();
          active = null;
          notify_active_state ();
        }
      }

      if (tabs.size () == 0) {
        has_open_tabs_changed (false);
      }
    }

    private void close_others (string keep_uri) {
      string[] uris = {};
      foreach (var uri in tabs.get_keys ()) {
        if (uri != keep_uri) {
          uris += uri;
        }
      }
      close_tabs.begin (uris);
    }

    private void close_all () {
      string[] uris = {};
      foreach (var uri in tabs.get_keys ()) {
        uris += uri;
      }
      close_tabs.begin (uris);
    }

    /**
     * Closes each of `uris` in turn — one at a time, not
     * concurrently, so an unsaved-changes prompt for one tab never
     * overlaps another's. `owned`, not borrowed: without it, `uris`
     * is only valid for the synchronous part of the call.
     */
    private async void close_tabs (owned string[] uris) {
      foreach (var uri in uris) {
        var tab = tabs[uri];
        if (tab != null) {
          yield tab.close ();
        }
      }
    }

    /** `path`, relative to the workspace root — `path` itself if it's somehow outside it. */
    private string relative_path (string path) {
      var prefix = root_path + "/";
      return path.has_prefix (prefix) ? path.substring (prefix.length) : path;
    }
  }
}
