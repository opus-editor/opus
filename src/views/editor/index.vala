/**
 * Real Gtk-backed facade for the editor pane: a single {@link GtkSource.View}
 * whose content swaps per active tab. An unreadable file is shown by
 * replacing the buffer with a placeholder message and making the view
 * non-editable, rather than by swapping in a different widget.
 *
 * Syntax highlighting and its colors are never hardcoded here: which
 * language a file highlights as comes from {@link GtkSource.LanguageManager},
 * and the colors from a {@link GtkSource.StyleScheme} — both loaded from
 * `.lang`/`.xml` files GtkSourceView already discovers on disk (including
 * under the user's own `~/.local/share/gtksourceview-5/`), so a new language
 * or a recolored one is a file dropped there, not a code change.
 */
public class EditorView : Object {
    private Gtk.Box root;
    private Gtk.Revealer change_banner_revealer;
    private GtkSource.View text_view;
    private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }

    /** Suppresses `text_changed` while a set_text/set_placeholder call is itself writing the buffer. */
    private bool updating_programmatically = false;

    public Gtk.Widget widget { get { return root; } }

    /** The user edited the text; `new_text` is the buffer's full content. */
    public signal void text_changed (string new_text);

    /** The active tab's file changed on disk and the user chose to discard in-memory content in its favor — see the "Discard Changes and Reload" button on the change banner. */
    public signal void reload_requested ();

    public EditorView () {
        var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/editor/index.ui");
        root = (Gtk.Box) builder.get_object ("root");
        change_banner_revealer = (Gtk.Revealer) builder.get_object ("change_banner_revealer");
        text_view = (GtkSource.View) builder.get_object ("text_view");
        text_view.buffer.changed.connect (on_buffer_changed);

        var discard_button = (Gtk.Button) builder.get_object ("change_banner_discard_button");
        discard_button.clicked.connect (() => reload_requested ());

        install_css ();

        // GtkSource.Buffer paints with a StyleScheme's own fixed colors
        // instead of following the app's GTK theme, so it stays put through
        // a light/dark switch unless told otherwise — pick the scheme
        // ourselves each time Adwaita's does.
        var style_manager = Adw.StyleManager.get_default ();
        style_manager.notify["dark"].connect (() => apply_style_scheme (style_manager.dark));
        apply_style_scheme (style_manager.dark);
    }

    /**
     * Copied straight from GTK's own real `infobar.warning > revealer >
     * box` / `infobar .close` rules (found in libgtk-4.so's compiled CSS,
     * not guessed) — same `var(--…)` tokens GtkInfoBar itself resolves
     * against, so this tracks light/dark and the accent color exactly the
     * same way it does, with no hardcoded color of our own. The 30% mix
     * with the window background (not a flat `--warning-bg-color`) is
     * what actually gives GtkInfoBar its pale, non-saturated look.
     */
    private void install_css () {
        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_string ("""
            .change-banner {
                background-color: color-mix(in srgb, var(--warning-bg-color) 30%, var(--window-bg-color));
                color: var(--window-fg-color);
                padding: 6px 6px 7px 6px;
                box-shadow: inset 0 -1px var(--shade-color);
            }

            .change-banner-title {
                font-weight: bold;
            }
        """);
        // See views/tab-bar/_pill.vala for why add_provider_for_display
        // despite the GTK 4.10 deprecation with no replacement.
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }

    /** Shows `text`, highlighted as whichever language `path`'s name/extension matches (none, if it matches none). */
    public void set_text (string text, string path) {
        text_view.editable = true;
        source_buffer.language = GtkSource.LanguageManager.get_default ().guess_language (path, null);
        set_buffer_text (text);
    }

    public string get_text () {
        return text_view.buffer.text;
    }

    public void set_placeholder (string message) {
        text_view.editable = false;
        source_buffer.language = null;
        set_buffer_text (message);
    }

    public void clear_placeholder () {
        text_view.editable = true;
    }

    /** Moves keyboard focus into the text view — used when opening a tab is meant to start editing right away, not just show it. */
    public void grab_focus () {
        text_view.grab_focus ();
    }

    /** Shows or hides the "File Has Changed on Disk" banner — for whichever document is currently shown, tracked by EditorController, not by EditorView itself. */
    public void set_change_banner_visible (bool visible) {
        change_banner_revealer.reveal_child = visible;
    }

    /**
     * Shows the system's own Save-As file chooser (Gtk.FileDialog — a
     * portal dialog, the desktop's own file manager UI when a portal is
     * available, e.g. GNOME's Nautilus-flavored one), pre-filled with
     * `suggested_name` in `current_folder`. Returns the chosen path, or
     * null if the user cancelled or the dialog/portal itself failed.
     */
    public async string? choose_save_as_path (string suggested_name, string current_folder) {
        var dialog = new Gtk.FileDialog ();
        dialog.initial_name = suggested_name;
        dialog.initial_folder = File.new_for_path (current_folder);

        try {
            var file = yield dialog.save (widget.get_root () as Gtk.Window, null);
            return file != null ? file.get_path () : null;
        } catch (Error e) {
            return null;
        }
    }

    private void on_buffer_changed () {
        if (updating_programmatically) {
            return;
        }

        text_changed (get_text ());
    }

    private void set_buffer_text (string text) {
        updating_programmatically = true;
        text_view.buffer.text = text;
        updating_programmatically = false;
    }

    private void apply_style_scheme (bool dark) {
        var scheme_id = dark ? "Adwaita-dark" : "Adwaita";
        source_buffer.style_scheme = GtkSource.StyleSchemeManager.get_default ().get_scheme (scheme_id);
    }
}
