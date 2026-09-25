/**
 * Find/Replace bar — Ctrl+F shows it in Find mode, Ctrl+H in Replace mode
 * (see MainWindowView's own key handling); its own close button, or
 * Escape from *anywhere in the window* (not just this bar), closes it
 * again — the latter isn't anything of this class's own doing: it
 * implements {@link GlobalPanel}, and MainWindowView's own window-wide
 * Escape handling is what actually drives close() from that, generically,
 * the same way it would for any other panel that implements the same
 * interface (see GlobalPanel's own doc comment for the reasoning).
 * SearchController drives the actual Find/Replace logic against
 * EditorView/EditorController.
 *
 * Gtk.SearchBar's own native behavior (checked its real source,
 * gtksearchbar.c) matters less here than it first looks: its auto-focus-
 * on-open only fires for a connected Gtk.Entry/Gtk.SearchEntry — the
 * connected entry here (SearchCounterEntry's own inner Gtk.Text, plain
 * Gtk.Editable — see its own doc comment for why) is neither, so
 * show_find()/show_replace() below grab focus themselves instead. Its
 * text-clearing behavior cuts the other way: with that same "neither
 * type" entry, it clears the entry on *every* search-mode-enabled
 * transition, not just closing — see set_find_text()'s own doc comment,
 * which relies on that ordering rather than fighting it.
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
 * The panel/input/buttons themselves match GNOME Text Editor's own real
 * search bar (editor-search-bar.ui, checked against its source) minus
 * the options menu (other_buttons stands in for that, as plain toggles
 * instead of a popover menu — a deliberate deviation, not an oversight)
 * and its separate mouse-driven mode toggle button (Ctrl+H is the only
 * trigger for now).
 */
public class SearchBar : Object, GlobalPanel {
    private Gtk.SearchBar search_bar;
    private SearchCounterEntry search_counter_entry;
    private Gtk.ToggleButton regex_button;
    private Gtk.ToggleButton case_sensitive_button;
    private Gtk.ToggleButton whole_word_button;
    private Gtk.Button move_previous_button;
    private Gtk.Button move_next_button;
    private Gtk.Entry replace_entry;
    private Gtk.Box replace_actions;
    private Gtk.Button replace_button;
    private Gtk.Button replace_all_button;
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

    /** "Replace" clicked, or plain Return in the Replace entry. */
    public signal void replace_requested ();

    /** "Replace All" clicked. */
    public signal void replace_all_requested ();

    /**
     * The bar just closed — Escape from anywhere in the window (via
     * GlobalPanel, see its own doc comment), the native close button, or
     * close() called directly (e.g. the last open tab closing). By the
     * time this fires, the live search state is already
     * cleared (GtkSearchBar's own real close path always clears the
     * connected entry's text first — checked gtksearchbar.c): Search
     * Controller listens for this to hand EditorView's last live match
     * off to the real selection before it's gone for good, not to read
     * anything live off this bar itself.
     */
    public signal void closed ();

    /** GlobalPanel's own is_open — whether the bar is currently revealed. */
    public bool is_open { get { return search_bar.search_mode_enabled; } }

    public bool regex_enabled { get { return regex_button.active; } }
    public bool case_sensitive_enabled { get { return case_sensitive_button.active; } }
    public bool whole_word_enabled { get { return whole_word_button.active; } }
    public string replace_text { get { return replace_entry.text; } }

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
        replace_button = (Gtk.Button) builder.get_object ("replace_button");
        replace_all_button = (Gtk.Button) builder.get_object ("replace_all_button");
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
        replace_entry.activate.connect (() => replace_requested ());
        replace_button.clicked.connect (() => replace_requested ());
        replace_all_button.clicked.connect (() => replace_all_requested ());

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

        // Fires closed() off search-mode-enabled itself, not e.g. inside
        // hide()/the escape controller above: the native close button
        // (show-close-button: true) flips that same property directly,
        // with no code of ours in the loop at all (checked gtksearchbar.c
        // — close_button's own "clicked" handler just calls gtk_revealer_
        // set_reveal_child(FALSE), nothing else), so this is the one
        // place that actually sees every path that closes the bar.
        search_bar.notify["search-mode-enabled"].connect (() => {
            if (!search_bar.search_mode_enabled) {
                closed ();
            }
        });
    }

    /**
     * Sets the Find entry's text and selects it all — SearchController's
     * own Ctrl+F "prefill from the current selection". Must be called
     * *after* show_find(), not before: Gtk.SearchBar's own real
     * reveal_child_changed_cb (checked gtksearchbar.c) resets its
     * connected entry's text to "" on every search-mode-enabled
     * transition where that entry isn't itself a Gtk.Entry/
     * Gtk.SearchEntry — ours never is (a plain Gtk.Text, see
     * SearchCounterEntry's own doc comment for why) — so show_find()'s
     * own transition would otherwise immediately wipe out whatever was
     * set here first. Setting `entry.text` already fires this same
     * entry's own `changed` handler synchronously (a plain Gtk.Editable
     * guarantee), which is what actually runs the search — no separate
     * call needed here to make that happen.
     */
    public void set_find_text (string text) {
        search_counter_entry.entry.text = text;
        search_counter_entry.entry.select_region (0, -1);
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

    /** GlobalPanel's own close() — its entry's own text clears on its own once it does (see the class's own doc comment). Also called directly (not just reached through GlobalPanel) once there's nothing left to search — e.g. the last open tab just closed. */
    public void close () {
        search_bar.search_mode_enabled = false;
    }

    private void set_replace_mode (bool is_replace) {
        replace_entry.visible = is_replace;
        replace_actions.visible = is_replace;
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
