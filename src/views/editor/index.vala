/**
 * Real Gtk-backed facade for the editor pane: a single {@link Gtk.TextView}
 * whose content swaps per active tab. An unreadable file is shown by
 * replacing the buffer with a placeholder message and making the view
 * non-editable, rather than by swapping in a different widget.
 */
public class EditorView : Object {
    private Gtk.ScrolledWindow root;
    private Gtk.TextView text_view;

    /** Suppresses `text_changed` while a set_text/set_placeholder call is itself writing the buffer. */
    private bool updating_programmatically = false;

    public Gtk.Widget widget { get { return root; } }

    /** The user edited the text; `new_text` is the buffer's full content. */
    public signal void text_changed (string new_text);

    public EditorView () {
        var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/editor/index.ui");
        root = (Gtk.ScrolledWindow) builder.get_object ("root");
        text_view = (Gtk.TextView) builder.get_object ("text_view");
        text_view.buffer.changed.connect (on_buffer_changed);
    }

    public void set_text (string text) {
        text_view.editable = true;
        set_buffer_text (text);
    }

    public string get_text () {
        return text_view.buffer.text;
    }

    public void set_placeholder (string message) {
        text_view.editable = false;
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
}
