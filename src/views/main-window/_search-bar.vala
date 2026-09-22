/**
 * Find/Replace bar — Ctrl+F shows it in Find mode, Ctrl+H in Replace mode
 * (see MainWindowView's own key handling); its own close button, or
 * Escape while its entry has focus, hide it again. Neither of those
 * needed a line of code here: both are Gtk.SearchBar's own native
 * behavior once connect_entry() wires a real Gtk.SearchEntry to it
 * (checked its real source, gtksearchbar.c) — closing also clears the
 * entry's text automatically, and opening focuses it, for the same
 * reason.
 *
 * Lives at the window level, not inside EditorView, on purpose: it spans
 * the full window width (below the sidebar too), the same way the header
 * above it does — not squeezed into just the content column the way a
 * per-tab search bar would be.
 *
 * Find/Replace mode mirrors GNOME Text Editor's own real search bar
 * (editor-search-bar.c, `_editor_search_bar_set_mode`): Ctrl+F always
 * switches back to Find (hiding the replace row), Ctrl+H always switches
 * to Replace (showing it) — pressing either while already in the other
 * mode re-targets the bar rather than toggling it shut.
 *
 * Purely visual for now — the panel, the input, the buttons, and the
 * signals below all render/fire, but nothing outside this class listens
 * yet: no controller drives real search against EditorView. Matches
 * GNOME Text Editor's own real search bar (editor-search-bar.ui, checked
 * against its source) minus the options menu (other_buttons stands in
 * for that, as plain toggles instead of a popover menu — a deliberate
 * deviation, not an oversight) and its separate mouse-driven mode toggle
 * button (Ctrl+H is the only trigger for now).
 */
public class SearchBar : Object {
    private Gtk.SearchBar search_bar;
    private SearchCounterEntry search_counter_entry;
    private Gtk.ToggleButton regex_button;
    private Gtk.ToggleButton case_sensitive_button;
    private Gtk.ToggleButton whole_word_button;
    private Gtk.Button move_previous_button;
    private Gtk.Button move_next_button;
    private Gtk.Entry replace_entry;
    private Gtk.Box replace_actions;
    private Gtk.ToggleButton preserve_case_button;
    private Gtk.Separator replace_divider;

    public Gtk.Widget widget { get { return search_bar; } }

    /** The Find entry's text changed — every keystroke, and once more (with "") on the bar's own native clear-on-close. */
    public signal void search_changed (string text);

    /** Regular Expressions/Case Sensitive/Match Whole Word Only — one of the three toggled. No argument: which one fired isn't itself meaningful, read the three *_enabled properties below for the current combination. */
    public signal void search_options_changed ();

    /** Previous Match clicked, or Shift+Return in the Find entry. */
    public signal void search_previous_requested ();

    /** Next Match clicked, or plain Return in the Find entry. */
    public signal void search_next_requested ();

    public bool regex_enabled { get { return regex_button.active; } }
    public bool case_sensitive_enabled { get { return case_sensitive_button.active; } }
    public bool whole_word_enabled { get { return whole_word_button.active; } }

    public SearchBar () {
        var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/main-window/_search-bar.ui");
        search_bar = (Gtk.SearchBar) builder.get_object ("search_bar");
        var search_grid = (Gtk.Grid) builder.get_object ("search_grid");
        regex_button = (Gtk.ToggleButton) builder.get_object ("regex_button");
        case_sensitive_button = (Gtk.ToggleButton) builder.get_object ("case_sensitive_button");
        whole_word_button = (Gtk.ToggleButton) builder.get_object ("whole_word_button");
        move_previous_button = (Gtk.Button) builder.get_object ("move_previous_button");
        move_next_button = (Gtk.Button) builder.get_object ("move_next_button");
        replace_entry = (Gtk.Entry) builder.get_object ("replace_entry");
        replace_actions = (Gtk.Box) builder.get_object ("replace_actions");
        preserve_case_button = (Gtk.ToggleButton) builder.get_object ("preserve_case_button");
        replace_divider = (Gtk.Separator) builder.get_object ("replace_divider");

        // Built in code, not declared in the .blp — see
        // SearchCounterEntry's own doc comment for what it is and why;
        // search_grid's (2, 0) cell is left empty there specifically for
        // this attach() to fill.
        search_counter_entry = new SearchCounterEntry ();
        search_grid.attach (search_counter_entry, 2, 0, 1, 1);

        search_bar.connect_entry (search_counter_entry.entry);
        install_css ();

        search_counter_entry.entry.changed.connect (() => search_changed (search_counter_entry.entry.text));
        search_counter_entry.entry.activate.connect (() => search_next_requested ());
        regex_button.toggled.connect (() => search_options_changed ());
        case_sensitive_button.toggled.connect (() => search_options_changed ());
        whole_word_button.toggled.connect (() => search_options_changed ());
        move_previous_button.clicked.connect (() => search_previous_requested ());
        move_next_button.clicked.connect (() => search_next_requested ());

        // CAPTURE: has to see Shift+Return before the entry's own native
        // "activate" (which fires on plain Return regardless of Shift,
        // single-line entries have no newline to insert instead) —
        // claiming it here is what makes Shift+Return mean "previous"
        // instead of also firing search_next_requested().
        var key_controller = new Gtk.EventControllerKey ();
        key_controller.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
        key_controller.key_pressed.connect ((keyval, keycode, state) => {
            if (keyval == Gdk.Key.Return && (state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                search_previous_requested ();
                return true;
            }
            return false;
        });
        search_counter_entry.entry.add_controller (key_controller);
    }

    /**
     * Reflects the live search results onto the entry's own "N of M"
     * counter — hidden entirely once `count` is 0 (see SearchCounterEntry
     * .set_match_info()'s own doc comment). `has_search` false (an empty
     * Find text) forces that same hidden state regardless of `count`:
     * "nothing being searched for" isn't "0 matches".
     */
    public void set_match_info (int position, int count, bool has_search) {
        search_counter_entry.set_match_info (position, has_search ? count : 0);
    }

    /**
     * Reveals the bar in Find mode — hides the replace row if it was
     * showing. Always grabs focus into the entry itself, not just left
     * to Gtk.SearchBar's own auto-focus-on-reveal: that only fires on an
     * actual closed → open transition (its real notify::reveal-child
     * handler, gtksearchbar.c) — pressing Ctrl+F again while the bar is
     * already open (focus having since moved into the editor) wouldn't
     * touch `search-mode-enabled` at all, so nothing would bring focus
     * back on its own.
     */
    public void show_find () {
        set_replace_mode (false);
        search_bar.search_mode_enabled = true;
        search_counter_entry.grab_focus ();
    }

    /** Reveals the bar in Replace mode — see show_find()'s own doc comment for why focus is grabbed explicitly rather than left to Gtk.SearchBar's own auto-focus. */
    public void show_replace () {
        set_replace_mode (true);
        search_bar.search_mode_enabled = true;
        search_counter_entry.grab_focus ();
    }

    /** Hides the bar — its entry's own text clears on its own once it does (see the class's own doc comment). Called directly (not just left to its own close button/Escape) once there's nothing left to search — e.g. the last open tab just closed. */
    public void hide () {
        search_bar.search_mode_enabled = false;
    }

    private void set_replace_mode (bool is_replace) {
        replace_entry.visible = is_replace;
        replace_actions.visible = is_replace;
        preserve_case_button.visible = is_replace;
        replace_divider.visible = is_replace;
    }

    private void install_css () {
        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_string ("""
            /* libadwaita's own default (_common.scss: $focus_transition,
             * applied via the focus-ring() mixin) animates outline-color/
             * width/offset over 200ms on every focus change — the "scale
             * + fade" as focus moves from one button/entry to the next.
             * Dropping outline-* from the transition list here removes
             * just that animation; button still keeps its own separate
             * background-color hover fade ($button_transition, same
             * mixin call) since that's listed back in explicitly. entry
             * has no other transition of its own (checked _entries.scss:
             * the focus-ring() call is its only one), so it's fine to
             * drop entirely. */
            searchbar button {
                transition-property: background;
            }
            searchbar entry {
                transition-property: none;
            }
        """);
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }
}
