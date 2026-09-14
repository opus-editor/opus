/**
 * The Blueprint-templated main window: a header bar plus a resizable
 * sidebar split from a column holding the tab bar above the editor pane.
 * The `sidebar_bin`, `tab_bar_bin` and `editor_bin` slots are filled by
 * `MainWindowView`, which owns this instance.
 */
[GtkTemplate (ui = "/io/github/alxmagro/Codi/ui/main-window.ui")]
private class CodiWindow : Adw.ApplicationWindow {
    [GtkChild]
    private unowned Adw.WindowTitle window_title;

    [GtkChild]
    private unowned Adw.Bin sidebar_bin;

    [GtkChild]
    private unowned Adw.Bin tab_bar_bin;

    [GtkChild]
    private unowned Adw.Bin editor_bin;

    public CodiWindow (Gtk.Application app) {
        Object (application: app);
    }

    public void set_folder_name (string name) {
        window_title.title = name;
    }

    public void set_sidebar (Gtk.Widget widget) {
        sidebar_bin.child = widget;
    }

    public void set_tab_bar (Gtk.Widget widget) {
        tab_bar_bin.child = widget;
    }

    public void set_editor (Gtk.Widget widget) {
        editor_bin.child = widget;
    }
}

/**
 * Facade for the application's main window. Composes the sidebar, tab-bar
 * and editor-pane widgets built elsewhere into the window's layout; holds
 * no controller logic of its own — whoever wires the app hands it the real
 * widgets and reacts to their own controllers separately.
 */
public class MainWindowView : Object {
    private CodiWindow window;

    public MainWindowView (Gtk.Application app, Gtk.Widget sidebar, Gtk.Widget tab_bar, Gtk.Widget editor_pane) {
        window = new CodiWindow (app);
        window.set_sidebar (sidebar);
        window.set_tab_bar (tab_bar);
        window.set_editor (editor_pane);
    }

    /** Sets the header title to the open folder's name. */
    public void set_folder_name (string name) {
        window.set_folder_name (name);
    }

    /** Shows the window. */
    public void present () {
        window.present ();
    }
}
