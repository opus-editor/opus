/**
 * Owns the open {@link Document}s and mediates between the tab bar and the
 * editor pane: opening files (as preview or permanent tabs), promoting a
 * preview tab on edit or double-click, tracking dirty state, saving, and the
 * close-with-unsaved-changes flow.
 */
public class EditorController : Object {
    private TabBarView tab_bar_view;
    private EditorView editor_view;
    private CursorController cursor_controller;
    private string root_path;

    private HashTable<string, Document> documents = new HashTable<string, Document> (str_hash, str_equal);
    private string? active_path = null;
    private int untitled_counter = 0;

    // One entry per open tab that's backed by a real file on disk (never
    // an untitled one — nothing to watch until it's actually saved
    // somewhere) — lets a tab notice the file it was opened from being
    // deleted (or moved away) by something other than Opus itself, unlike
    // FileTreeController's own directory watching (sidebar-tree only,
    // and only for expanded directories) which wouldn't otherwise catch
    // this for a file outside — or simply not currently expanded within
    // — the linked folder, or for a window with no folder linked at all.
    private HashTable<string, FileMonitor> file_watches = new HashTable<string, FileMonitor> (str_hash, str_equal);

    // Set right before this controller's own save()/save_as() writes to a
    // path, consumed by the very next file-monitor event for it. A
    // self-save produces a real filesystem event indistinguishable at the
    // GIO level from an external change (confirmed directly: FileUtils.
    // set_contents fires exactly one RENAMED event, nothing more) — this
    // is the only way to tell the two apart.
    private HashTable<string, bool> own_writes = new HashTable<string, bool> (str_hash, str_equal);

    /** Whether at least one tab is open — whoever hosts the editor's widget uses this to hide it (an empty-state placeholder instead) when it's not. */
    public signal void has_open_tabs_changed (bool has_tabs);

    /** The active tab, or its dirty state, changed — null `path` means no tab is active (`dirty` is meaningless then). Drives the primary menu's Save/Save as… group (see MainWindowView.set_active_state); Save/Save as… now live only there and on Ctrl+S/Ctrl+Shift+S, not per-tab in the tab bar's own context menu. */
    public signal void active_state_changed (string? path, bool dirty);

    public EditorController (TabBarView tab_bar_view, EditorView editor_view, string root_path) {
        this.tab_bar_view = tab_bar_view;
        this.editor_view = editor_view;
        this.root_path = root_path;
        cursor_controller = new CursorController (editor_view);

        editor_view.text_changed.connect (on_text_changed);
        tab_bar_view.tab_selected.connect (on_tab_selected);
        tab_bar_view.tab_double_clicked.connect (on_tab_double_clicked);
        tab_bar_view.tab_close_requested.connect ((path) => close_tab.begin (path));
        tab_bar_view.preview_demoted.connect (on_preview_demoted);
        tab_bar_view.close_others_requested.connect (close_others);
        tab_bar_view.close_all_requested.connect (close_all);
        tab_bar_view.copy_path_requested.connect ((path) => tab_bar_view.copy_to_clipboard (path));
        tab_bar_view.copy_relative_path_requested.connect ((path) => tab_bar_view.copy_to_clipboard (relative_path (path)));
        tab_bar_view.new_file_requested.connect (new_untitled);
        editor_view.reload_requested.connect (on_reload_requested);
    }

    /** "Open Folder…" swaps the sidebar to a new root, in the same window — open tabs stay open, only future "Copy Relative Path" calls resolve against the new root. */
    public void set_root_path (string root_path) {
        this.root_path = root_path;
    }

    /**
     * Opens `path`, as a preview tab or a permanent one, reusing an
     * existing tab if already open. A permanent open also moves keyboard
     * focus into the editor — it means "I want to edit this now" (a
     * double-click, or a just-created file), unlike a preview (a single
     * click while browsing), which deliberately leaves focus in the
     * sidebar so arrow keys keep moving through the tree.
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
            editor_view.grab_focus ();
        }
    }

    /**
     * Opens a brand-new, not-yet-saved-anywhere tab named "Untitled-N" —
     * a permanent tab (not preview), focused immediately, same as any
     * other deliberately-opened file. Saving it (see save_path()) goes
     * through the Save As flow regardless of whether "Save" or "Save as…"
     * is what's actually clicked, since there's nowhere on disk yet for
     * a plain Save to write to.
     */
    public void new_untitled () {
        untitled_counter++;
        var name = "Untitled-%d".printf (untitled_counter);

        var document = Document.untitled (name);
        documents[name] = document;
        tab_bar_view.add_tab (name, name, "", false);
        if (documents.size () == 1) {
            has_open_tabs_changed (true);
        }
        activate (name);
        editor_view.grab_focus ();
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

    /** Whether `path` is currently open as a tab with unsaved changes — MainController checks this before letting the sidebar's Delete through without asking first. */
    public bool is_dirty (string path) {
        var document = documents[path];
        return document != null && document.dirty;
    }

    /** Every currently open tab's path — Opus.Dev.DevServer's own ListOpenTabs, no UI caller today. */
    public string[] open_paths () {
        string[] paths = {};
        foreach (var path in documents.get_keys ()) {
            paths += path;
        }
        return paths;
    }

    /** The active tab's path, or null if none — same value active_state_changed's own last emission carried, just readable directly instead of having to have been listening for it. */
    public string? active_document_path {
        get { return active_path; }
    }

    /** The active document's current buffer content, or "" if none — Opus.Dev.DevServer's own GetActiveText, the reverse of set_active_content(). */
    public string active_content {
        get { return active_path == null ? "" : documents[active_path].content; }
    }

    /**
     * Replaces the active document's content wholesale, as if the user
     * had retyped the whole buffer — Opus.Dev.DevServer's own
     * SetActiveText, no UI caller today (a person editing for real goes
     * through on_text_changed() instead, reached from the buffer's own
     * `changed` signal, not this). Unlike on_text_changed(), this also
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
        editor_view.set_text (text, active_path);
        tab_bar_view.mark_modified (document.path, document.dirty);
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
        var cursors = new Cursor[anchors.length];
        for (int i = 0; i < anchors.length; i++) {
            var cursor = new Cursor (anchors[i]);
            cursor.position_offset = positions[i];
            cursors[i] = cursor;
        }

        document.cursors.set_cursors (cursors);
        editor_view.render_cursors (document.cursors.snapshot ());
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

        var cursors = documents[active_path].cursors.snapshot ();
        anchors = new int[cursors.length];
        positions = new int[cursors.length];
        for (int i = 0; i < cursors.length; i++) {
            anchors[i] = cursors[i].anchor_offset;
            positions[i] = cursors[i].position_offset;
        }
    }

    /**
     * Applies `edits` as one atomic, non-coalescing history step — none
     * of them produced by any live cursor, unlike every other edit path
     * in this controller (which all go through CursorController
     * instead): the real buffer transaction (EditorView.apply_edits(),
     * already one GTK transaction), every cursor shifted to stay at its
     * own logical position (CursorCollection.shift_for_external_edits(),
     * never collapsed onto any of `edits`), and one EditHistory.push()
     * (EditKind.OTHER — never coalesces, so this is always its own undo
     * step). SearchController's own Replace/Replace All; nothing about
     * this is search-specific, so any future non-cursor-driven bulk edit
     * can reuse it too. A no-op with no active tab, or an empty `edits`.
     */
    public void apply_external_edits (TextEdit[] edits) {
        if (active_path == null || edits.length == 0) {
            return;
        }

        var document = documents[active_path];
        var before_cursors = document.cursors.snapshot ();

        editor_view.apply_edits (edits);
        document.cursors.shift_for_external_edits (edits);

        document.history.push (edits, before_cursors, document.cursors.snapshot (), EditKind.OTHER);
        editor_view.render_cursors (document.cursors.snapshot ());
    }

    /**
     * Simulates one keystroke exactly as a real EventControllerKey would
     * report it, driving the same CursorController dispatch a genuine
     * keypress triggers — Opus.Dev.DevServer's own KeyPress, for the
     * system-test DSL. `modifier_state` is a raw `Gdk.ModifierType`
     * bitmask, kept as a plain `uint` here since this controller never
     * imports Gdk itself (see EditorView.simulate_key_press(), which
     * does the actual cast). Returns whether something claimed the key,
     * same as the real signal.
     */
    public bool simulate_key_press (uint keyval, uint modifier_state) {
        return editor_view.simulate_key_press (keyval, modifier_state);
    }

    /** Fires GtkTextView's own native "select-all" (Ctrl+A) action directly — Opus.Dev.DevServer's own SelectAll, for the system-test DSL. See EditorView.simulate_select_all()'s own doc comment for why this reaches GTK's real handling without a raw keystroke. */
    public void simulate_select_all () {
        editor_view.simulate_select_all ();
    }

    /** Closes `path`'s tab outright, no unsaved-changes prompt — for when the file itself is already gone (deleted from the sidebar) and there's nothing left to save it to. No-op if `path` isn't open. */
    public void discard_tab (string path) {
        if (documents.contains (path)) {
            finish_close (path);
        }
    }

    /**
     * `old_path` moved to `new_path` on disk (a sidebar Rename, or a
     * Cut+Paste — menu or drag — actually moving rather than copying),
     * per FileTreeController's own file_moved. Only ever matches a path
     * that was directly opened as its own tab — a moved *directory*'s
     * path is never itself a documents key (only files ever are), so this
     * is a plain no-op for one, same as for any other moved path with no
     * open tab of its own: a tab open on a file *nested inside* a moved
     * directory still ends up "Deleted", exactly like it was moved
     * outside Opus — an acceptable, unsurprising outcome, not one this
     * bothers chasing down and re-pointing.
     */
    public void file_moved (string old_path, string new_path) {
        var document = documents[old_path];
        if (document == null) {
            return;
        }

        stop_watching_file (old_path);
        document.move_to (new_path);
        documents.remove (old_path);
        documents[new_path] = document;
        start_watching_file (new_path);

        tab_bar_view.rename_tab (old_path, new_path, Path.get_basename (new_path), folder_name_of (new_path));

        if (active_path == old_path) {
            active_path = new_path;
        }
        notify_active_state ();
    }

    /** Cancels every open tab's file watch — call before discarding this controller (the window closing), same reasoning as FileTreeController's own close(): an active Gio.FileMonitor's own IO source could otherwise keep this object alive indefinitely via its connected signal handler's closure. */
    public void close () {
        foreach (var monitor in file_watches.get_values ()) {
            monitor.cancel ();
        }
        file_watches.remove_all ();
    }

    private void open_preview (string path) throws Error {
        var existing_preview = find_preview ();
        if (existing_preview != null) {
            tab_bar_view.remove_tab (existing_preview.path);
            documents.remove (existing_preview.path);
            stop_watching_file (existing_preview.path);
        }

        var document = Document.load (path);
        document.is_preview = true;
        documents[path] = document;
        tab_bar_view.add_tab (path, Path.get_basename (path), folder_name_of (path), true);
        start_watching_file (path);
        if (documents.size () == 1) {
            has_open_tabs_changed (true);
        }
        activate (path);
    }

    private void open_permanent (string path) throws Error {
        var document = Document.load (path);
        document.is_preview = false;
        documents[path] = document;
        tab_bar_view.add_tab (path, Path.get_basename (path), folder_name_of (path), false);
        start_watching_file (path);
        if (documents.size () == 1) {
            has_open_tabs_changed (true);
        }
        activate (path);
    }

    /**
     * Watches `path` itself (not its containing directory) for it being
     * deleted or moved away outside Opus — unlike FileTreeController's
     * own directory watching (sidebar-tree only, and only for expanded
     * directories), a tab needs to know regardless of whether any folder
     * is even linked, or whether its own directory happens to be
     * expanded in the tree right now. Untitled documents never call this
     * — there's nothing on disk yet to watch.
     */
    private void start_watching_file (string path) {
        try {
            var monitor = File.new_for_path (path).monitor_file (FileMonitorFlags.WATCH_MOVES, null);
            monitor.changed.connect ((file, other_file, event_type) => on_file_changed (path, other_file, event_type));
            file_watches[path] = monitor;
        } catch (Error e) {
            warning ("failed to watch %s: %s", path, e.message);
        }
    }

    private void stop_watching_file (string path) {
        var monitor = file_watches[path];
        if (monitor == null) {
            return;
        }
        monitor.cancel ();
        file_watches.remove (path);
        own_writes.remove (path);
    }

    /**
     * `path` itself was deleted, or came back. A plain direct write shows
     * up as CREATED, but the common "write a temp file, then rename it
     * into place" pattern most tools (including Document.save() itself)
     * actually use — confirmed directly, not assumed: a real recreate at
     * the same path came back as RENAMED with `other_file` pointing at
     * this exact path, not CREATED — shows up as RENAMED instead, so
     * both need checking to mean "it's back".
     *
     * Always just marks the tab deleted (dirty or not) — it never closes
     * anything on its own. Whether *closing* the tab by hand afterwards
     * (X/Ctrl+W) then asks for confirmation is already exactly
     * document.dirty's own job in close_tab(), completely unaffected by
     * is_deleted — nothing extra needed here for that.
     *
     * A RENAMED-onto-`path` event is ambiguous on its own: confirmed
     * directly (not assumed) that FileUtils.set_contents — and most other
     * editors' own "save", GNOME Text Editor's own EditorBufferMonitor
     * included — always writes through a temp-file-then-atomic-rename,
     * so a plain in-place resave by another program looks identical at
     * the GIO level to a delete-then-recreate. Disambiguated by whether
     * this document was already known deleted: if it was, the file just
     * came back (mark not-deleted); if it wasn't, it was never gone —
     * someone else just changed its content (the "File Has Changed on
     * Disk" banner). A plain CHANGED (no rename — e.g. `>>` shell
     * appends, or `dd`) is unambiguous and always means the latter.
     */
    private void on_file_changed (string path, File? other_file, FileMonitorEvent event_type) {
        var document = documents[path];
        if (document == null) {
            return;
        }

        if (own_writes.remove (path)) {
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
                if (other_file == null || other_file.get_path () != path) {
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
     * sticky "unsynchronized" state, not just a one-off reaction to this
     * particular event: once set, `document` stays unsynchronized
     * through *any* number of further external changes, no matter what
     * dirty happens to be at the time of each one — only resolved by an
     * explicit choice (Discard and Reload, or a Save that overwrites
     * disk with this tab's own content), never by silently landing back
     * in a clean state along the way (e.g. Ctrl+Z undoing back to the
     * original content) or by dismissing the banner's own close button
     * (that only hides it, see EditorView — the state underneath is
     * unaffected). First found live, not assumed: a *second* external
     * edit while already unsynchronized re-ran this same dirty check
     * fresh, and — since the tab had gone clean again via Ctrl+Z in the
     * meantime — silently reloaded it right out from under the pending,
     * still-unresolved conflict the banner was already showing.
     *
     * Only on the *first* transition into this state does dirty actually
     * matter: a clean tab has nothing of its own at stake, so it's just
     * silently reloaded instead of ever becoming unsynchronized at all;
     * a dirty one shows the banner (if `path` is the active tab; a
     * background one just remembers the flag on its Document until it's
     * activated or reloaded — see show_in_editor).
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
        tab_bar_view.mark_unsynchronized (path, true);
        if (path == active_path) {
            editor_view.set_change_banner_visible (true);
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

    /** Discards `document`'s in-memory content in favor of what's on disk right now — shared by the explicit "Discard Changes and Reload" action and the automatic silent reload for a clean tab. Only touches the editor buffer itself if `path` is the active tab; the tab pill's own state (modified/deleted) updates either way. */
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
        tab_bar_view.mark_modified (path, document.dirty);
        tab_bar_view.mark_deleted (path, false);
        tab_bar_view.mark_unsynchronized (path, false);
        notify_active_state ();
    }

    private void mark_file_deleted (string path, Document document, bool deleted) {
        if (document.is_deleted == deleted) {
            return;
        }

        document.is_deleted = deleted;
        tab_bar_view.mark_deleted (path, deleted);
        tab_bar_view.mark_modified (path, document.dirty);
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
        tab_bar_view.set_active (path);
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
            editor_view.set_text (document.content, path);
            editor_view.clear_placeholder ();
        } else {
            editor_view.set_placeholder (_("This file can't be displayed."));
        }
        editor_view.set_change_banner_visible (document.is_externally_modified);
        cursor_controller.set_active_document (document);
    }

    private void promote (Document document) {
        document.is_preview = false;
        tab_bar_view.mark_preview (document.path, false);
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
        tab_bar_view.mark_modified (document.path, document.dirty);
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

        var choice = yield tab_bar_view.confirm_unsaved_close (Path.get_basename (path));
        switch (choice) {
            case DiscardChoice.SAVE:
                // An untitled document has nowhere to plain-save() to —
                // save_as_path() prompts for one and, on success, re-keys
                // it to the real path it renamed the tab to, which is
                // what actually needs closing now, not the old key.
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

    /** Returns whether the document is clean afterwards (i.e. the save, if attempted, succeeded). */
    /**
     * A clean, synchronized document has nothing to write — but "clean"
     * alone isn't enough to skip this: a document can be clean and still
     * unsynchronized at once (its own content matches original_content,
     * which is itself stale against what's actually on disk right now —
     * e.g. Ctrl+Z undoing back to a clean state while the "File Has
     * Changed on Disk" banner is still up). Save is one of the two ways
     * that's meant to resolve — writing this tab's own content back to
     * disk either way — so it has to actually run even then, not just
     * when dirty happens to be true (found live: Ctrl+S silently doing
     * nothing in exactly that state).
     */
    private bool save_document (Document? document) {
        if (document == null || (!document.dirty && !document.is_externally_modified)) {
            return true;
        }

        own_writes[document.path] = true;
        try {
            document.save ();
        } catch (Error e) {
            own_writes.remove (document.path); // never wrote, so no event will ever come consume it
            warning ("failed to save %s: %s", document.path, e.message);
            return false;
        }

        tab_bar_view.mark_modified (document.path, document.dirty);
        tab_bar_view.mark_deleted (document.path, document.is_deleted); // save() already reset this to false
        tab_bar_view.mark_unsynchronized (document.path, false); // same — save() already reset is_externally_modified too
        if (document.path == active_path) {
            editor_view.set_change_banner_visible (false);
        }
        notify_active_state ();
        return true;
    }

    private void finish_close (string path) {
        stop_watching_file (path);
        tab_bar_view.remove_tab (path);
        documents.remove (path);

        if (active_path == path) {
            // Prefer another still-open tab over going empty — the
            // rightmost one, for now (see last_tab_path()'s own doc
            // comment for the MRU-stack alternative this deliberately
            // isn't yet).
            var fallback = tab_bar_view.last_tab_path ();
            if (fallback != null) {
                activate (fallback);
            } else {
                active_path = null;
                editor_view.set_text ("", path);
                editor_view.set_change_banner_visible (false);
                cursor_controller.set_active_document (null);
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
     * Closes each of `paths` in turn — one at a time, not concurrently, so
     * an unsaved-changes prompt for one tab never overlaps another's.
     * `owned`, not borrowed: without it, `paths` here is only valid for
     * the synchronous part of the call — the caller's own local array is
     * freed once close_others()/close_all() returns, which happens before
     * this coroutine ever resumes from its first yield (confirmed via a
     * real segfault, reading a freed string on the second tab closed —
     * not assumed up front).
     */
    private async void close_paths (owned string[] paths) {
        foreach (var path in paths) {
            yield close_tab (path);
        }
    }

    /** A plain Save on `path` specifically, not necessarily the active tab — except for an untitled document, which has nowhere to write to yet and goes through the Save As flow instead, same as the user asked: "the same little Save As window, since it doesn't exist anywhere". Public for Opus.Dev.DevServer's own SaveTab, which addresses a tab by path — the UI itself only ever reaches this through save_active()/save_as_active(), always on whichever tab is active. */
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
     * Save As: asks EditorView for a destination via the system's own file
     * chooser (an untitled document defaults to the workspace root, since
     * its own synthetic "path" has no real directory to default to),
     * writes the document there, and re-keys both the document (documents
     * is keyed by path) and its tab (TabBarView.rename_tab) to the new
     * path — same pill, same position, just now pointing somewhere else,
     * the way any editor's Save As leaves you editing the new file
     * afterwards, not the old one. Also promotes a preview tab: a
     * deliberately-saved-elsewhere file isn't "just previewing" anything
     * anymore. Returns the new path on success, or null if cancelled or
     * the write itself failed — close_tab()'s own Save choice needs to
     * know which tab to actually close afterwards.
     */
    private async string? save_as_path (string path) {
        var document = documents[path];
        if (document == null) {
            return null;
        }

        var initial_folder = document.is_untitled ? root_path : Path.get_dirname (path);
        var new_path = yield editor_view.choose_save_as_path (Path.get_basename (path), initial_folder);
        if (new_path == null) {
            return null;
        }

        own_writes[new_path] = true;
        try {
            document.save_as (new_path);
        } catch (Error e) {
            own_writes.remove (new_path); // never wrote, so no event will ever come consume it
            warning ("failed to save %s: %s", new_path, e.message);
            return null;
        }

        documents.remove (path);
        documents[new_path] = document;
        stop_watching_file (path);
        start_watching_file (new_path);
        bool was_active = active_path == path;
        if (was_active) {
            active_path = new_path;
        }

        tab_bar_view.rename_tab (path, new_path, Path.get_basename (new_path), folder_name_of (new_path));
        tab_bar_view.mark_modified (new_path, false);
        tab_bar_view.mark_deleted (new_path, false);
        tab_bar_view.mark_unsynchronized (new_path, false); // save_as() already reset is_externally_modified too
        if (was_active) {
            editor_view.set_change_banner_visible (false);
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
