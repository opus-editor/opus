/**
 * One Document tab: a real file, or an Untitled-N. Owns its Document,
 * its own CodeEditor (built the first time the tab is shown, and kept —
 * what makes coming back to the tab instant: the laid-out text, its
 * colors and its scroll are all still there), the "changed on disk"
 * banner, the watch on its own file and the git-diff feed for it.
 * Loading/saving/Save As and the on-disk change handling live here too;
 * which tabs exist, which is active, and the one-preview rule are the
 * pane's.
 *
 * The pane hands over what is the folder's rather than the file's — the
 * .editorconfig, the git decorations registry, the diff base provider —
 * and this tab asks each for its own file.
 *
 * Talks to the pane only through ITab's own signals — it never touches
 * TabBar, a sibling it doesn't own.
 */
namespace EditorView.EditorPane {
  public class TabDocument : Object, ITab {
    // No `.editorconfig`, or none of its sections match a given file —
    // VS Code's own default `tabSize`, and a reasonable one on its own.
    private const int DEFAULT_INDENT_SIZE = 4;
    // Matches current native behavior — Tab only switches to inserting
    // spaces once a file's own .editorconfig explicitly says so.
    private const bool DEFAULT_INSERT_SPACES = false;

    // How many of these exist right now — Opus.Dev.DevServer's own way to
    // see a closed tab that was never taken apart.
    public static int live_count = 0;

    public Document document { get; private set; }

    private UserSettings user_settings;
    private GtkSource.SearchSettings? search_settings;
    private Gtk.Box root;
    private TabDocumentChangeBanner change_banner;
    private TabDocumentFileWatcher file_watcher = new TabDocumentFileWatcher ();
    private GitDiff.DocumentTracker diff_tracker = new GitDiff.DocumentTracker ();
    private GitDiff.IBaseProvider? diff_base_provider = null;
    // The provider changed while this tab was hidden: recompute when it shows again.
    private bool hunks_stale = false;
    private string root_path;
    private EditorConfig? editor_config = null;
    private FileDecoration.Registry? decorations = null;

    // Null until first shown — a session restores many tabs and shows one.
    private CodeEditor? editor = null;
    private bool is_shown = false;

    public string uri { owned get { return document.uri; } }
    public string title { owned get { return document.title; } }
    public string name { owned get { return document.name; } }
    public string folder_name { owned get { return document.pathname == null ? "" : folder_name_of (document.pathname); } }
    public bool has_pathname { get { return document.pathname != null; } }
    public bool is_preview { get { return document.is_preview; } }
    public bool is_dirty { get { return document.dirty; } }
    public Gtk.Widget widget { get { return root; } }
    public TabCapability capabilities { get { return TabCapability.TEXT_SEARCH; } }
    public CodeEditor? search_editor { get { return code_editor; } }

    /** The real CodeEditor, once the tab has been shown — Opus.Dev.DevServer's own way to reach test-only entry points (e.g. select_all()) directly. */
    public CodeEditor? code_editor { get { return editor; } }

    /** This tab closed with a file behind it, and where its cursor was — what Ctrl+Shift+T brings back. `line` is 1-based, `column` 0-based, as go_to_line() takes them. */
    public signal void file_tab_closed (string path, int line, int column);

    /** `search_settings` is the pane's one Find query, shared by every tab's editor. */
    public TabDocument (Document document, UserSettings user_settings, GtkSource.SearchSettings? search_settings, string root_path) {
      this.document = document;
      this.user_settings = user_settings;
      this.search_settings = search_settings;
      this.root_path = root_path;
      live_count++;

      change_banner = new TabDocumentChangeBanner ();
      root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
      root.append (change_banner.widget);

      change_banner.discard_clicked.connect (reload_document);
      file_watcher.file_changed.connect (on_file_changed);
      diff_tracker.hunks_changed.connect (() => editor?.set_hunks (diff_tracker.hunks ()));
      if (document.pathname != null) {
        file_watcher.watch (document.pathname);
      }
    }

    /** The folder's .editorconfig, for this file's indentation; takes effect the next time the editor is built. `root_path` is where Save As starts for an untitled document. */
    public void set_editor_config (EditorConfig? config, string root_path) {
      editor_config = config;
      this.root_path = root_path;
    }

    /** The folder's git decorations, null with no folder — stamps this tab's own tint right away, and again on restamp_decoration(). */
    public void set_decorations (FileDecoration.Registry? registry) {
      decorations = registry;
      restamp_decoration ();
    }

    /** The registry changed: this file's tint may have. An Untitled tab (no real `pathname`) never has anything to decorate. `decorations == null` explicitly clears rather than skipping, so a tab tinted before "Close Folder" doesn't keep a stale tint. */
    public void restamp_decoration () {
      if (document.pathname == null) {
        return;
      }
      decoration_changed (decorations == null ? null : decorations.decoration_for (document.pathname, false));
    }

    /** The folder's diff base provider, null with no folder or no plugin for it — hunks recompute now if the tab is showing, else when it next does. */
    public void set_diff_base_provider (GitDiff.IBaseProvider? provider) {
      diff_base_provider = provider;
      if (editor != null && is_shown) {
        recompute_hunks ();
      } else {
        hunks_stale = true;
      }
    }

    public void shown () {
      is_shown = true;
      ensure_editor ();
      if (hunks_stale) {
        recompute_hunks ();
      }
      // The pane only relays the active editor's search position: this one's is news now.
      editor.announce_search_position ();
    }

    public void hidden () {
      is_shown = false;
    }

    /** Moves keyboard focus into this tab's editor. */
    public void grab_focus () {
      ensure_editor ();
      editor.grab_focus ();
    }

    /**
     * Builds the editor and binds the document into it, once: the text,
     * its language, the indentation, the cursors, where it is scrolled
     * to — set here, then simply living in the widget.
     */
    private void ensure_editor () {
      if (editor != null) {
        return;
      }
      editor = new CodeEditor (user_settings, search_settings);
      editor.widget.vexpand = true;
      root.append (editor.widget);

      load_into_editor ();
      editor.set_indent (
        editor_config?.indent_size_for (relative_path (display_path ())) ?? DEFAULT_INDENT_SIZE,
        editor_config?.insert_spaces_for (relative_path (display_path ())) ?? DEFAULT_INSERT_SPACES
      );
      editor.bind (document.cursors, document.history);
      // A fresh editor already shows the top; scrolling there would only nudge the margin away.
      if (document.top_line > 1) {
        editor.scroll_to_top_line (document.top_line);
      }
      change_banner.set_visible (document.is_externally_modified);

      editor.text_changed.connect (on_text_changed);
      editor.search_position_changed.connect ((position, count) => search_position_changed (position, count));
      recompute_hunks ();
    }

    /** The document's content into the editor. An unreadable file shows a placeholder message instead, read-only and with no language (a "" path guesses none). */
    private void load_into_editor () {
      editor.read_only = !document.readable;
      editor.set_text (document.readable ? document.content : _("This file can't be displayed."),
                       document.readable ? display_path () : "",
                       document.readable ? document.language_override : null);
    }

    private void recompute_hunks () {
      hunks_stale = false;
      diff_tracker.set_document.begin (document.pathname, document.content, diff_base_provider);
    }

    /** An Untitled tab has no real path for language detection to key off of — its uri (no extension either way) stands in, never a raw file:// one for a real file. */
    private string display_path () {
      return document.pathname ?? document.uri;
    }

    /**
     * Places a collapsed cursor at (1-based `line`, 0-based `column`)
     * and scrolls it into view — the Command Bar's own `:30`. Both
     * clamped to the content as it is now (see
     * char_offset_of_line_column). A no-op with an unreadable document
     * (not valid UTF-8 — see Document.readable): that shows a
     * placeholder, not the file, so nothing in it corresponds to the line.
     */
    public void go_to_line (int line, int column) {
      if (!document.readable) {
        return;
      }
      ensure_editor ();
      int target_offset = char_offset_of_line_column (document.content, line, column);
      document.cursors.set_cursors ({ new Cursor (target_offset) });
      editor.render_cursors (document.cursors.snapshot ());
      editor.reveal_offset (target_offset);
    }

    /** The primary cursor's 1-based line and the document's line count — the Command Bar's own `:` hint. False for an unreadable document. */
    public bool caret_position (out int line, out int line_count) {
      line = 0;
      line_count = 0;
      if (!document.readable) {
        return false;
      }
      int caret = document.content.index_of_nth_char (document.cursors.primary.position_offset);
      line = 1 + count_newlines (document.content, caret);
      line_count = 1 + count_newlines (document.content, document.content.length);
      return true;
    }

    /** The Command Bar's own `#` list — what the document defines, and the line its caret is on. Null for an unreadable document. */
    public CommandBar.DocumentSymbols? symbols () {
      int line, line_count;
      if (!caret_position (out line, out line_count)) {
        return null;
      }
      ensure_editor ();
      Syntax.Symbol[] found;
      bool ready = editor.symbols (out found);
      return new CommandBar.DocumentSymbols (found, editor.lists_symbols, ready, line);
    }

    /** How this tab would be saved in a session, or null for a tab with no file behind it. */
    public SessionTab? session_tab () {
      if (document.pathname == null) {
        return null;
      }
      int line, column;
      primary_cursor_position (out line, out column);
      int top_line = editor != null && document.readable ? editor.top_line : document.top_line;
      return new SessionTab (document.pathname, line, column, top_line, document.is_preview);
    }

    /** The document's current content — Opus.Dev.DevServer's own GetActiveText, the reverse of set_content(). */
    public string content {
      owned get { return document.content; }
    }

    /**
     * Replaces the content wholesale, as if the user had retyped the
     * whole buffer — Opus.Dev.DevServer's own SetActiveText, no UI caller
     * today (a person editing for real goes through on_text_changed()
     * instead). Unlike that path, this also has to push the new text
     * into the real buffer itself.
     */
    public void set_content (string text) {
      ensure_editor ();
      document.content = text;
      promote ();
      editor.read_only = false;
      editor.set_text (text, display_path (), document.language_override);
      emit_marks ();
    }

    /** Whether the language was picked by hand. */
    public bool has_language_override {
      get { return document.language_override != null; }
    }

    /** Sets the language by hand: a language package's name, or null to go back to what the file's own name says. Kept on the Document, so it survives a "Save As". */
    public void set_language (string? language_name) {
      document.language_override = language_name;
      editor?.set_language_override (language_name);
    }

    /**
     * Replaces the cursor set and renders it — Opus.Dev.DevServer's own
     * SetActiveCursors. `anchors[i]`/`positions[i]` pair up into one
     * cursor each; a collapsed cursor has `anchors[i] == positions[i]`.
     * A no-op if the two arrays don't have the same length.
     */
    public void set_cursors (int[] anchors, int[] positions) {
      if (anchors.length != positions.length) {
        return;
      }
      ensure_editor ();
      var cursor_set = new Cursor[anchors.length];
      for (int i = 0; i < anchors.length; i++) {
        var cursor = new Cursor (anchors[i]);
        cursor.position_offset = positions[i];
        cursor_set[i] = cursor;
      }
      document.cursors.set_cursors (cursor_set);
      editor.render_cursors (document.cursors.snapshot ());
    }

    /** The current cursor set — Opus.Dev.DevServer's own GetActiveCursors, the reverse of set_cursors(). */
    public void get_cursors (out int[] anchors, out int[] positions) {
      var cursor_set = document.cursors.snapshot ();
      anchors = new int[cursor_set.length];
      positions = new int[cursor_set.length];
      for (int i = 0; i < cursor_set.length; i++) {
        anchors[i] = cursor_set[i].anchor_offset;
        positions[i] = cursor_set[i].position_offset;
      }
    }

    /** The file moved to `new_path` on disk (a sidebar Rename, or a Cut+Paste actually moving) — the tab follows it. */
    public void move_to (string new_path) {
      var old_uri = document.uri;
      document.move_to (new_path);
      file_watcher.watch (new_path);
      renamed (old_uri);
      restamp_decoration ();
    }

    public async void close () {
      if (!document.dirty) {
        finish_close ();
        return;
      }

      var choice = yield Dialogs.confirm_discard (widget, document.name);
      switch (choice) {
        case DiscardChoice.SAVE:
          // An untitled document has nowhere to plain-save() to —
          // save_as() prompts for one.
          if (document.is_untitled) {
            if (yield save_as ()) {
              finish_close ();
            }
          } else if (save_document ()) {
            finish_close ();
          }
          break;
        case DiscardChoice.DISCARD:
          finish_close ();
          break;
        case DiscardChoice.CANCEL:
          break;
      }
    }

    /** Closes outright, no unsaved-changes prompt — for when the file itself is already gone (deleted from the sidebar) and there's nothing left to save it to. */
    public void discard () {
      finish_close ();
    }

    public void dispose_tab () {
      file_watcher.close ();
      diff_tracker.set_document.begin (null, "", null);
      editor?.close ();
      editor = null;
      live_count--;
    }

    public void zoom_in () {
      editor?.zoom_in ();
    }

    public void zoom_out () {
      editor?.zoom_out ();
    }

    public void reset_zoom () {
      editor?.reset_zoom ();
    }

    public void promote () {
      if (!document.is_preview) {
        return;
      }
      document.is_preview = false;
      preview_changed (false);
    }

    /** Saves, if dirty — the Save As flow instead for an untitled document. */
    public async void save () {
      if (document.is_untitled) {
        yield save_as ();
      } else {
        save_document ();
      }
    }

    /**
     * Save As: asks for a destination via the system's own file chooser
     * (an untitled document defaults to the workspace root), writes the
     * document there, and renames the tab to the new uri. Also promotes a
     * preview tab. Returns whether it saved — false if cancelled or the
     * write itself failed.
     */
    public async bool save_as () {
      // Only a real, already-loaded file has a pathname to default
      // against — an untitled document has nowhere on disk yet.
      var initial_folder = document.is_untitled ? root_path : Path.get_dirname (document.pathname);
      var new_path = yield choose_save_as_path (document.name, initial_folder);
      if (new_path == null) {
        return false;
      }

      var old_uri = document.uri;
      var old_pathname = document.pathname;
      // Watching the new path before the write: its own event is the one to swallow.
      file_watcher.watch (new_path);
      file_watcher.mark_own_write ();
      try {
        document.save_as (new_path);
      } catch (Error e) {
        file_watcher.discard_own_write (); // never wrote, so no event will ever come consume it
        if (old_pathname != null) {
          file_watcher.watch (old_pathname);
        } else {
          file_watcher.unwatch ();
        }
        warning ("failed to save %s: %s", new_path, e.message);
        return false;
      }

      renamed (old_uri);
      // save_as() already reset every flag emit_marks() reads.
      emit_marks ();
      restamp_decoration ();
      change_banner.set_visible (false);
      promote ();
      return true;
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
     * A clean, synchronized document has nothing to write — but "clean"
     * alone isn't enough to skip this: a document can be clean and still
     * unsynchronized at once (e.g. Ctrl+Z undoing back to a clean state
     * while the "File Has Changed on Disk" banner is still up). Save is
     * one of the two ways that's meant to resolve — writing this tab's
     * own content back to disk either way — so it has to actually run
     * even then. Returns whether the document is clean afterwards.
     */
    private bool save_document () {
      if (!document.dirty && !document.is_externally_modified) {
        return true;
      }

      file_watcher.mark_own_write ();
      try {
        document.save ();
      } catch (Error e) {
        file_watcher.discard_own_write (); // never wrote, so no event will ever come consume it
        warning ("failed to save %s: %s", document.pathname, e.message);
        return false;
      }

      // save() already reset is_deleted/is_externally_modified too.
      emit_marks ();
      change_banner.set_visible (false);
      return true;
    }

    private void finish_close () {
      closed ();
      if (document.pathname != null) {
        int line, column;
        primary_cursor_position (out line, out column);
        file_tab_closed (document.pathname, line, column);
      }
    }

    /** The primary cursor's 1-based line and 0-based column, counted in characters. */
    private void primary_cursor_position (out int line, out int column) {
      int caret = document.content.index_of_nth_char (document.cursors.primary.position_offset);
      line = 1 + count_newlines (document.content, caret);
      int line_start = document.content.substring (0, caret).last_index_of_char ('\n') + 1;
      column = document.content.substring (line_start, caret - line_start).char_count ();
    }

    /**
     * The file was deleted, or came back, or changed content — reading
     * the raw event from file_watcher.file_changed. The RENAMED-onto-
     * itself ambiguity (a plain resave looks identical at the GIO level
     * to a delete-then-recreate) is resolved by whether the document was
     * already known deleted.
     */
    private void on_file_changed (FileMonitorEvent event_type, string? other_file_path) {
      switch (event_type) {
        case FileMonitorEvent.DELETED:
        case FileMonitorEvent.MOVED_OUT:
          mark_file_deleted (true);
          break;
        case FileMonitorEvent.CREATED:
          mark_file_deleted (false);
          break;
        case FileMonitorEvent.RENAMED:
          if (other_file_path == null || other_file_path != document.pathname) {
            break;
          }
          if (document.is_deleted) {
            mark_file_deleted (false);
          } else {
            mark_externally_modified ();
          }
          break;
        case FileMonitorEvent.CHANGED:
          mark_externally_modified ();
          break;
        default:
          break;
      }
    }

    /**
     * The content changed on disk. is_externally_modified is a sticky
     * "unsynchronized" state: once set, the document stays unsynchronized
     * through any number of further external changes, only resolved by
     * an explicit choice (Discard and Reload, or a Save that overwrites
     * disk with this tab's own content).
     *
     * Only on the *first* transition into this state does dirty actually
     * matter: a clean tab has nothing of its own at stake, so it's just
     * silently reloaded instead of ever becoming unsynchronized at all; a
     * dirty one shows the banner.
     */
    private void mark_externally_modified () {
      if (document.is_externally_modified) {
        return;
      }
      if (!document.dirty) {
        reload_document ();
        return;
      }
      document.is_externally_modified = true;
      emit_marks ();
      change_banner.set_visible (true);
    }

    /** Discards the in-memory content in favor of what's on disk right now — "Discard Changes and Reload" always wins over in-memory content, dirty or not; the banner itself is already the user's confirmation. */
    private void reload_document () {
      try {
        document.reload ();
      } catch (Error e) {
        warning ("failed to reload %s: %s", document.pathname, e.message);
        return;
      }
      if (editor != null) {
        load_into_editor ();
        editor.render_cursors (document.cursors.snapshot ());
        recompute_hunks ();
      }
      change_banner.set_visible (false);
      emit_marks ();
    }

    private void mark_file_deleted (bool deleted) {
      if (document.is_deleted == deleted) {
        return;
      }
      document.is_deleted = deleted;
      emit_marks ();
    }

    /** The pill state, straight off the document's own flags — the pane also derives the active tab's dirty state from this. */
    private void emit_marks () {
      marks_changed (document.dirty, document.is_deleted, document.is_externally_modified);
    }

    private void on_text_changed (string new_text) {
      document.content = new_text;
      diff_tracker.notify_text_changed (new_text);
      promote ();
      emit_marks ();
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
     * same convention FindInFilesMatch's own fields use. Both are clamped
     * to the content as it is *now*: a result can be older than the
     * buffer, and a line past the end or a column past the line must land
     * at the nearest real position, never spill into the next line or
     * past the buffer.
     */
    public static int char_offset_of_line_column (string content, int line, int column) {
      var lines = content.split ("\n");
      int line_index = (line - 1).clamp (0, lines.length - 1);
      int offset = 0;
      for (int i = 0; i < line_index; i++) {
        offset += lines[i].char_count () + 1;
      }
      return offset + column.clamp (0, lines[line_index].char_count ());
    }

    /** The tab-bar label's folder suffix: the file's immediate parent directory name, or "" if it has none. */
    private static string folder_name_of (string path) {
      var folder_name = Path.get_basename (Path.get_dirname (path));
      return folder_name == "." || folder_name == Path.DIR_SEPARATOR_S ? "" : folder_name;
    }

    /** `path`, relative to the workspace root — `path` itself if it's somehow outside it. */
    private string relative_path (string path) {
      var prefix = root_path + "/";
      return path.has_prefix (prefix) ? path.substring (prefix.length) : path;
    }
  }
}
