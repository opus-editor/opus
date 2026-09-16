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
    private Gtk.ScrolledWindow root;
    private GtkSource.View text_view;
    private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }

    /** Suppresses `text_changed` while a set_text/set_placeholder call is itself writing the buffer. */
    private bool updating_programmatically = false;

    public Gtk.Widget widget { get { return root; } }

    /** The user edited the text; `new_text` is the buffer's full content. */
    public signal void text_changed (string new_text);

    public EditorView () {
        var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/editor/index.ui");
        root = (Gtk.ScrolledWindow) builder.get_object ("root");
        text_view = (GtkSource.View) builder.get_object ("text_view");
        text_view.buffer.changed.connect (on_buffer_changed);

        // GtkSource.Buffer paints with a StyleScheme's own fixed colors
        // instead of following the app's GTK theme, so it stays put through
        // a light/dark switch unless told otherwise — pick the scheme
        // ourselves each time Adwaita's does.
        var style_manager = Adw.StyleManager.get_default ();
        style_manager.notify["dark"].connect (() => apply_style_scheme (style_manager.dark));
        apply_style_scheme (style_manager.dark);
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
