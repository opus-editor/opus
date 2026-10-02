/**
 * Find-in-Files bar — duplicated from EditorView.FindBar as a starting
 * point (see that class's own doc comment for the mechanics this still
 * shares: Gtk.SearchBar/GtkSearchBar native behavior, why focus is
 * grabbed explicitly in show_find(), why set_find_text() must be
 * called after it). Find-only — Replace lives in the Find Results tab's
 * own header instead (EditorView.EditorPane.TabFindResults' own
 * replace_button), not here; Where is still always shown alongside
 * Find, matching VS Code's own real Find in Files panel. Wired into
 * MainWindow's own Ctrl+Shift+F; the doc comments below still describe
 * FindBar's own per-tab search scope, which doesn't apply here — this
 * bar's own cross-file search behavior isn't implemented yet.
 */
namespace EditorView {
  public class FindInFilesBar : Object, IGlobalPanel {
    private Gtk.SearchBar search_bar;
    private SearchInput search_input;
    private Gtk.ToggleButton regex_button;
    private Gtk.ToggleButton case_sensitive_button;
    private Gtk.ToggleButton whole_word_button;
    private Gtk.Button search_button;
    private Gtk.ToggleButton gitignore_button;
    private Gtk.Entry where_entry;
    private Gtk.Button add_folder_button;

    public Gtk.Widget widget { get { return search_bar; } }

    /** The Find entry's text changed — every keystroke, and once more (with "") on the bar's own native clear-on-close. */
    public signal void search_changed (string text);

    /** Regular Expressions/Case Sensitive/Match Whole Word Only — one of the three toggled. No argument: which one fired isn't itself meaningful, read the three *_enabled properties below for the current combination. */
    public signal void search_options_changed ();

    /** Shift+Return in the Find entry. */
    public signal void search_previous_requested ();

    /** Search clicked, or plain Return in the Find entry. */
    public signal void search_next_requested ();

    /** Alt+Return in the Find entry — matches VS Code's own "Select All Occurrences" (no dedicated button there either, same reasoning here: Previous/Next stay as the only two buttons, keyboard-only for this one). */
    public signal void select_all_requested ();

    /** "Add Folder…" clicked — MainWindow's own on_add_folder_requested() is what actually opens the folder chooser and validates the result (this bar has no root_path of its own to validate against), then calls append_where_patterns() back on success. */
    public signal void add_folder_requested ();

    /**
     * The bar just closed — Escape from anywhere in the window (via
     * IGlobalPanel, see its own doc comment), the native close button, or
     * close() called directly.
     */
    public signal void closed ();

    /** IGlobalPanel's own is_open — whether the bar is currently revealed. */
    public bool is_open { get { return search_bar.search_mode_enabled; } }

    public string search_text { get { return search_input.entry.text; } }
    public bool regex_enabled { get { return regex_button.active; } }
    public bool case_sensitive_enabled { get { return case_sensitive_button.active; } }
    public bool whole_word_enabled { get { return whole_word_button.active; } }
    public bool gitignore_enabled { get { return gitignore_button.active; } }
    public string where_text { get { return where_entry.text; } }

    public FindInFilesBar () {
      var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/editor-view/find-in-files-bar/index.ui");
      search_bar = (Gtk.SearchBar) builder.get_object ("search_bar");
      var search_grid = (Gtk.Grid) builder.get_object ("search_grid");
      regex_button = (Gtk.ToggleButton) builder.get_object ("regex_button");
      case_sensitive_button = (Gtk.ToggleButton) builder.get_object ("case_sensitive_button");
      whole_word_button = (Gtk.ToggleButton) builder.get_object ("whole_word_button");
      search_button = (Gtk.Button) builder.get_object ("search_button");
      gitignore_button = (Gtk.ToggleButton) builder.get_object ("gitignore_button");
      where_entry = (Gtk.Entry) builder.get_object ("where_entry");
      add_folder_button = (Gtk.Button) builder.get_object ("add_folder_button");

      // Built in code, not declared in the .blp — see FindBar's own
      // constructor for why (SearchInput isn't something Blueprint has
      // introspection data for); search_grid's (2, 0) cell is left empty
      // there specifically for this attach() to fill.
      search_input = new SearchInput ();
      // See FindBar's own doc comment on this same call: without it,
      // search_input stays at its own natural width instead of reaching
      // the clamp's maximum-size.
      search_input.hexpand = true;
      search_grid.attach (search_input, 2, 0, 1, 1);

      search_bar.connect_entry (search_input.entry);
      install_css ();

      search_input.entry.changed.connect (() => search_changed (search_input.entry.text));
      search_input.entry.activate.connect (() => search_next_requested ());
      regex_button.toggled.connect (() => search_options_changed ());
      case_sensitive_button.toggled.connect (() => search_options_changed ());
      whole_word_button.toggled.connect (() => search_options_changed ());
      search_button.clicked.connect (() => search_next_requested ());
      add_folder_button.clicked.connect (() => add_folder_requested ());
      // Return in "Where" runs the search too — same as the Find entry
      // itself, so the user doesn't have to click back into it (or onto
      // the Search button) just to submit after typing a scope pattern.
      where_entry.activate.connect (() => search_next_requested ());

      // CAPTURE: has to see Shift+Return before the entry's own native
      // "activate" — see FindBar's own doc comment on this same
      // controller for why.
      var key_controller = new Gtk.EventControllerKey ();
      key_controller.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
      key_controller.key_pressed.connect ((keyval, keycode, state) => {
        if (keyval == Gdk.Key.Return && (state & Gdk.ModifierType.SHIFT_MASK) != 0) {
          search_previous_requested ();
          return true;
        }
        if (keyval == Gdk.Key.Return && (state & Gdk.ModifierType.ALT_MASK) != 0) {
          select_all_requested ();
          return true;
        }
        return false;
      });
      search_input.entry.add_controller (key_controller);

      // Fires closed() off search-mode-enabled itself — see FindBar's
      // own doc comment for why this is the one place that actually
      // sees every path that closes the bar.
      search_bar.notify["search-mode-enabled"].connect (() => {
        if (!search_bar.search_mode_enabled) {
          closed ();
        }
      });
    }

    /** Sets the Find entry's text and selects it all — see FindBar's own doc comment for why this must be called after show_find(), not before. */
    public void set_find_text (string text) {
      search_input.entry.text = text;
      search_input.entry.select_region (0, -1);
    }

    /**
     * Fills every field/toggle from `query` — MainWindow's own Ctrl+Shift+F
     * calls this with EditorPaneWidget.current_find_in_files_query, which is
     * only non-null while the "Find Results" tab it produced is the
     * active one, so this only ever restores a search the user could
     * plausibly want to redo, never a stale one from some other tab.
     * `null` means "no search to restore" — resets to the same blank
     * state the bar starts in, gitignore included (its own template
     * default is checked; that's product intent, not FindInFilesQuery's
     * own unrelated default of false for a query nothing has touched yet).
     */
    public void set_query (FindInFilesQuery? query) {
      search_input.entry.text = query?.text ?? "";
      search_input.entry.select_region (0, -1);
      regex_button.active = query?.regex_enabled ?? false;
      case_sensitive_button.active = query?.case_sensitive_enabled ?? false;
      whole_word_button.active = query?.whole_word_enabled ?? false;
      gitignore_button.active = query?.gitignore_enabled ?? true;
      where_entry.text = query?.where_text ?? "";
    }

    /**
     * Appends every already-validated `/<relative-path>/` pattern
     * MainWindow's own on_add_folder_requested() computed, comma-
     * separated after whatever's already typed in where_entry — never
     * called with a partial batch: that method validates every chosen
     * folder itself is inside the linked folder *before* calling this
     * at all, so either all of them land here or none do.
     */
    public void append_where_patterns (string[] patterns) {
      if (patterns.length == 0) {
        return;
      }

      var text = where_entry.text.strip ();
      var joined = string.joinv (", ", patterns);
      where_entry.text = text == "" ? joined : text + ", " + joined;
    }

    /** Reflects the live search results onto the entry's own "N of M" counter — see FindBar's own doc comment on set_match_info() for the hidden-state rules. */
    public void set_match_info (int position, int count, bool has_search) {
      search_input.set_match_info (position, has_search ? count : 0);
    }

    /** Reveals the bar — Where is always shown alongside Find here, unlike FindBar's own Ctrl+F/Ctrl+H toggle, so there's no separate mode to pick. See FindBar's own doc comment for why focus is grabbed explicitly rather than left to Gtk.SearchBar's own auto-focus. */
    public void show_find () {
      search_bar.search_mode_enabled = true;
      search_input.grab_focus ();
    }

    /** IGlobalPanel's own close() — its entry's own text clears on its own once it does (see the class's own doc comment). */
    public void close () {
      search_bar.search_mode_enabled = false;
    }

    private void install_css () {
      // Reuses find-bar.css as-is: its rules target the generic
      // "searchbar"/"entry" CSS nodes, not anything find-bar-specific,
      // so there's nothing for a separate find-in-files-bar.css to add.
      GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/find-bar.css");
    }
  }
}
