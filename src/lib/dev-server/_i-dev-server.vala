namespace Opus.Dev {
  /**
   * The actual D-Bus wire contract — kept separate from DevServer itself
   * because Vala's GDBus codegen treats every public method of a
   * `[DBus (name = ...)]`-annotated *class* as a D-Bus method. DevServer
   * has real public methods that take plain GTK objects
   * (`EditorView.EditorPane` in add_session()/remove_session(),
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
  [DBus (name = "io.github.nowaos.Opus.Dev")]
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
     * such label at all). EditorPane.save_path()'s own synchronous
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
  }
}
