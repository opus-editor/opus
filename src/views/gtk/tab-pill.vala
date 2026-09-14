/**
 * A single tab in the {@link TabBarView}'s row: a title, a close button
 * that's always clickable, and italic styling while the tab is a preview.
 * Selection and double-click are reported via signals; this widget knows
 * nothing about {@link ITabBarView} — TabBarView translates its signals into
 * that interface's, keyed by path.
 */
[GtkTemplate (ui = "/io/github/alxmagro/Codi/ui/tab-pill.ui")]
public class TabPill : Gtk.Box {
    /** Single click — makes this tab active. */
    public signal void selected ();

    /** Double click — promotes a preview tab to permanent. */
    public signal void double_clicked ();

    /** The close button was clicked. Always emitted; the button is never disabled. */
    public signal void close_requested ();

    [GtkChild]
    private unowned Gtk.Label title_label;

    [GtkChild]
    private unowned Gtk.Button close_button;

    private static Pango.AttrList italic_attrs = build_italic_attrs ();

    private string base_label = "";
    private bool modified = false;

    construct {
        var click = new Gtk.GestureClick ();
        click.pressed.connect ((n_press, x, y) => {
            if (n_press == 1) {
                selected ();
            } else if (n_press == 2) {
                double_clicked ();
            }
        });
        add_controller (click);

        close_button.clicked.connect (() => close_requested ());
    }

    public void set_label (string label) {
        base_label = label;
        refresh_label ();
    }

    public void set_active (bool active) {
        if (active) {
            add_css_class ("active");
        } else {
            remove_css_class ("active");
        }
    }

    public void set_preview (bool preview) {
        title_label.attributes = preview ? italic_attrs : null;
    }

    public void set_modified (bool modified) {
        this.modified = modified;
        refresh_label ();
    }

    private void refresh_label () {
        title_label.label = modified ? "%s •".printf (base_label) : base_label;
    }

    private static Pango.AttrList build_italic_attrs () {
        var attrs = new Pango.AttrList ();
        attrs.insert (Pango.attr_style_new (Pango.Style.ITALIC));
        return attrs;
    }
}
