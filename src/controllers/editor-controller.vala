/**
 * Owns the open {@link Document}s and mediates between the tab bar and the
 * editor pane: opening files (as preview or permanent tabs), promoting a
 * preview tab on edit or double-click, tracking dirty state, saving, and the
 * close-with-unsaved-changes flow.
 */
public class EditorController : Object {
    private TabBarView tab_bar_view;
    private EditorView editor_view;
    private string root_path;

    private HashTable<string, Document> documents = new HashTable<string, Document> (str_hash, str_equal);
    private string? active_path = null;
    private int untitled_counter = 0;

    /** Whether at least one tab is open — whoever hosts the editor's widget uses this to hide it (an empty-state placeholder instead) when it's not. */
    public signal void has_open_tabs_changed (bool has_tabs);

    /** The active tab, or its dirty state, changed — null `path` means no tab is active (`dirty` is meaningless then). Drives the primary menu's Save/Save as… group (see MainWindowView.set_active_state); Save/Save as… now live only there and on Ctrl+S/Ctrl+Shift+S, not per-tab in the tab bar's own context menu. */
    public signal void active_state_changed (string? path, bool dirty);

    public EditorController (TabBarView tab_bar_view, EditorView editor_view, string root_path) {
        this.tab_bar_view = tab_bar_view;
        this.editor_view = editor_view;
        this.root_path = root_path;

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

    /** Closes `path`'s tab outright, no unsaved-changes prompt — for when the file itself is already gone (deleted from the sidebar) and there's nothing left to save it to. No-op if `path` isn't open. */
    public void discard_tab (string path) {
        if (documents.contains (path)) {
            finish_close (path);
        }
    }

    private void open_preview (string path) throws Error {
        var existing_preview = find_preview ();
        if (existing_preview != null) {
            tab_bar_view.remove_tab (existing_preview.path);
            documents.remove (existing_preview.path);
        }

        var document = Document.load (path);
        document.is_preview = true;
        documents[path] = document;
        tab_bar_view.add_tab (path, Path.get_basename (path), folder_name_of (path), true);
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
        if (documents.size () == 1) {
            has_open_tabs_changed (true);
        }
        activate (path);
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
    private bool save_document (Document? document) {
        if (document == null || !document.dirty) {
            return true;
        }

        try {
            document.save ();
        } catch (Error e) {
            warning ("failed to save %s: %s", document.path, e.message);
            return false;
        }

        tab_bar_view.mark_modified (document.path, document.dirty);
        notify_active_state ();
        return true;
    }

    private void finish_close (string path) {
        tab_bar_view.remove_tab (path);
        documents.remove (path);

        if (active_path == path) {
            active_path = null;
            editor_view.set_text ("", path);
            notify_active_state ();
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

    /** A plain Save — except for an untitled document, which has nowhere to write to yet and goes through the Save As flow instead, same as the user asked: "the same little Save As window, since it doesn't exist anywhere". */
    private async void save_path (string path) {
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

        try {
            document.save_as (new_path);
        } catch (Error e) {
            warning ("failed to save %s: %s", new_path, e.message);
            return null;
        }

        documents.remove (path);
        documents[new_path] = document;
        if (active_path == path) {
            active_path = new_path;
        }

        tab_bar_view.rename_tab (path, new_path, Path.get_basename (new_path), folder_name_of (new_path));
        tab_bar_view.mark_modified (new_path, false);
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
