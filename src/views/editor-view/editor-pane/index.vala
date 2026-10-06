/**
 * The pane that hosts every open tab: TabBar on top, the active tab's
 * own widget below. Each *kind* of tab (a Document, Find Results, …) is
 * its own EditorPane.ITabKind owning every tab of that kind; this class
 * keeps the registry of which kind owns which uri, turns each kind's
 * chrome signals into TabBar calls, and routes TabBar's gestures and
 * MainWindow's shortcuts to whichever kind is active — see ITabKind's
 * own doc comment. No per-kind business logic lives here.
 *
 * TabBar's own "Reveal in Sidebar" is the one signal this re-emits
 * rather than handling itself — its target (ExplorerPane) is a sibling
 * this class has no reference to; MainWindow, which composes both, is
 * what actually wires it through.
 *
 * Assembles its own widget — a vertical Box, TabBar's own widget on top,
 * a divider, the active tab's own widget below (vexpand) — rather than
 * exposing the parts separately for MainWindow to place into different
 * regions of its own window template: they were never actually placed
 * in different regions, so MainWindow reaching in for each one
 * independently was only ever indirection, not a real layout need.
 */
namespace EditorView {
  public class EditorPaneWidget : Object {
    /** One registry entry per open tab — `title` is what this class answers DevServer/Copy Path with, handed over in tab_added so the kind never has to be asked again. */
    private class OpenTab : Object {
      public EditorPane.ITabKind kind;
      public string title;

      public OpenTab (EditorPane.ITabKind kind, string title) {
        this.kind = kind;
        this.title = title;
      }
    }

    // The one widget actually exposed via `widget` below — its own
    // `.child` toggles between `content` (tab bar + editor area) and
    // `empty_state`, kept in sync with has_open_tabs_changed right in
    // the constructor, so whoever hosts `widget` never needs to touch
    // it again after placing it once.
    private Adw.Bin container;
    private Gtk.Box content;
    private Adw.StatusPage empty_state;
    // Shows whichever kind's widget owns the active tab.
    private Adw.Bin editor_area_bin;
    private EditorPane.TabBar tab_bar;
    private string root_path;
    private UserSettings user_settings;

    private HashTable<string, OpenTab> tabs = new HashTable<string, OpenTab> (str_hash, str_equal);
    private string? active_path = null;
    private EditorPane.ITabKind? active_kind = null;

    // Created lazily (first search only) — most windows never run one.
    private EditorPane.TabFindResults? tab_find_results = null;

    public Gtk.Widget widget { get { return container; } }

    /** The Document kind itself — Opus.Dev.DevServer's own way to reach the Document-only entry points it drives (active_content, cursors, save_path) directly, rather than through one forwarding method here per call; see its own doc comment. */
    public EditorPane.TabDocument document_tab { get; private set; }

    /** The Document kind's own CodeEditor — Opus.Dev.DevServer's own KeyPress/SelectAll, and MainWindow's way to re-apply settings.json's display-wide font (any one instance recomputing it is enough). */
    public CodeEditor code_editor {
      get { return document_tab.code_editor; }
    }

    /** The editor FindBar acts on — the active tab's own, or null when the active tab has no text search (or there is none). MainWindow and Opus.Dev.DevServer drive CodeEditor's own search API through this directly. */
    public CodeEditor? search_editor {
      get { return active_kind?.search_editor; }
    }

    /** Whether at least one tab is open — `widget` itself already reacts to this (see the constructor); still re-emitted for whoever hosts it to react too (MainWindow closes FindBar once the last tab goes). */
    public signal void has_open_tabs_changed (bool has_tabs);

    /** The active tab, or its dirty state, changed — null `path` means no tab is active (`dirty` is meaningless then). */
    public signal void active_state_changed (string? path, bool dirty);

    /** A tab for `path` just started existing (opened permanent or preview) — unlike active_state_changed, this fires once per tab regardless of focus, for whoever needs to know a specific path is open at all rather than merely active (MainWindow's own settings.json live-reload watch). */
    public signal void tab_opened (string path);

    /** A tab for `path` just stopped existing (closed, discarded, or evicted as an old preview) — see tab_opened()'s own doc comment. */
    public signal void tab_closed (string path);
    /** A file tab closed, with where its cursor was — see TabDocument.file_tab_closed. */
    public signal void file_tab_closed (string path, int line, int column);

    /** Re-emitted from the active tab's own search — see FindBar's own "N of M" counter, wired to this wherever both are composed (MainWindow). */
    public signal void search_position_changed (int position, int count);

    /** Re-emitted from TabBar's own "Reveal in Sidebar" — whoever composes this alongside ExplorerPane (MainWindow) is the one with a reference to both. */
    public signal void reveal_in_sidebar_requested (string path);

    public EditorPaneWidget (string root_path, UserSettings user_settings) {
      this.root_path = root_path;
      this.user_settings = user_settings;

      tab_bar = new EditorPane.TabBar ();
      document_tab = new EditorPane.TabDocument (root_path, user_settings);
      wire_kind (document_tab);
      document_tab.file_tab_closed.connect ((path, line, column) => file_tab_closed (path, line, column));

      content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
      content.append (tab_bar.widget);
      content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { css_classes = { "content-divider" } });
      editor_area_bin = new Adw.Bin () { child = document_tab.widget, vexpand = true };
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

      tab_bar.tab_selected.connect (activate);
      tab_bar.tab_double_clicked.connect ((uri) => kind_of (uri)?.promote (uri));
      tab_bar.preview_demoted.connect ((uri) => kind_of (uri)?.promote (uri));
      tab_bar.tab_close_requested.connect ((uri) => close_tabs.begin ({ uri }));
      tab_bar.close_others_requested.connect (close_others);
      tab_bar.close_all_requested.connect (close_all);
      // TabBar only offers Copy Path / Reveal in Sidebar for a tab with a
      // real path, whose title *is* that path — so resolving the uri back
      // to a title is all there is to it.
      tab_bar.copy_path_requested.connect ((uri) => tab_bar.copy_to_clipboard (title_of (uri)));
      tab_bar.copy_relative_path_requested.connect ((uri) => tab_bar.copy_to_clipboard (relative_path (title_of (uri))));
      tab_bar.new_file_requested.connect (new_untitled);
      tab_bar.reveal_in_sidebar_requested.connect ((uri) => reveal_in_sidebar_requested (title_of (uri)));
    }

    /**
     * Turns `kind`'s chrome signals into TabBar calls plus this class's
     * own registry bookkeeping — the one place a kind's tabs enter and
     * leave the pane, so has_open_tabs_changed/tab_opened/tab_closed
     * fire from here rather than from each kind separately. Adding a
     * kind is constructing it and calling this.
     */
    private void wire_kind (EditorPane.ITabKind kind) {
      kind.tab_added.connect ((uri, name, folder_name, preview, title, has_pathname) => {
        tabs[uri] = new OpenTab (kind, title);
        tab_bar.add_tab (uri, name, folder_name, preview, title, has_pathname);
        tab_opened (uri);
        if (tabs.size () == 1) {
          has_open_tabs_changed (true);
        }
      });
      kind.tab_removed.connect ((uri) => {
        tab_bar.remove_tab (uri);
        tabs.remove (uri);
        tab_closed (uri);
        on_tab_gone (uri);
      });
      kind.tab_renamed.connect ((old_uri, new_uri, name, folder_name, title, has_pathname) => {
        tabs.remove (old_uri);
        tabs[new_uri] = new OpenTab (kind, title);
        tab_bar.rename_tab (old_uri, new_uri, name, folder_name, title, has_pathname);
        if (active_path == old_uri) {
          active_path = new_uri;
        }
        notify_active_state ();
      });
      kind.tab_marks_changed.connect ((uri, modified, deleted, unsynchronized) => {
        tab_bar.mark_modified (uri, modified);
        tab_bar.mark_deleted (uri, deleted);
        tab_bar.mark_unsynchronized (uri, unsynchronized);
        if (uri == active_path) {
          active_state_changed (uri, modified);
        }
      });
      kind.tab_preview_changed.connect ((uri, preview) => tab_bar.mark_preview (uri, preview));
      kind.tab_decoration_changed.connect ((uri, decoration) => tab_bar.mark_decoration (uri, decoration));
      kind.activate_requested.connect (activate);
      kind.search_position_changed.connect ((position, count) => {
        if (kind == active_kind) {
          search_position_changed (position, count);
        }
      });
    }

    private EditorPane.ITabKind? kind_of (string uri) {
      return tabs[uri]?.kind;
    }

    /** The clean, user-facing name behind `uri`, as its kind registered it. Falls back to `uri` itself, which should never actually happen for a tab that exists. */
    private string title_of (string uri) {
      return tabs[uri]?.title ?? uri;
    }

    /** The registered uri whose title is `title`, or null — Opus.Dev.DevServer addresses a tab by the very same string open_paths()/active_document_path hand back to it, never by a uri it has no reason to know about. */
    private string? uri_of_title (string title) {
      foreach (var uri in tabs.get_keys ()) {
        if (tabs[uri].title == title) {
          return uri;
        }
      }
      return null;
    }

    /** "Open Folder…" swaps the sidebar to a new root, in the same window — open tabs stay open, only future "Copy Relative Path"/.editorconfig lookups resolve against the new root. */
    public void set_root_path (string root_path) {
      this.root_path = root_path;
      document_tab.set_root_path (root_path);
    }

    public void set_decorations (FileDecoration.Registry? new_decorations) {
      document_tab.set_decorations (new_decorations);
    }

    public void set_diff_base_provider (GitDiff.IBaseProvider? new_provider) {
      document_tab.set_diff_base_provider (new_provider);
    }

    /** Opens `path` as a Document tab, preview or permanent — see TabDocument.open(). */
    public void open (string path, bool as_permanent) throws Error {
      document_tab.open (path, as_permanent);
    }

    public void new_untitled () {
      document_tab.new_untitled ();
    }

    /** Whether a tab is open on `path` right now. */
    public bool has_tab_for (string path) {
      return path in open_paths ();
    }

    /** The Command Bar's own `:30` — see TabDocument.go_to_line(). */
    public void go_to_line (int line, int column) {
      document_tab.go_to_line (line, column);
    }

    /** The Command Bar's own `:` hint — see TabDocument.caret_position(). */
    public bool caret_position (out int line, out int line_count) {
      return document_tab.caret_position (out line, out line_count);
    }

    /** The Command Bar's own `#` list — see TabDocument.active_symbols(). */
    public CommandBar.DocumentSymbols? active_symbols () {
      return document_tab.active_symbols ();
    }

    /** Find in Files — see TabFindResults.search(). The tab kind itself is created on the first search only. */
    public async void search_in_files (FindInFilesQuery query) {
      if (tab_find_results == null) {
        tab_find_results = new EditorPane.TabFindResults (user_settings);
        wire_kind (tab_find_results);
        tab_find_results.navigate_requested.connect ((path, line, column) => document_tab.open_at (path, line, column));
      }
      yield tab_find_results.search (root_path, query);
    }

    /** Saves the active tab, if it's a Document — nothing else has anything to save. */
    public async void save_active () {
      if (active_kind == document_tab) {
        yield document_tab.save_uri (active_path);
      }
    }

    /** "Save As" on the active tab, if it's a Document — see save_active(). */
    public async void save_as_active () {
      if (active_kind == document_tab) {
        yield document_tab.save_as_uri (active_path);
      }
    }

    /** Closes the active tab, if any — same unsaved-changes flow as its own close button. */
    public void close_active () {
      if (active_path != null) {
        active_kind.close_tab.begin (active_path);
      }
    }

    /** Whether `path` is currently open as a Document tab with unsaved changes. */
    public bool is_dirty (string path) {
      return document_tab.is_path_dirty (path);
    }

    /** The active tab's own clean, user-facing name — its real path for a file, a plain display name otherwise — or null if none. Opus.Dev.DevServer's own GetActiveTab. */
    public string? active_document_path {
      owned get { return active_path == null ? null : title_of (active_path); }
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
      return active_kind != null && capability in active_kind.capabilities;
    }

    /** Ctrl+Plus on the active tab — whatever zooming means for its kind; a no-op with none open. */
    public void zoom_in () {
      active_kind?.zoom_in ();
    }

    /** Ctrl+Minus — see zoom_in(). */
    public void zoom_out () {
      active_kind?.zoom_out ();
    }

    /** Ctrl+0 — see zoom_in(). */
    public void reset_zoom () {
      active_kind?.reset_zoom ();
    }

    /** Opens the active tab's own inline replace row — only meaningful when active_tab_supports(INLINE_REPLACE); a no-op otherwise, same as every other action method here trusting its own guard over the caller's. */
    public void open_replace () {
      active_kind?.open_replace ();
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
      var uri = uri_of_title (path);
      if (uri != null) {
        tabs[uri].kind.discard_tab (uri);
      }
    }

    /** `old_path` moved to `new_path` on disk — see TabDocument.file_moved(). */
    public void file_moved (string old_path, string new_path) {
      document_tab.file_moved (old_path, new_path);
    }

    /** Cascades to each kind's own close(). */
    public void close () {
      document_tab.close ();
      tab_find_results?.close ();
    }

    private void activate (string uri) {
      var kind = kind_of (uri);
      if (kind == null) {
        return;
      }
      if (active_kind != null && active_kind != kind) {
        active_kind.hide ();
      }
      active_kind = kind;
      active_path = uri;
      tab_bar.set_active (uri);
      editor_area_bin.child = kind.widget;
      kind.show (uri);
      notify_active_state ();
    }

    /** Recomputes and re-emits active_state_changed from the current active tab — safe to call defensively any time it could have changed, even if it turns out it didn't. */
    private void notify_active_state () {
      if (active_path == null) {
        active_state_changed (null, false);
      } else {
        active_state_changed (active_path, active_kind.is_dirty (active_path));
      }
    }

    /** The shared tail of any tab's removal: falls back to another tab if the active one just went, and announces the last one leaving. */
    private void on_tab_gone (string uri) {
      if (active_path == uri) {
        // Prefer another still-open tab over going empty — the
        // rightmost one, for now.
        var fallback = tab_bar.last_tab_path ();
        if (fallback != null) {
          activate (fallback);
        } else {
          active_path = null;
          active_kind.hide ();
          active_kind = null;
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
        var kind = kind_of (uri);
        if (kind != null) {
          yield kind.close_tab (uri);
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
