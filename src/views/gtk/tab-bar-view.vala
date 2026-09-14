/**
 * Real Gtk-backed {@link ITabBarView}: a horizontal, scrollable row of
 * {@link TabPill}s, one per open file, keyed by path.
 */
public class TabBarView : Object, ITabBarView {
    private Gtk.Box box;
    private Gtk.ScrolledWindow scrolled_window;
    private HashTable<string, TabPill> pills = new HashTable<string, TabPill> (str_hash, str_equal);
    private TabPill? active_pill = null;

    public Gtk.Widget widget { get { return scrolled_window; } }

    public TabBarView () {
        box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);

        scrolled_window = new Gtk.ScrolledWindow ();
        scrolled_window.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER);
        scrolled_window.set_child (box);
    }

    public void add_tab (string path, string label, bool preview) {
        var pill = new TabPill ();
        pill.set_label (label);
        pill.set_preview (preview);
        pill.selected.connect (() => tab_selected (path));
        pill.double_clicked.connect (() => tab_double_clicked (path));
        pill.close_requested.connect (() => tab_close_requested (path));

        pills[path] = pill;
        box.append (pill);
    }

    public void remove_tab (string path) {
        var pill = pills[path];
        if (pill == null) {
            return;
        }

        box.remove (pill);
        pills.remove (path);
        if (active_pill == pill) {
            active_pill = null;
        }
    }

    public void set_active (string path) {
        if (active_pill != null) {
            active_pill.set_active (false);
        }

        active_pill = pills[path];
        if (active_pill != null) {
            active_pill.set_active (true);
        }
    }

    public void mark_preview (string path, bool preview) {
        var pill = pills[path];
        if (pill != null) {
            pill.set_preview (preview);
        }
    }

    public void mark_modified (string path, bool modified) {
        var pill = pills[path];
        if (pill != null) {
            pill.set_modified (modified);
        }
    }

    public async DiscardChoice confirm_unsaved_close (string filename) {
        var dialog = new Adw.AlertDialog (
            _("Save changes to “%s”?").printf (filename),
            _("Your changes will be lost if you don't save them.")
        );
        dialog.add_response ("cancel", _("Cancel"));
        dialog.add_response ("discard", _("Don't Save"));
        dialog.add_response ("save", _("Save"));
        dialog.set_response_appearance ("discard", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
        dialog.set_default_response ("save");
        dialog.set_close_response ("cancel");

        var response = yield dialog.choose (widget, null);
        switch (response) {
            case "save":
                return DiscardChoice.SAVE;
            case "discard":
                return DiscardChoice.DISCARD;
            default:
                return DiscardChoice.CANCEL;
        }
    }
}
