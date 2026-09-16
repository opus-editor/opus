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
    private Gtk.Overlay floating_layer;
    private Adw.Bin sidebar_bin;
    private Adw.Bin tab_bar_bin;
    private Adw.Bin editor_bin;

    private Gtk.Widget? floating_widget = null;
    private Gdk.Rectangle floating_rect;

    public MainWindowView (Gtk.Application app, Gtk.Widget sidebar, Gtk.Widget tab_bar, Gtk.Widget editor_pane) {
        var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/main-window/index.ui");
        window = (Adw.ApplicationWindow) builder.get_object ("window");
        window_title = (Adw.WindowTitle) builder.get_object ("window_title");
        floating_layer = (Gtk.Overlay) builder.get_object ("floating_layer");
        sidebar_bin = (Adw.Bin) builder.get_object ("sidebar_bin");
        tab_bar_bin = (Adw.Bin) builder.get_object ("tab_bar_bin");
        editor_bin = (Adw.Bin) builder.get_object ("editor_bin");

        floating_layer.get_child_position.connect (on_get_floating_position);

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
        """);
        // See views/tab-bar/_pill.vala for why add_provider_for_display
        // despite the GTK 4.10 deprecation with no replacement.
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        window.application = app;
        sidebar_bin.child = sidebar;
        tab_bar_bin.child = tab_bar;
        editor_bin.child = editor_pane;
    }

    /** Sets the header title to the open folder's name. */
    public void set_folder_name (string name) {
        window_title.title = name;
    }

    /**
     * Shows `widget` floating over the rest of the window at `(x, y, width,
     * height)`, in this window's own coordinates — e.g. a dragged tab's
     * ghost copy (see TabBarView's `drag_ghost_*` signals), positioned
     * anywhere on screen regardless of which narrower widget it came from.
     * Only one floating widget at a time; a second call replaces the first.
     */
    public void show_floating (Gtk.Widget widget, int x, int y, int width, int height) {
        if (floating_widget != widget) {
            hide_floating ();
            floating_layer.add_overlay (widget);
        }

        floating_widget = widget;
        floating_rect = { x, y, width, height };
        floating_layer.queue_allocate ();
    }

    /** Moves the widget currently shown via show_floating() to `(x, y)`, keeping its size. Does nothing if none is shown. */
    public void move_floating (int x, int y) {
        if (floating_widget == null) {
            return;
        }

        floating_rect.x = x;
        floating_rect.y = y;
        floating_layer.queue_allocate ();
    }

    /** Removes the widget shown via show_floating(), if any. */
    public void hide_floating () {
        if (floating_widget == null) {
            return;
        }

        floating_layer.remove_overlay (floating_widget);
        floating_widget = null;
    }

    private bool on_get_floating_position (Gtk.Widget widget, out Gdk.Rectangle allocation) {
        allocation = floating_rect;
        return widget == floating_widget;
    }

    /** Shows the window. */
    public void present () {
        window.present ();
    }
}
