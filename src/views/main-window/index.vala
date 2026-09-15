/**
 * Facade for the application's main window. Loads the window and its named
 * slots straight from the compiled Blueprint via {@link Gtk.Builder} — the
 * same way {@link EditorView} loads its widget tree, no composite-template
 * subclass needed — and composes the sidebar, tab-bar and editor-pane
 * widgets built elsewhere into those slots. Holds no controller logic of
 * its own; whoever wires the app hands it the real widgets and reacts to
 * their own controllers separately.
 */
public class MainWindowView : Object {
    private Adw.ApplicationWindow window;
    private Adw.WindowTitle window_title;
    private Adw.Bin sidebar_bin;
    private Adw.Bin tab_bar_bin;
    private Adw.Bin editor_bin;

    public MainWindowView (Gtk.Application app, Gtk.Widget sidebar, Gtk.Widget tab_bar, Gtk.Widget editor_pane) {
        var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/main-window/index.ui");
        window = (Adw.ApplicationWindow) builder.get_object ("window");
        window_title = (Adw.WindowTitle) builder.get_object ("window_title");
        sidebar_bin = (Adw.Bin) builder.get_object ("sidebar_bin");
        tab_bar_bin = (Adw.Bin) builder.get_object ("tab_bar_bin");
        editor_bin = (Adw.Bin) builder.get_object ("editor_bin");

        window.application = app;
        sidebar_bin.child = sidebar;
        tab_bar_bin.child = tab_bar;
        editor_bin.child = editor_pane;
    }

    /** Sets the header title to the open folder's name. */
    public void set_folder_name (string name) {
        window_title.title = name;
    }

    /** Shows the window. */
    public void present () {
        window.present ();
    }
}
