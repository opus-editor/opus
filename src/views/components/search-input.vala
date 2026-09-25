/**
 * A plain-entry look-alike with an inline, right-aligned "N of M" match
 * counter — the same real technique GNOME Text Editor's own
 * `EditorSearchEntry` uses (ported from its real source, editor-search-
 * entry.c): a bare `Gtk.Widget` subclass laid out with `Gtk.BoxLayout`,
 * its own css-name set to "entry" so libadwaita's real entry stylesheet
 * (background, border, focus ring, padding) applies with zero CSS of our
 * own — the same reason EditorView.FindBar's own outer Gtk.SearchBar borrows
 * "searchbar" as its css-name. A plain Gtk.Entry can't do this itself:
 * it has no way to embed an arbitrary child widget alongside its text.
 *
 * One real deviation from EditorSearchEntry's own source: it also
 * implements Gtk.Editable itself, delegating every method to its inner
 * GtkText, so the whole thing is a drop-in Gtk.Editable (their own
 * gtk_editable_delegate_get_property()/set_property() pattern). Tried
 * porting that here too — Vala can't compile it: the interface's `text`
 * property and its `get_text()` method both claim the same underlying
 * GtkEditableInterface vfunc slot, and providing either one (let alone
 * both) collides internally (`internal: Redefinition of
 * 'search_counter_entry_real_get_text'`) no matter how the accessors are
 * split (owned/unowned, property-only, method-only) — a real Vala 0.56
 * binding gap for this specific interface shape, not a design choice.
 * `entry` below (the inner Gtk.Text — itself a genuine Gtk.Editable) is
 * what EditorView.FindBar wires everything through instead, including
 * Gtk.SearchBar.connect_entry().
 */
public class SearchInput : Gtk.Widget {
    private Gtk.Label counter_label;

    /** The real editable text — EditorView.FindBar connects its own `changed`/`activate` signals and reads/writes `.text` straight through this, and passes it to Gtk.SearchBar.connect_entry() (a plain Gtk.Text already satisfies Gtk.Editable on its own — see this class's own doc comment for why it's not this outer widget instead). */
    public Gtk.Text entry { get; private set; }

    private int occurrence_count = 0;
    private int occurrence_position = -1;

    static construct {
        set_css_name ("entry");
    }

    public SearchInput () {
        layout_manager = new Gtk.BoxLayout (Gtk.Orientation.HORIZONTAL);

        entry = new Gtk.Text () {
            hexpand = true,
            placeholder_text = _("Find")
        };
        entry.set_parent (this);

        counter_label = new Gtk.Label (null) {
            xalign = 1,
            // Reserves space for the widest realistic count ("999 of
            // 999") up front, so the entry's own typing area doesn't
            // visibly shrink/grow as this label's text appears, changes
            // digit count, or clears back to "" — found live: without
            // this, GtkBoxLayout only ever gives this label exactly as
            // much width as its *current* text needs, so entry (the
            // only hexpand child) silently absorbed the difference every
            // time, reading as the whole input jittering in width.
            width_chars = 10
        };
        counter_label.add_css_class ("dim-label");
        counter_label.set_parent (this);
    }

    public override void dispose () {
        Gtk.Widget? child;
        while ((child = get_first_child ()) != null) {
            child.unparent ();
        }
        base.dispose ();
    }

    /** Focuses the real inner text, not this composite widget itself — same reason EditorSearchEntry overrides grab_focus in its own real source. */
    public override bool grab_focus () {
        return entry.grab_focus ();
    }

    /**
     * Shows "`position` of `count`" right-aligned inside the entry, or
     * nothing at all once `count` is 0 — matching GNOME Text Editor's
     * own real search entry (editor-search-entry.c:
     * `if (occurrence_count == 0) gtk_label_set_label (info, NULL)`).
     */
    public void set_match_info (int position, int count) {
        occurrence_position = int.max (-1, position);
        occurrence_count = int.max (0, count);

        if (occurrence_count == 0) {
            counter_label.label = "";
        } else {
            // translators: the first %d is the current match's position, the second is the total match count
            counter_label.label = _("%d of %d").printf (int.max (0, occurrence_position), occurrence_count);
        }
    }
}
