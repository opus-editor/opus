/**
 * Facade for the application's main window. Loads the window and its named
 * slots straight from the compiled Blueprint via {@link Gtk.Builder} — the
 * same way {@link EditorView} loads its widget tree, no composite-template
 * subclass needed — and composes the sidebar and tab-bar widgets built
 * elsewhere into those slots. The content pane itself is handed whatever
 * widget the active tab owns via show_content(), rather than being wired to
 * one fixed widget at construction — it doesn't assume that's always an
 * {@link EditorView}. Holds no controller logic of its own; whoever wires
 * the app hands it the real widgets and reacts to their own controllers
 * separately.
 */
public class MainWindowView : Object {
    private Adw.ApplicationWindow window;
    private Adw.OverlaySplitView split_view;
    private Adw.Bin sidebar_bin;
    private Adw.Bin tab_bar_bin;
    private Adw.Bin content_bin;
    private Adw.StatusPage empty_state;
    private Gtk.MenuButton menu_button;
    private Gtk.ToggleButton sidebar_toggle_button;
    private Gtk.Widget close_folder_item;
    private GLib.Settings settings;

    // The first theme-selector button becomes the group's own leader
    // (Gtk.CheckButton.group has no getter, so this is the only way to
    // point every later button at the same group) — see
    // build_theme_selector().
    private Gtk.CheckButton? theme_selector_group_leader = null;

    // Whether "Open Folder…" has ever linked a folder into this window —
    // the sidebar-reveal button and the primary menu's "Close Folder"
    // (see update_folder_dependent_ui) both stay hidden without one:
    // there'd be nothing in the sidebar to reveal, and nothing linked to
    // close.
    private bool has_linked_folder = false;

    // The primary menu's Save/Save as… group — kept live (not rebuilt on
    // each open) via set_active_state(), the same push-on-change pattern
    // TabPill.set_modified()/mark_preview() already use elsewhere, rather
    // than querying EditorController state at popover-open time (which
    // Gtk.MenuButton has no signal for anyway).
    private Gtk.Widget save_group_separator;
    private Gtk.Widget save_item;
    private Gtk.Widget save_as_item;
    private bool has_active_tab = false;
    private bool active_is_dirty = false;

    /** Ctrl+W anywhere in the window — the tab context menu's own "Close" item names this same shortcut. */
    public signal void close_active_tab_requested ();

    /** Ctrl+S anywhere in the window, or the primary menu's own "Save" — applies to the active tab. */
    public signal void save_requested ();

    /** Ctrl+Shift+S anywhere in the window, or the primary menu's own "Save as…" — applies to the active tab. */
    public signal void save_as_requested ();

    /** Ctrl+N, or the primary menu's own "New File". */
    public signal void new_file_requested ();

    /** Ctrl+Shift+N, or the primary menu's own "New Window". */
    public signal void new_window_requested ();

    /** Ctrl+O, or the primary menu's own "Open File…". */
    public signal void open_file_requested ();

    /** Ctrl+Shift+O, or the primary menu's own "Open Folder…". */
    public signal void open_folder_requested ();

    /** The primary menu's own "Close Folder" — unlinks whatever folder is currently linked, hiding the sidebar entirely again. */
    public signal void close_folder_requested ();

    /** The window was actually destroyed (not just requested to close, which can be cancelled) — main.vala uses this to release this window's own Session. */
    public signal void closed ();

    public MainWindowView (Gtk.Application app, Gtk.Widget tab_bar, GLib.Settings settings) {
        this.settings = settings;

        var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/main-window/index.ui");
        window = (Adw.ApplicationWindow) builder.get_object ("window");
        split_view = (Adw.OverlaySplitView) builder.get_object ("split_view");
        sidebar_bin = (Adw.Bin) builder.get_object ("sidebar_bin");
        tab_bar_bin = (Adw.Bin) builder.get_object ("tab_bar_bin");
        content_bin = (Adw.Bin) builder.get_object ("content_bin");
        menu_button = (Gtk.MenuButton) builder.get_object ("menu_button");
        sidebar_toggle_button = (Gtk.ToggleButton) builder.get_object ("sidebar_toggle_button");

        // Restores whatever size the last window that closed was left at
        // (window-width/window-height default to the same 900x600 this
        // window used to hardcode in its own Blueprint template) — saved
        // back on close_request below. Deliberately session-wide, not
        // per-window: with several windows open, whichever one closes
        // last is what the next launch restores, matching most GNOME
        // apps' own single-shared-size behavior rather than remembering
        // one size per window.
        window.set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
        window.close_request.connect (() => {
            settings.set_int ("window-width", window.get_width ());
            settings.set_int ("window-height", window.get_height ());
            return false;
        });

        // Gtk.Window has its own plain destroy() method (calls
        // gtk_window_destroy()), which shadows Gtk.Widget's own `destroy`
        // signal for a Gtk.Window-typed reference — same issue, same fix,
        // as add_controller()'s own cast above.
        ((Gtk.Widget) window).destroy.connect (() => closed ());
        build_primary_menu ();

        // GNOME Builder's own header/content divider (libpanel's
        // panelframeheaderbar) mixes --border-color down to 60% instead of
        // using it at full strength like Adwaita's default `separator`
        // does — a visibly subtler line. Matches that here rather than
        // hardcoding the hex it renders to, so it still tracks the accent
        // and light/dark theme automatically.
        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_string ("""
            separator.content-divider {
                background: color-mix(in srgb, var(--border-color) 60%, transparent);
            }

            /* libadwaita's own tooltip.background rule (checked its
             * source, _tooltip.scss) sets RGB(0 0 6 / 80%) — a translucent
             * near-black, always, regardless of light/dark theme. Fine
             * for a short label, but this UI packs a lot of text close
             * together (the tab tooltip's own full path, among others),
             * so whatever's behind a tooltip keeps showing through enough
             * to fight with it. Same color, just opaque — only the alpha
             * changes, kept as `.background` since libadwaita's own
             * comment there explains why (double-drawing otherwise). */
            tooltip.background {
                background-color: rgb(0 0 6);
            }
        """);
        // See views/tab-bar/_pill.vala for why add_provider_for_display
        // despite the GTK 4.10 deprecation with no replacement.
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        window.application = app;
        tab_bar_bin.child = tab_bar;
        // No folder is linked at construction — the sidebar has nothing
        // to show until link_folder() gives it one ("Open Folder…", or
        // open_workspace() right after construction when launched with a
        // folder argument). Adw.HeaderBar's own split-view integration
        // (see the sidebar header's comment in the Blueprint) already
        // reacts to this, moving the window's controls to the content
        // header on its own — same mechanism the width breakpoint uses.
        split_view.show_sidebar = false;

        // The button itself just mirrors/drives show-sidebar — the split
        // view already reveals/hides accordingly, animation and all, and
        // (per its own source) already dismisses on an outside click
        // while collapsed, with no extra code needed for that part.
        split_view.bind_property (
            "show-sidebar", sidebar_toggle_button, "active", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE
        );
        split_view.notify["collapsed"].connect (update_folder_dependent_ui);

        // On the window itself, not a specific widget: these need to fire
        // no matter where focus currently is (sidebar, tab bar, or the
        // editor's own GtkSourceView, none of which bind Ctrl+W/Ctrl+S/
        // Ctrl+Shift+S to anything of their own, so nothing here competes
        // with a more specific handler for the same keys).
        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        // Adw.ApplicationWindow implements Gtk.ShortcutManager, whose own
        // add_controller (Gtk.ShortcutController) shadows Gtk.Widget's —
        // the cast picks the one that actually takes an EventControllerKey.
        ((Gtk.Widget) window).add_controller (key_controller);

        // Generic on purpose, not "…from the sidebar": a blank/file-only
        // window (no folder linked) has no sidebar to speak of at all.
        empty_state = new Adw.StatusPage () {
            title = _("No File Open"),
            description = _("Open a file or folder to start editing."),
            icon_name = "document-open-symbolic",
        };
        // No tab open yet, so there's nothing to show in content_bin —
        // stays on empty_state until show_content() says otherwise, rather
        // than assuming there's always some editor-shaped widget to mount.
        content_bin.child = empty_state;
    }

    /**
     * Shows `widget` — the active tab's own content, an {@link EditorView}'s
     * today but not assumed to always be — in the content pane, replacing
     * whatever was shown before.
     */
    public void show_content (Gtk.Widget widget) {
        content_bin.child = widget;
    }

    /** Shows the empty-state placeholder in the content pane, e.g. once the last open tab closes. */
    public void show_empty_state () {
        content_bin.child = empty_state;
    }

    /**
     * Links a folder into this window — "Open Folder…", whether this
     * window had none yet or is replacing one it already had. Shows the
     * sidebar (it has nothing to show, and stays hidden entirely, until a
     * folder is actually linked — see the constructor).
     */
    public void link_folder (Gtk.Widget sidebar) {
        sidebar_bin.child = sidebar;
        has_linked_folder = true;
        split_view.show_sidebar = true;
        update_folder_dependent_ui ();
    }

    /** Shows the sidebar if it's currently collapsed/hidden behind the toggle button — "Reveal in Sidebar" needs it actually visible, not just linked, same as clicking sidebar_toggle_button by hand would. A no-op with no folder linked at all (has_linked_folder false): nothing to reveal. */
    public void reveal_sidebar () {
        if (has_linked_folder) {
            split_view.show_sidebar = true;
        }
    }

    /** "Close Folder" — the opposite of link_folder(): the sidebar goes back to not existing at all, same as a window that never had one linked. Open tabs stay exactly as they are; only the sidebar (and what "Copy Relative Path" resolves against, main.vala's own concern) are affected. */
    public void unlink_folder () {
        sidebar_bin.child = null;
        has_linked_folder = false;
        split_view.show_sidebar = false;
        update_folder_dependent_ui ();
    }

    private void update_folder_dependent_ui () {
        sidebar_toggle_button.visible = has_linked_folder && split_view.collapsed;
        close_folder_item.visible = has_linked_folder;
    }

    public void show_error (string message) {
        var dialog = new Adw.AlertDialog (_("Error"), message);
        dialog.add_response ("ok", _("OK"));
        dialog.present (window);
    }

    private bool on_key_pressed (uint keyval, uint keycode, Gdk.ModifierType state) {
        if ((state & Gdk.ModifierType.CONTROL_MASK) == 0) {
            return false;
        }

        // Shift already changes the keyval itself (lowercase 's' becomes
        // uppercase 'S'), on top of setting SHIFT_MASK — comparing the raw
        // keyval against Gdk.Key.s below would never match with Shift
        // held, silently missing Ctrl+Shift+S (found live: Ctrl+S worked,
        // Ctrl+Shift+S didn't). Normalizing here lets the switch below
        // check letters only, leaving Shift entirely to the flag above.
        keyval = Gdk.keyval_to_lower (keyval);

        var shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
        switch (keyval) {
            case Gdk.Key.w:
                close_active_tab_requested ();
                return true;
            case Gdk.Key.s:
                if (shift) {
                    save_as_requested ();
                } else {
                    save_requested ();
                }
                return true;
            case Gdk.Key.n:
                if (shift) {
                    new_window_requested ();
                } else {
                    new_file_requested ();
                }
                return true;
            case Gdk.Key.o:
                if (shift) {
                    open_folder_requested ();
                } else {
                    open_file_requested ();
                }
                return true;
            default:
                return false;
        }
    }

    /**
     * Builds the primary (hamburger) menu once, at construction — its
     * Save/Save as… group is kept in sync afterwards via set_active_state()
     * rather than being rebuilt lazily on open (see the fields' own
     * comment). Save/Save as… fire the very same save_requested/
     * save_as_requested signals Ctrl+S/Ctrl+Shift+S already do — one
     * signal per action regardless of what triggered it.
     */
    private void build_primary_menu () {
        var popover = new Gtk.Popover ();
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

        box.append (build_theme_selector ());
        box.append (ContextMenu.separator ());

        box.append (ContextMenu.item (_("New File"), () => new_file_requested (), popover, Gtk.accelerator_get_label (Gdk.Key.n, Gdk.ModifierType.CONTROL_MASK)));
        box.append (ContextMenu.item (_("New Window"), () => new_window_requested (), popover, Gtk.accelerator_get_label (Gdk.Key.n, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)));
        box.append (ContextMenu.separator ());
        box.append (ContextMenu.item (_("Open File…"), () => open_file_requested (), popover, Gtk.accelerator_get_label (Gdk.Key.o, Gdk.ModifierType.CONTROL_MASK)));
        box.append (ContextMenu.item (_("Open Folder…"), () => open_folder_requested (), popover, Gtk.accelerator_get_label (Gdk.Key.o, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)));
        close_folder_item = ContextMenu.item (_("Close Folder"), () => close_folder_requested (), popover);
        box.append (close_folder_item);

        save_group_separator = ContextMenu.separator ();
        box.append (save_group_separator);
        save_item = ContextMenu.item (_("Save"), () => save_requested (), popover, Gtk.accelerator_get_label (Gdk.Key.s, Gdk.ModifierType.CONTROL_MASK));
        box.append (save_item);
        save_as_item = ContextMenu.item (_("Save as…"), () => save_as_requested (), popover, Gtk.accelerator_get_label (Gdk.Key.s, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK));
        box.append (save_as_item);

        popover.child = box;
        // Not the `popover` property: the vapi types it as Gtk.Popover,
        // but the real C setter (gtk_menu_button_set_popover) takes a
        // plain GtkWidget* — the property assignment generates a call
        // that mismatches the real header (-Wincompatible-pointer-types,
        // same vapi/C-header mismatch class as this project's other
        // already-documented warnings). The plain set_popover() method is
        // typed Gtk.Widget? in the vapi, matching the real signature.
        menu_button.set_popover (popover);

        update_save_group ();
        // close_folder_item defaults to visible (a plain Gtk.Button's own
        // default) — this is what actually hides it until a folder is
        // linked; sidebar_toggle_button already starts hidden via the
        // Blueprint's own `visible: false;`, so it doesn't strictly need
        // this call too, but sharing one update function for everything
        // has_linked_folder affects is simpler than two.
        update_folder_dependent_ui ();
    }

    /**
     * The primary menu's own light/dark/follow-system radio row — three
     * grouped Gtk.CheckButtons, each wired straight to the "style-variant"
     * GLib.Settings key via its own action-name/action-target, with no
     * manual read/write/sync code of our own: GLib.Settings.create_action()
     * already returns a real Gio.Action whose state mirrors the setting
     * both ways (activating it with a target writes the setting; the
     * setting changing elsewhere updates which button reads as active).
     * Ported from GNOME Text Editor's own real EditorThemeSelector
     * (editor-theme-selector.ui + editor-window-actions.c) — same widget
     * shape (three GtkCheckButtons in one group, `action-name`/
     * `action-target` on each, no signal handlers), same settings key
     * name and choices ("follow"/"light"/"dark"), same circular-swatch
     * look (install_css() below, values taken straight from its own
     * style.css). The "settings" action-group prefix is inserted on the
     * window itself, same as Text Editor's own _editor_window_actions_init()
     * — a popover attached to a descendant Gtk.MenuButton still resolves
     * action-names up through its attachment widget's own ancestry.
     */
    private Gtk.Widget build_theme_selector () {
        install_theme_selector_css ();

        var action = settings.create_action ("style-variant");
        var action_group = new SimpleActionGroup ();
        action_group.add_action (action);
        ((Gtk.Widget) window).insert_action_group ("settings", action_group);

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_start = 6, margin_end = 6, margin_top = 6, margin_bottom = 6, hexpand = true,
        };
        box.append (theme_selector_button ("follow", _("Follow System Style")));
        box.append (theme_selector_button ("light", _("Light Style")));
        box.append (theme_selector_button ("dark", _("Dark Style")));
        return box;
    }

    private Gtk.Widget theme_selector_button (string variant, string tooltip_text) {
        var button = new Gtk.CheckButton () {
            hexpand = true,
            halign = Gtk.Align.CENTER,
            focus_on_click = false,
            action_name = "settings.style-variant",
            action_target = new Variant.string (variant),
            tooltip_text = tooltip_text,
        };
        button.add_css_class ("theme-selector");
        button.add_css_class (variant);
        if (theme_selector_group_leader == null) {
            theme_selector_group_leader = button;
        } else {
            button.group = theme_selector_group_leader;
        }
        return button;
    }

    /**
     * Circular swatches (44px, follow = diagonal light/dark split, light
     * = solid white, dark = solid #202020), a checked one ringed in the
     * accent color — colors and sizes copied directly from GNOME Text
     * Editor's own real style.css (`themeselector checkbutton[.variant]`
     * rules), translated from its GTK3-era `@named_color` syntax to
     * libadwaita's own CSS custom properties (`var(--accent-bg-color)`,
     * `var(--border-color)`) already used elsewhere in this codebase
     * (see EditorView.install_css()) — same colors, current syntax. The
     * native radio indicator (the small checkmark/dot GTK draws by
     * default) is fully suppressed — background/border/box-shadow/icon
     * all cleared, not just the icon — the accent-colored ring alone is
     * enough to show which one is selected. Text Editor's own version
     * repositions that indicator instead of removing it; ported here
     * first, but repositioning it well enough to look right turned out
     * not to be worth it, so it's just gone.
     */
    private void install_theme_selector_css () {
        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_string ("""
            checkbutton.theme-selector {
                padding: 1px;
                min-width: 44px;
                min-height: 44px;
                background-clip: content-box;
                border-radius: 9999px;
                box-shadow: inset 0 0 0 1px var(--border-color);
            }
            checkbutton.theme-selector:checked {
                box-shadow: inset 0 0 0 2px var(--accent-bg-color);
            }
            checkbutton.theme-selector.follow {
                background-image: linear-gradient(to bottom right, #fff 49.99%, #202020 50.01%);
            }
            checkbutton.theme-selector.light {
                background-color: #fff;
            }
            checkbutton.theme-selector.dark {
                background-color: #202020;
            }
            checkbutton.theme-selector radio {
                -gtk-icon-source: none;
                background: none;
                border: none;
                box-shadow: none;
                min-width: 0;
                min-height: 0;
                padding: 0;
            }
        """);
        // See views/tab-bar/_pill.vala for why add_provider_for_display
        // despite the GTK 4.10 deprecation with no replacement.
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }

    /** Whether the active tab exists/is dirty — drives the primary menu's Save/Save as… group: hidden entirely with no active tab, "Save" itself disabled while it's clean. */
    public void set_active_state (bool has_active_tab, bool dirty) {
        this.has_active_tab = has_active_tab;
        this.active_is_dirty = dirty;
        update_save_group ();
    }

    private void update_save_group () {
        save_group_separator.visible = has_active_tab;
        save_item.visible = has_active_tab;
        save_as_item.visible = has_active_tab;
        save_item.sensitive = active_is_dirty;
    }

    /** The system's own file chooser (a portal dialog) — for "Open File…". Returns the chosen path, or null if cancelled/failed. */
    public async string? choose_file () {
        var dialog = new Gtk.FileDialog ();
        try {
            var file = yield dialog.open (window, null);
            return file != null ? file.get_path () : null;
        } catch (Error e) {
            return null;
        }
    }

    /** The system's own folder chooser (a portal dialog) — for "Open Folder…". Returns the chosen path, or null if cancelled/failed. */
    public async string? choose_folder () {
        var dialog = new Gtk.FileDialog ();
        try {
            var folder = yield dialog.select_folder (window, null);
            return folder != null ? folder.get_path () : null;
        } catch (Error e) {
            return null;
        }
    }

    /** Shows the window. */
    public void present () {
        window.present ();
    }
}
