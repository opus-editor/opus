/**
 * Owns the open {@link Document}s and mediates between the tab bar and the
 * editor pane: opening files (as preview or permanent tabs), promoting a
 * preview tab on edit or double-click, tracking dirty state, saving, and the
 * close-with-unsaved-changes flow.
 */
public class EditorController : Object {
    private TabBarView tab_bar_view;
    private EditorView editor_view;

    private HashTable<string, Document> documents = new HashTable<string, Document> (str_hash, str_equal);
    private string? active_path = null;

    public EditorController (TabBarView tab_bar_view, EditorView editor_view) {
        this.tab_bar_view = tab_bar_view;
        this.editor_view = editor_view;

        editor_view.text_changed.connect (on_text_changed);
        tab_bar_view.tab_selected.connect (on_tab_selected);
        tab_bar_view.tab_double_clicked.connect (on_tab_double_clicked);
        tab_bar_view.tab_close_requested.connect ((path) => close_tab.begin (path));
    }

    /** Opens `path`, as a preview tab or a permanent one, reusing an existing tab if already open. */
    public void open (string path, bool as_permanent) throws Error {
        if (documents.contains (path)) {
            if (as_permanent) {
                promote (documents[path]);
            }
            activate (path);
            return;
        }

        if (as_permanent) {
            open_permanent (path);
        } else {
            open_preview (path);
        }
    }

    /** Saves the active document, if any and if dirty. */
    public void save_active () {
        if (active_path == null) {
            return;
        }

        save_document (documents[active_path]);
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
        tab_bar_view.add_tab (path, Path.get_basename (path), true);
        activate (path);
    }

    private void open_permanent (string path) throws Error {
        var document = Document.load (path);
        document.is_preview = false;
        documents[path] = document;
        tab_bar_view.add_tab (path, Path.get_basename (path), false);
        activate (path);
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
    }

    private void show_in_editor (string path) {
        var document = documents[path];
        if (document.readable) {
            editor_view.set_text (document.content);
            editor_view.clear_placeholder ();
        } else {
            editor_view.set_placeholder (_("This file can't be displayed."));
        }
    }

    private void promote (Document document) {
        document.is_preview = false;
        tab_bar_view.mark_preview (document.path, false);
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
    }

    private void on_tab_selected (string path) {
        active_path = path;
        show_in_editor (path);
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
                if (save_document (document)) {
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
        return true;
    }

    private void finish_close (string path) {
        tab_bar_view.remove_tab (path);
        documents.remove (path);

        if (active_path == path) {
            active_path = null;
            editor_view.set_text ("");
        }
    }
}
