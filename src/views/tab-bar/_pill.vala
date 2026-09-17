/**
 * A single tab in the {@link TabBarView}'s row: a title showing the
 * file name and, smaller and italic, its parent folder name; a close button
 * that's always clickable; and italic styling for the whole label while
 * the tab is a preview. Selection and double-click are reported via
 * signals; this widget knows nothing about `TabBarView` — that class
 * translates its signals into its own, keyed by path.
 *
 * Loads its widget tree via {@link Gtk.Builder} rather than a
 * composite-template subclass — same pattern as EditorView/MainWindowView.
 */
public class TabPill : Object {
    private Gtk.Box box;
    private Gtk.Label title_label;
    private Gtk.Button close_button;

    public Gtk.Widget widget { get { return box; } }

    /** Single click — makes this tab active. */
    public signal void selected ();

    /** Double click — promotes a preview tab to permanent. */
    public signal void double_clicked ();

    /** The close button was clicked. Always emitted; the button is never disabled. */
    public signal void close_requested ();

    /** Right click — open this tab's context menu at `(x, y)`, in this pill's own widget coordinates. */
    public signal void context_menu_requested (double x, double y);

    // Read-only outside this class (see set_label/set_preview/set_modified
    // for how they're set) — exposed so a ghost copy (see _ghost.vala) can
    // be built with the same label/state without this pill needing to know
    // dragging is even happening. Named is_preview/is_modified, not
    // preview/modified: those would collide with the set_preview()/
    // set_modified() methods below — a property named `preview` generates
    // a `tab_pill_set_preview` accessor in C, same symbol the method
    // already uses.
    public string file_name { get; private set; default = ""; }
    public string folder_name { get; private set; default = ""; }
    public bool is_preview { get; private set; default = false; }
    public bool is_modified { get; private set; default = false; }
    public bool is_deleted { get; private set; default = false; }

    static construct {
        install_css ();
    }

    public TabPill () {
        var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/tab-bar/_pill.ui");
        box = (Gtk.Box) builder.get_object ("pill");
        title_label = (Gtk.Label) builder.get_object ("title_label");
        close_button = (Gtk.Button) builder.get_object ("close_button");

        var click = new Gtk.GestureClick ();
        click.pressed.connect ((n_press, x, y) => {
            if (n_press == 1) {
                selected ();
            } else if (n_press == 2) {
                double_clicked ();
            }
        });
        box.add_controller (click);

        var right_click = new Gtk.GestureClick ();
        right_click.set_button (Gdk.BUTTON_SECONDARY);
        right_click.pressed.connect ((n_press, x, y) => context_menu_requested (x, y));
        box.add_controller (right_click);

        close_button.clicked.connect (() => close_requested ());
    }

    /** `folder_name` is the file's immediate parent directory name, or "" if it has none. */
    public void set_label (string file_name, string folder_name) {
        this.file_name = file_name;
        this.folder_name = folder_name;
        refresh_label ();
    }

    public void set_active (bool active) {
        if (active) {
            box.add_css_class ("active");
        } else {
            box.remove_css_class ("active");
        }
    }

    public void set_preview (bool preview) {
        is_preview = preview;
        refresh_label ();
    }

    public void set_modified (bool modified) {
        is_modified = modified;
        refresh_label ();
    }

    /** The file this tab was opened from was deleted (or moved away) outside Opus. */
    public void set_deleted (bool deleted) {
        is_deleted = deleted;
        refresh_label ();
    }

    private void refresh_label () {
        var file_part = Markup.escape_text (file_name);
        if (is_modified) {
            file_part = "%s •".printf (file_part);
        }
        if (is_preview) {
            file_part = "<i>%s</i>".printf (file_part);
        }
        if (is_deleted) {
            file_part = "<s>%s</s>".printf (file_part);
        }

        var text = file_part;
        if (folder_name != "") {
            text += " <span style=\"italic\" size=\"smaller\" alpha=\"50%%\">%s</span>".printf (Markup.escape_text (folder_name));
        }

        title_label.label = text;
    }

    // Gtk.Button has no size-in-pixels API for icon buttons: the theme's
    // default flat/circular button padding makes it much larger than the
    // 24x24 close button in e.g. Nautilus's tabs. Forcing it down needs CSS.
    private static void install_css () {
        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_string ("""
            .tab-close-button {
                min-width: 24px;
                min-height: 24px;
                padding: 0;
            }

            /* Dim inactive tabs instead of a second "selected" background
             * color — one so close to the view-switcher's own would be more
             * confusing than clarifying. */
            .tab-pill:not(.active) {
                opacity: 0.6;
            }

            /* Close button only shows on the active tab or on hover, not on
             * every idle tab. */
            .tab-pill .tab-close-button {
                opacity: 0;
            }

            .tab-pill.active .tab-close-button,
            .tab-pill:hover .tab-close-button {
                opacity: 1;
            }
        """);

        // Gtk.StyleContext.add_provider_for_display is deprecated since GTK
        // 4.10 (removed in GTK 5) with no replacement — same unresolved
        // upstream issue as the one cited in views/file-tree/index.vala:
        // https://gitlab.gnome.org/GNOME/gtk/-/issues/2603
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }
}
