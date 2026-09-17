/** See ContextMenu.item(). */
public delegate void MenuAction ();

/**
 * A small shared builder for the flat-button right-click menus used by both
 * FileTreeView and TabBarView — a plain Gtk.Popover containing a vertical
 * Gtk.Box of flat Gtk.Buttons and Gtk.Separators, not Gtk.PopoverMenu/
 * GLib.Menu+Gio.SimpleAction: nothing else in this codebase uses that
 * pattern, every interactive row/pill here is plain widgets wired to
 * signals, and a menu isn't reason enough to introduce a whole new
 * action-group convention just for itself.
 */
public class ContextMenu : Object {
    // Not a `static construct` block: this class is only ever used through
    // its static methods, never instantiated, and a GObject class's
    // `static construct`/class_init only runs once something actually
    // triggers type registration — plain static-method calls don't (found
    // the hard way, twice: once because this class is never `new`'d at
    // all, then again because the check lived in create() specifically —
    // a menu attached straight to a Gtk.MenuButton's own `popover`
    // property, as the primary menu is, never calls create() at all, so
    // its CSS silently never loaded either). The check now lives in
    // item() instead — the one thing every possible menu, built however
    // it likes, always calls at least once (a menu with no items isn't a
    // menu) — so there is exactly one place left that can ever forget it.
    private static bool css_installed = false;

    /** A popover parented on `parent`, pointing at `(x, y)` (in `parent`'s own coordinates) — set its `.child` and call `.popup ()` once its items are built. */
    public static Gtk.Popover create (Gtk.Widget parent, double x, double y) {
        var popover = new Gtk.Popover ();
        popover.set_parent (parent);
        popover.has_arrow = false;
        popover.set_pointing_to (Gdk.Rectangle () { x = (int) x, y = (int) y, width = 1, height = 1 });
        popover.closed.connect (() => popover.unparent ());
        return popover;
    }

    // 6px, matching AdwTabView's own dividers/spacing conventions elsewhere
    // in this codebase — a bare separator with no margin reads as glued to
    // its neighbors.
    public static Gtk.Widget separator () {
        var separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        separator.margin_top = 6;
        separator.margin_bottom = 6;
        return separator;
    }

    /**
     * A flat button styled as a menu row; `action` runs once `popover` has
     * popped down. `accel`, if given (build it with
     * `Gtk.accelerator_get_label (keyval, mods)`, not typed out by hand —
     * see TabBarView.show_context_menu for why), is shown as a dimmed hint
     * on the right, matching Nautilus's own popover menus (its own label
     * carries no `dim-label`/similar class of its own — that's a real
     * GtkPopoverMenu's own built-in accelerator column, which this project
     * doesn't use; see the class doc comment — this reproduces the same
     * look with two plain Gtk.Labels instead).
     */
    public static Gtk.Widget item (string label_text, owned MenuAction action, Gtk.Popover popover, string? accel = null) {
        if (!css_installed) {
            css_installed = true;
            install_css ();
        }

        var button = new Gtk.Button ();
        // libadwaita's own button { font-weight: bold; } applies
        // unconditionally, .flat included — real popover menu items use a
        // different widget entirely (a legacy `modelbutton`, styled
        // separately) that never had this problem to begin with;
        // install_css() below undoes it for a plain Gtk.Button used the
        // same way.
        button.add_css_class ("flat");
        button.add_css_class ("opus-context-menu-item");

        var label = new Gtk.Label (label_text) { xalign = 0, hexpand = true };
        if (accel == null) {
            button.child = label;
        } else {
            var accel_label = new Gtk.Label (accel) { xalign = 1 };
            accel_label.add_css_class ("dim-label");

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            box.append (label);
            box.append (accel_label);
            button.child = box;
        }

        button.clicked.connect (() => {
            popover.popdown ();
            action ();
        });
        return button;
    }

    private static void install_css () {
        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_string ("""
            .opus-context-menu-item {
                font-weight: normal;
            }
        """);
        // Gtk.StyleContext.add_provider_for_display is deprecated since GTK
        // 4.10 (removed in GTK 5) with no replacement — same unresolved
        // upstream issue cited elsewhere in this codebase:
        // https://gitlab.gnome.org/GNOME/gtk/-/issues/2603
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }
}
