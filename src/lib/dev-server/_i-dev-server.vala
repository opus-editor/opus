namespace Opus.Dev {
  /**
   * The actual D-Bus wire contract — kept separate from DevServer itself
   * because Vala's GDBus codegen treats every public method of a
   * `[DBus (name = ...)]`-annotated *class* as a D-Bus method. DevServer
   * has real public methods that take plain GTK objects
   * (`EditorView.EditorPaneWidget` in add_session()/remove_session(),
   * `DBusConnection` in start()) — none of those are GVariant-marshalable,
   * so annotating DevServer directly fails to compile the moment it has
   * any such method (confirmed directly: a minimal `[DBus]`-annotated
   * class with one plain-Object-typed method parameter fails with
   * "GVariant deserialization of type `X' is not supported"). Declaring
   * the wire contract on this interface instead, and registering
   * `(IDevServer) this` in DevServer.start(), scopes the D-Bus surface
   * to exactly these methods — every parameter/return type here is a
   * GVariant-safe primitive on purpose.
   */
  [DBus (name = "io.github.opus_editor.Opus.Dev")]
  public interface IDevServer : Object {
    /** Opens a brand-new "Untitled-N" tab, focused immediately — same as the sidebar's "New File". */
    public abstract void new_file () throws DBusError, IOError;

    /** Opens `path` as a permanent tab — same as a double-click. Already-open just activates it, same as clicking its tab. */
    public abstract void open_tab (string path) throws DBusError, IOError;

    /** Closes `path`'s tab outright, no unsaved-changes prompt (same as discard_tab()) — a dev tool has no dialog to answer. */
    public abstract void close_tab (string path) throws DBusError, IOError;

    /**
     * Saves `path` specifically, regardless of which tab is active.
     * Not `async`: valac's own GDBus codegen for an async interface
     * method's dispatch stub always emits an `_error:` label nothing
     * in that function ever jumps to (real async errors surface in
     * the ready callback instead) — an unconditional, unfixable
     * warning for *any* async D-Bus method, not particular to this
     * one (confirmed directly: a bare synchronous method generates no
     * such label at all). EditorView.EditorPane.TabDocument.save_path()'s own synchronous
     * case (an already-named file, the common one) has no yield point
     * in it at all, so it still runs to completion before this returns
     * either way; only the rare untitled-document case (needing a
     * save-as dialog) becomes genuinely fire-and-forget.
     */
    public abstract void save_tab (string path) throws DBusError, IOError;

    /** Replaces the active tab's entire buffer content — simulates a real edit (dirty tracking and all), just not through a real keypress. */
    public abstract void set_active_text (string text) throws DBusError, IOError;

    /** Replaces the active tab's cursor set — `anchors[i]`/`positions[i]` pair up into one cursor each (collapsed when equal). Lets a system test seed a multi-cursor starting state directly, without typing/clicking it into place first. */
    public abstract void set_active_cursors (int[] anchors, int[] positions) throws DBusError, IOError;

    /** The syntax style key painted at character `offset` of the active tab ("keyword", "string", …), or "" where nothing is. */
    public abstract string syntax_style_at (int offset) throws DBusError, IOError;

    /** The active tab's current buffer content, or "" if none — the reverse of set_active_text(). */
    public abstract string get_active_text () throws DBusError, IOError;

    /** The active tab's current cursor set, or two empty arrays if none — the reverse of set_active_cursors(). */
    public abstract void get_active_cursors (out int[] anchors, out int[] positions) throws DBusError, IOError;

    /**
     * Dispatches one keystroke on the active tab exactly as a real one
     * would be reported (same keyval/modifier shape as Gdk, e.g.
     * `Gdk.ModifierType.CONTROL_MASK` for Ctrl) — driving the real
     * CodeEditorCursors dispatch, not a shortcut around it. Returns
     * whether anything claimed the key. The system-test DSL's `type`/
     * `type_cmd` both resolve to this: `type` looks up each
     * character's own keyval and calls this once per character;
     * `type_cmd` resolves a named command (e.g. "undo") to its
     * keyval + modifiers the same way a real Ctrl+Z would arrive.
     */
    public abstract bool key_press (uint keyval, uint modifiers) throws DBusError, IOError;

    /**
     * Fires GtkTextView's own native "select-all" (Ctrl+A) action on
     * the active tab directly — the system-test DSL's `select_all`.
     * Not routed through key_press(): unlike an ordinary keystroke,
     * "select-all" is a GTK keybinding-action signal, reachable
     * (and faithfully exercised) without needing a real GTK event
     * at all — see CodeEditor.select_all()'s own doc
     * comment for why.
     */
    public abstract void select_all () throws DBusError, IOError;

    /** Every currently open tab's path, across whichever window this call happens to land on (see current_editor_pane()'s own comment). */
    public abstract string[] list_open_tabs () throws DBusError, IOError;

    /** The active tab's path, or "" if none is. */
    public abstract string get_active_tab () throws DBusError, IOError;

    public abstract bool is_dirty (string path) throws DBusError, IOError;

    /** Sets the active tab's live Find search text — same as typing into FindBar's own entry, minus the widget. "" clears the search, same as an empty Find entry. */
    public abstract void search_set_text (string text) throws DBusError, IOError;

    /** Sets the active tab's Regular Expressions/Case Sensitive/Match Whole Word Only search options — same as FindBar's own three toggle buttons. */
    public abstract void search_set_options (bool regex, bool case_sensitive, bool whole_word) throws DBusError, IOError;

    /** Next Match — same as FindBar's own move_next_button/plain Return. */
    public abstract void search_next () throws DBusError, IOError;

    /** Previous Match — same as FindBar's own move_previous_button/Shift+Return. */
    public abstract void search_previous () throws DBusError, IOError;

    /** The live search's current (position, count) as of the last search_position_changed — the same numbers FindBar's own "N of M" counter would show. Both 0 with no active search/no matches. */
    public abstract void search_get_position (out int position, out int count) throws DBusError, IOError;

    /** Find in Files for `text` across the linked folder, with FindInFilesBar's own toggles all off — opens (or refreshes) the "Find Results" tab, same as its Return key. The search itself is async; the tab appears once it finishes. */
    public abstract void find_in_files (string text) throws DBusError, IOError;

    /** The 1-based first line showing in the editor. */
    public abstract int get_top_line () throws DBusError, IOError;

    /** Whether the active editor wraps lines right now (its own Alt+W override, else editor.word_wrap). */
    public abstract bool get_word_wrap () throws DBusError, IOError;

    /** A single click in the explorer — opens `path` as a preview tab, the one that the next preview replaces. */
    public abstract void open_preview_tab (string path) throws DBusError, IOError;

    /** How many document tabs exist in memory, open or not yet taken apart — a closed tab that lingers shows here. */
    public abstract int get_live_tabs () throws DBusError, IOError;

    /** Closes the window the way its close button does — the session is saved, and the process ends with its last window. */
    public abstract void close_window () throws DBusError, IOError;

    /** Ctrl+Shift+T — reopens the latest closed file tab, cursor where it was. */
    public abstract void reopen_closed_tab () throws DBusError, IOError;

    /** Ctrl+P — opens the Command Bar, folder linked or not. */
    public abstract void open_command_bar () throws DBusError, IOError;

    /** Opens the Command Bar on its `>` list of commands — same as Ctrl+Shift+P, and like it needs no folder. */
    public abstract void open_commands () throws DBusError, IOError;

    /** Replaces the open Command Bar's entry text — the same path a real keystroke takes, through the entry's own `changed`. */
    public abstract void command_bar_set_text (string text) throws DBusError, IOError;

    /** Return in the Command Bar — accepts the row under the cursor. */
    public abstract void command_bar_accept () throws DBusError, IOError;

    /** Escape in the Command Bar — closes it, accepting nothing. */
    public abstract void command_bar_close () throws DBusError, IOError;

    /** What the Command Bar says in place of rows when it has none — "" while it isn't open. */
    public abstract string command_bar_empty_message () throws DBusError, IOError;

    /** The 1-based line the editor is previewing for the Command Bar's `#` list, 0 when none. */
    public abstract int get_previewed_line () throws DBusError, IOError;

    /** Every row the Command Bar currently shows, top to bottom, as what accepting each would resolve to (a file's path). Empty while it isn't open, or while its file walk hasn't answered yet — poll. */
    public abstract string[] command_bar_list_items () throws DBusError, IOError;

    /** The header switcher's "Git" page — GitView.StagingPane in the sidebar. */
    public abstract void show_git_view () throws DBusError, IOError;

    /** StagingPane's rows in `section` ("conflicts"/"unstaged"/"staged"), each "<code> <relative path>". */
    public abstract string[] git_list_changes (string section) throws DBusError, IOError;

    public abstract void git_stage_all () throws DBusError, IOError;

    public abstract void git_unstage_all () throws DBusError, IOError;

    /** Unstaged's own "Discard all changes" — opens its confirmation, see respond_to_dialog(). */
    public abstract void git_discard_all () throws DBusError, IOError;

    /** A double-click on `path`'s row in `section` — stage, unstage, or (conflicts) stage with its questions. */
    public abstract void git_activate_row (string section, string path) throws DBusError, IOError;

    public abstract void git_accept_current (string path) throws DBusError, IOError;

    public abstract void git_accept_incoming (string path) throws DBusError, IOError;

    /** The commit button's own text — "Commit to main", "Merge", "Continue". */
    public abstract string git_commit_label () throws DBusError, IOError;

    /** "none", or the parked operation: "merge", "rebase", "cherry-pick", "revert". */
    public abstract string git_operation () throws DBusError, IOError;

    public abstract bool git_commit_enabled () throws DBusError, IOError;

    public abstract void git_set_commit_message (string text) throws DBusError, IOError;

    public abstract string git_commit_message () throws DBusError, IOError;

    /** The commit button — a commit, the merge commit, or the parked operation's own continue. */
    public abstract void git_commit () throws DBusError, IOError;

    /** The Abort button — opens its confirmation, see respond_to_dialog(). */
    public abstract void git_abort () throws DBusError, IOError;

    /** The last failure toast's own summary, "" until one happened. */
    public abstract string git_last_failure () throws DBusError, IOError;

    /** GitView.TreePane's rows, top to bottom, each "<kind>|<lane>|<refs>|<text>|<hash>" (see TreePane.describe_rows()). */
    public abstract string[] git_tree_rows () throws DBusError, IOError;

    public abstract void git_tree_select (string hash_prefix) throws DBusError, IOError;

    /** The selected commit's short hash, "" with none. */
    public abstract string git_tree_selected () throws DBusError, IOError;

    public abstract int git_tree_loaded () throws DBusError, IOError;

    /** What scrolling the tree to its bottom does: the next page. */
    public abstract void git_tree_load_more () throws DBusError, IOError;

    public abstract void git_tree_select_wip () throws DBusError, IOError;

    /** Which pane the Git sidebar shows: "staging" or "history". */
    public abstract string git_sidebar_pane () throws DBusError, IOError;

    /** HistoryPane's header line, e.g. "Commit: 1a2b3c4". */
    public abstract string git_history_header () throws DBusError, IOError;

    /** HistoryPane's files, each "<code> <relative path>". */
    public abstract string[] git_history_files () throws DBusError, IOError;

    /** HistoryPane's close button. */
    public abstract void git_history_back () throws DBusError, IOError;

    /** A single click on `path`'s row in StagingPane's `section` ("unstaged"/"staged"/"conflicts"): selects it alone, which opens its diff or file. */
    public abstract void git_select_row (string section, string path) throws DBusError, IOError;

    /** A double-click on `path` in HistoryPane's file list: that file's diff in the commit. */
    public abstract void git_history_open_file (string path) throws DBusError, IOError;

    /** What the Git view's main area shows: "tree" or "diff". */
    public abstract string git_content_showing () throws DBusError, IOError;

    /** The breadcrumb over it: "History", or "History / <commit or WIP> / <file>". */
    public abstract string git_breadcrumb () throws DBusError, IOError;

    /** The breadcrumb's "History": back to the tree. */
    public abstract void git_show_tree () throws DBusError, IOError;

    /** The diff on screen, each line "<old>|<new>|<marker>|<text>"; empty while a placeholder shows or no diff is open. */
    public abstract string[] git_diff_lines () throws DBusError, IOError;

    /** How the diff area shows the file: "diff", "plain" (one side only) or "placeholder". */
    public abstract string git_diff_mode () throws DBusError, IOError;

    /** The diff placeholder's title ("Binary file", …), "" while a real diff shows. */
    public abstract string git_diff_placeholder () throws DBusError, IOError;

    /** Every conflicted file opened in the editor — StagingPane.solve_all(). */
    public abstract void git_solve_all () throws DBusError, IOError;

    /** The header switcher's current page: "editor" or "git". */
    public abstract string current_view () throws DBusError, IOError;

    /** How many merge-conflict blocks the active document tab's text holds. */
    public abstract int conflict_count () throws DBusError, IOError;

    /** One of conflict block `index`'s own links in the active document tab: `side` is "current", "incoming", "both" (current then incoming) or "both-incoming-first". */
    public abstract void accept_conflict (int index, string side) throws DBusError, IOError;

    /** The heading of whichever Dialogs dialog is showing, "" with none. */
    public abstract string dialog_heading () throws DBusError, IOError;

    /** Clicks the showing dialog's `response_id` button ("cancel"/"confirm"/"first"/"second"/"ok"). */
    public abstract void respond_to_dialog (string response_id) throws DBusError, IOError;
  }
}
