/**
 * Mediates EditorView.FindBar <-> EditorView.TextEditor for Find, and EditorView.FindBar <->
 * EditorController for Replace/Replace All: text and option changes
 * drive EditorView.TextEditor's own live search, Next/Previous move through its
 * matches, and the resulting position/count get reflected straight back
 * onto EditorView.FindBar's own "N of M" counter. Replace/Replace All build their
 * edits against EditorView.TextEditor (it owns the live match ranges/regex state)
 * but apply them through EditorController.apply_external_edits() — see
 * its own doc comment for why: none of Find/Replace's edits are
 * produced by a live cursor, so they can't go through CursorController
 * the way every other edit in this app does.
 */
public class SearchController : Object {
    private EditorView.FindBar search_bar;
    private EditorView.TextEditor editor_view;
    private EditorController editor_controller;

    // search_position_changed's own (position, count) doesn't say whether
    // count == 0 means "no search text" or "search text with zero
    // matches" — EditorView.FindBar's set_match_info() needs that distinction (see
    // its own doc comment), so it's tracked here from search_changed
    // directly instead.
    private bool has_search_text = false;

    public SearchController (EditorView.FindBar search_bar, EditorView.TextEditor editor_view, EditorController editor_controller) {
        this.search_bar = search_bar;
        this.editor_view = editor_view;
        this.editor_controller = editor_controller;

        search_bar.search_changed.connect (on_search_changed);
        search_bar.search_options_changed.connect (on_search_options_changed);
        search_bar.search_next_requested.connect (() => editor_view.search_next ());
        search_bar.search_previous_requested.connect (() => editor_view.search_previous ());
        search_bar.replace_requested.connect (on_replace_requested);
        search_bar.replace_all_requested.connect (on_replace_all_requested);
        search_bar.closed.connect (on_search_bar_closed);
        editor_view.search_position_changed.connect (on_search_position_changed);
    }

    /**
     * Ctrl+F — MainWindow's own find_requested, already gated there
     * on there being an open tab at all. Seeds the Find entry from the
     * editor's own current (primary) selection first, same as most
     * editors' own real Ctrl+F, but only when the editor genuinely had
     * focus at the moment it was pressed — read into `selected` before
     * show_find() below moves focus into the entry itself, so a second
     * Ctrl+F while the bar's already open (focus already in its entry,
     * mid-typing a query) leaves that query alone instead of clobbering
     * it with whatever the editor's own primary selection happens to be.
     *
     * set_find_text() itself still has to run *after* show_find(), not
     * before: Gtk.SearchBar's own real reveal_child_changed_cb (checked
     * gtksearchbar.c) clears its connected entry's text on every single
     * search-mode-enabled transition where that entry isn't itself a
     * Gtk.Entry/Gtk.SearchEntry — ours (SearchInput's plain
     * Gtk.Text, see its own doc comment for why) never is, so the
     * transition show_find() triggers would otherwise wipe out whatever
     * was set here first.
     */
    public void open_find () {
        bool has_selection_in_focus = editor_view.has_focus;
        string selected = has_selection_in_focus ? editor_view.primary_selection_text : "";

        search_bar.show_find ();

        if (selected != "") {
            search_bar.set_find_text (selected);
        }
    }

    /** "Replace" — replaces only the current match, then advances to the next one. A no-op if there's no current match right now. */
    private void on_replace_requested () {
        var edit = editor_view.compute_replace_current_match (search_bar.replace_text);
        if (edit == null) {
            return;
        }

        editor_controller.apply_external_edits ({ edit });
        editor_view.land_after_replace (edit.start_offset + edit.new_text.char_count ());
    }

    /** "Replace All" — replaces every live match as one undo step; the user's own cursor/selection just shifts to stay at its own logical position (see EditorController.apply_external_edits()). A no-op with no matches. */
    private void on_replace_all_requested () {
        var edits = editor_view.compute_replace_all (search_bar.replace_text);
        if (edits.length == 0) {
            return;
        }

        editor_controller.apply_external_edits (edits);
        editor_view.forget_current_match ();
    }

    private void on_search_changed (string text) {
        has_search_text = text != "";
        editor_view.set_search_text (text);
    }

    private void on_search_options_changed () {
        editor_view.set_search_options (
            search_bar.regex_enabled, search_bar.case_sensitive_enabled, search_bar.whole_word_enabled
        );
    }

    private void on_search_position_changed (int position, int count) {
        search_bar.set_match_info (position, count, has_search_text);
    }

    /**
     * select_last_match() only moves focus back into the editor when a
     * match was actually live-highlighted (see its own doc comment) — a
     * no-op close (bar opened, nothing searched/found, then dismissed)
     * left focus stuck whatever it was, typically still the bar's own
     * entry. Grabbing it here too covers that case as well, harmlessly
     * redundant with select_last_match()'s own grab in the case it
     * already handled. Gated on there still being an active tab: FindBar.
     * close() is also called directly when the last open tab closes
     * while the bar is still open (see its own doc comment) — nothing to
     * focus then.
     */
    private void on_search_bar_closed () {
        editor_view.select_last_match ();
        if (editor_controller.active_document_path != null) {
            editor_view.grab_focus ();
        }
    }
}
