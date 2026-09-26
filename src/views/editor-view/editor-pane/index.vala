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
 * tab_bar_widget/text_editor_widget are exposed separately, not one
 * `widget` — the real app places them in different parts of the window
 * (the tab bar in the header, the editor in the content pane), so
 * whoever composes *this* still needs to reach each independently.
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

    private TabBar tab_bar;
    private EditorPaneFileWatcher file_watcher;
    private string root_path;
    private EditorConfig? editor_config;

    private HashTable<string, Document> documents = new HashTable<string, Document> (str_hash, str_equal);
    private string? active_path = null;
    private int untitled_counter = 0;

    public Gtk.Widget tab_bar_widget { get { return tab_bar.widget; } }
    public Gtk.Widget text_editor_widget { get { return text_editor.widget; } }

    /** The real TextEditor itself, not just its widget — Opus.Dev.DevServer's own way to reach test-only entry points (e.g. select_all()) directly, without EditorPane wrapping each one in a forwarding method of its own. */
    public TextEditor text_editor { get; private set; }

    /** Whether at least one tab is open — whoever hosts the editor's widget uses this to hide it (an empty-state placeholder instead) when it's not. */
    public signal void has_open_tabs_changed (bool has_tabs);

    /** The active tab, or its dirty state, changed — null `path` means no tab is active (`dirty` is meaningless then). */
    public signal void active_state_changed (string? path, bool dirty);

    /** Re-emitted from TextEditor's own search sub-component — see FindBar's own "N of M" counter, wired to this wherever both are composed (MainWindow). */
    public signal void search_position_changed (int position, int count);

    /** Re-emitted from TabBar's own "Reveal in Sidebar" — whoever composes this alongside ExplorerPane (MainWindow) is the one with a reference to both. */
    public signal void reveal_in_sidebar_requested (string path);

    public EditorPane (string root_path) {
      this.root_path = root_path;
      editor_config = EditorConfig.load (root_path);

      tab_bar = new TabBar ();
      text_editor = new TextEditor ();
      file_watcher = new EditorPaneFileWatcher ();

      text_editor.text_changed.connect (on_text_changed);
      tab_bar.tab_selected.connect (on_tab_selected);
      tab_bar.tab_double_clicked.connect (on_tab_double_clicked);
      tab_bar.tab_close_requested.connect ((path) => close_tab.begin (path));
      tab_bar.preview_demoted.connect (on_preview_demoted);
      tab_bar.close_others_requested.connect (close_others);
      tab_bar.close_all_requested.connect (close_all);
      tab_bar.copy_path_requested.connect ((path) => tab_bar.copy_to_clipboard (path));
      tab_bar.copy_relative_path_requested.connect ((path) => tab_bar.copy_to_clipboard (relative_path (path)));
      tab_bar.new_file_requested.connect (new_untitled);
      tab_bar.reveal_in_sidebar_requested.connect ((path) => reveal_in_sidebar_requested (path));
      text_editor.reload_requested.connect (on_reload_requested);
      text_editor.search_position_changed.connect ((position, count) => search_position_changed (position, count));
      file_watcher.file_changed.connect (on_file_changed);
    }

    /** "Open Folder…" swaps the sidebar to a new root, in the same window — open tabs stay open, only future "Copy Relative Path" calls resolve against the new root. */
    public void set_root_path (string root_path) {
      this.root_path = root_path;
      editor_config = EditorConfig.load (root_path);
    }

    /**
     * Opens `path`, as a preview tab or a permanent one, reusing an
     * existing tab if already open. A permanent open also moves
     * keyboard focus into the editor.
     */
    public void open (string path, bool as_permanent) throws Error {
      if (documents.contains (path)) {
        if (as_permanent) {
          promote (documents[path]);
        }
        activate (path);
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

      var document = Document.untitled (name);
      documents[name] = document;
      tab_bar.add_tab (name, name, "", false);
      if (documents.size () == 1) {
        has_open_tabs_changed (true);
      }
      activate (name);
      text_editor.grab_focus ();
    }

    /** Saves the active document, if any and if dirty — see save_path(). */
    public async void save_active () {
      if (active_path != null) {
        yield save_path (active_path);
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
      var document = documents[path];
      return document != null && document.dirty;
    }

    /** The active tab's path, or null if none. */
    public string? active_document_path {
      get { return active_path; }
    }

    /** Every currently open tab's path — Opus.Dev.DevServer's own ListOpenTabs, no UI caller today. */
    public string[] open_paths () {
      string[] paths = {};
      foreach (var path in documents.get_keys ()) {
        paths += path;
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
      text_editor.set_text (text, active_path);
      tab_bar.mark_modified (document.path, document.dirty);
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

    /** Closes `path`'s tab outright, no unsaved-changes prompt — for when the file itself is already gone (deleted from the sidebar) and there's nothing left to save it to. No-op if `path` isn't open. */
    public void discard_tab (string path) {
      if (documents.contains (path)) {
        finish_close (path);
      }
    }

    /**
     * `old_path` moved to `new_path` on disk (a sidebar Rename, or a
     * Cut+Paste actually moving rather than copying). Only ever
     * matches a path that was directly opened as its own tab.
     */
    public void file_moved (string old_path, string new_path) {
      var document = documents[old_path];
      if (document == null) {
        return;
      }

      file_watcher.stop_watching (old_path);
      document.move_to (new_path);
      documents.remove (old_path);
      documents[new_path] = document;
      file_watcher.start_watching (new_path);

      tab_bar.rename_tab (old_path, new_path, Path.get_basename (new_path), folder_name_of (new_path));

      if (active_path == old_path) {
        active_path = new_path;
      }
      notify_active_state ();
    }

    /** Cascades to the file-watcher sub-component's own close(). */
    public void close () {
      file_watcher.close ();
    }

    private void open_preview (string path) throws Error {
      var existing_preview = find_preview ();
      if (existing_preview != null) {
        tab_bar.remove_tab (existing_preview.path);
        documents.remove (existing_preview.path);
        file_watcher.stop_watching (existing_preview.path);
      }

      var document = Document.load (path);
      document.is_preview = true;
      documents[path] = document;
      tab_bar.add_tab (path, Path.get_basename (path), folder_name_of (path), true);
      file_watcher.start_watching (path);
      if (documents.size () == 1) {
        has_open_tabs_changed (true);
      }
      activate (path);
    }

    private void open_permanent (string path) throws Error {
      var document = Document.load (path);
      document.is_preview = false;
      documents[path] = document;
      tab_bar.add_tab (path, Path.get_basename (path), folder_name_of (path), false);
      file_watcher.start_watching (path);
      if (documents.size () == 1) {
        has_open_tabs_changed (true);
      }
      activate (path);
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
      var document = documents[path];
      if (document == null) {
        return;
      }

      switch (event_type) {
        case FileMonitorEvent.DELETED:
        case FileMonitorEvent.MOVED_OUT:
          mark_file_deleted (path, document, true);
          break;
        case FileMonitorEvent.CREATED:
          mark_file_deleted (path, document, false);
          break;
        case FileMonitorEvent.RENAMED:
          if (other_file_path == null || other_file_path != path) {
            break;
          }
          if (document.is_deleted) {
            mark_file_deleted (path, document, false);
          } else {
            mark_externally_modified (path, document);
          }
          break;
        case FileMonitorEvent.CHANGED:
          mark_externally_modified (path, document);
          break;
        default:
          break;
      }
    }

    /**
     * `path`'s content changed on disk. is_externally_modified is a
     * sticky "unsynchronized" state: once set, `document` stays
     * unsynchronized through any number of further external changes,
     * only resolved by an explicit choice (Discard and Reload, or a
     * Save that overwrites disk with this tab's own content).
     *
     * Only on the *first* transition into this state does dirty
     * actually matter: a clean tab has nothing of its own at stake, so
     * it's just silently reloaded instead of ever becoming
     * unsynchronized at all; a dirty one shows the banner (if `path`
     * is the active tab).
     */
    private void mark_externally_modified (string path, Document document) {
      if (document.is_externally_modified) {
        return;
      }

      if (!document.dirty) {
        reload_document (path, document);
        return;
      }

      document.is_externally_modified = true;
      tab_bar.mark_unsynchronized (path, true);
      if (path == active_path) {
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

      reload_document (active_path, document);
    }

    /** Discards `document`'s in-memory content in favor of what's on disk right now. Only touches the editor buffer itself if `path` is the active tab; the tab pill's own state updates either way. */
    private void reload_document (string path, Document document) {
      try {
        document.reload ();
      } catch (Error e) {
        warning ("failed to reload %s: %s", path, e.message);
        return;
      }

      if (path == active_path) {
        show_in_editor (path);
      }
      tab_bar.mark_modified (path, document.dirty);
      tab_bar.mark_deleted (path, false);
      tab_bar.mark_unsynchronized (path, false);
      notify_active_state ();
    }

    private void mark_file_deleted (string path, Document document, bool deleted) {
      if (document.is_deleted == deleted) {
        return;
      }

      document.is_deleted = deleted;
      tab_bar.mark_deleted (path, deleted);
      tab_bar.mark_modified (path, document.dirty);
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

    private void show_in_editor (string path) {
      var document = documents[path];
      if (document.readable) {
        text_editor.set_text (document.content, path);
        text_editor.clear_placeholder ();
      } else {
        text_editor.set_placeholder (_("This file can't be displayed."));
      }
      text_editor.set_change_banner_visible (document.is_externally_modified);

      var indent_size = editor_config?.indent_size_for (relative_path (path)) ?? DEFAULT_INDENT_SIZE;
      var insert_spaces = editor_config?.insert_spaces_for (relative_path (path)) ?? DEFAULT_INSERT_SPACES;
      text_editor.set_indent_size (indent_size);
      text_editor.set_indent_config (indent_size, insert_spaces);

      text_editor.set_active_document (document);
    }

    private void promote (Document document) {
      document.is_preview = false;
      tab_bar.mark_preview (document.path, false);
    }

    /** The tab bar already demoted the tab itself; just keep the model in sync. */
    private void on_preview_demoted (string path) {
      var document = documents[path];
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
      if (document.is_preview) {
        promote (document);
      }
      tab_bar.mark_modified (document.path, document.dirty);
      notify_active_state ();
    }

    private void on_tab_selected (string path) {
      activate (path);
    }

    private void on_tab_double_clicked (string path) {
      var document = documents[path];
      if (document != null && document.is_preview) {
        promote (document);
      }
    }

    private async void close_tab (string path) {
      var document = documents[path];
      if (document == null) {
        return;
      }

      if (!document.dirty) {
        finish_close (path);
        return;
      }

      var choice = yield tab_bar.confirm_unsaved_close (Path.get_basename (path));
      switch (choice) {
        case DiscardChoice.SAVE:
          // An untitled document has nowhere to plain-save() to —
          // save_as_path() prompts for one and, on success,
          // re-keys it to the real path it renamed the tab to,
          // which is what actually needs closing now, not the
          // old key.
          if (document.is_untitled) {
            var new_path = yield save_as_path (path);
            if (new_path != null) {
              finish_close (new_path);
            }
          } else if (save_document (document)) {
            finish_close (path);
          }
          break;
        case DiscardChoice.DISCARD:
          finish_close (path);
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

      file_watcher.mark_own_write (document.path);
      try {
        document.save ();
      } catch (Error e) {
        file_watcher.discard_own_write (document.path); // never wrote, so no event will ever come consume it
        warning ("failed to save %s: %s", document.path, e.message);
        return false;
      }

      tab_bar.mark_modified (document.path, document.dirty);
      tab_bar.mark_deleted (document.path, document.is_deleted); // save() already reset this to false
      tab_bar.mark_unsynchronized (document.path, false); // same — save() already reset is_externally_modified too
      if (document.path == active_path) {
        text_editor.set_change_banner_visible (false);
      }
      notify_active_state ();
      return true;
    }

    private void finish_close (string path) {
      file_watcher.stop_watching (path);
      tab_bar.remove_tab (path);
      documents.remove (path);

      if (active_path == path) {
        // Prefer another still-open tab over going empty — the
        // rightmost one, for now.
        var fallback = tab_bar.last_tab_path ();
        if (fallback != null) {
          activate (fallback);
        } else {
          active_path = null;
          text_editor.set_text ("", path);
          text_editor.set_change_banner_visible (false);
          text_editor.set_active_document (null);
          notify_active_state ();
        }
      }

      if (documents.size () == 0) {
        has_open_tabs_changed (false);
      }
    }

    private void close_others (string keep_path) {
      string[] paths = {};
      foreach (var path in documents.get_keys ()) {
        if (path != keep_path) {
          paths += path;
        }
      }
      close_paths.begin (paths);
    }

    private void close_all () {
      string[] paths = {};
      foreach (var path in documents.get_keys ()) {
        paths += path;
      }
      close_paths.begin (paths);
    }

    /**
     * Closes each of `paths` in turn — one at a time, not
     * concurrently, so an unsaved-changes prompt for one tab never
     * overlaps another's. `owned`, not borrowed: without it, `paths`
     * is only valid for the synchronous part of the call.
     */
    private async void close_paths (owned string[] paths) {
      foreach (var path in paths) {
        yield close_tab (path);
      }
    }

    /** A plain Save on `path` specifically — except for an untitled document, which has nowhere to write to yet and goes through the Save As flow instead. */
    /** A plain Save on `path` specifically, not necessarily the active tab — except for an untitled document, which has nowhere to write to yet and goes through the Save As flow instead. Public for Opus.Dev.DevServer's own SaveTab, which addresses a tab by path — the UI itself only ever reaches this through save_active()/save_as_active(), always on whichever tab is active. */
    public async void save_path (string path) {
      var document = documents[path];
      if (document == null) {
        return;
      }

      if (document.is_untitled) {
        yield save_as_path (path);
      } else {
        save_document (document);
      }
    }

    /**
     * Save As: asks TextEditor for a destination via the system's own
     * file chooser (an untitled document defaults to the workspace
     * root), writes the document there, and re-keys both the document
     * and its tab to the new path. Also promotes a preview tab.
     * Returns the new path on success, or null if cancelled or the
     * write itself failed.
     */
    private async string? save_as_path (string path) {
      var document = documents[path];
      if (document == null) {
        return null;
      }

      var initial_folder = document.is_untitled ? root_path : Path.get_dirname (path);
      var new_path = yield text_editor.choose_save_as_path (Path.get_basename (path), initial_folder);
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

      documents.remove (path);
      documents[new_path] = document;
      file_watcher.stop_watching (path);
      file_watcher.start_watching (new_path);
      bool was_active = active_path == path;
      if (was_active) {
        active_path = new_path;
      }

      tab_bar.rename_tab (path, new_path, Path.get_basename (new_path), folder_name_of (new_path));
      tab_bar.mark_modified (new_path, false);
      tab_bar.mark_deleted (new_path, false);
      tab_bar.mark_unsynchronized (new_path, false); // save_as() already reset is_externally_modified too
      if (was_active) {
        text_editor.set_change_banner_visible (false);
      }
      if (document.is_preview) {
        promote (document);
      }
      notify_active_state ();
      return new_path;
    }

    /** `path`, relative to the workspace root — `path` itself if it's somehow outside it. */
    private string relative_path (string path) {
      var prefix = root_path + "/";
      return path.has_prefix (prefix) ? path.substring (prefix.length) : path;
    }
  }
}
