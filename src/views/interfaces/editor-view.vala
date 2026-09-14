/**
 * Facade for the single editor pane whose content swaps per active tab. A
 * Controller only ever sees this interface — never the Gtk widgets backing
 * it.
 */
public interface IEditorView : Object {
    /** The user edited the text; `new_text` is the buffer's full content. */
    public signal void text_changed (string new_text);

    /** Shows `text` for editing. */
    public abstract void set_text (string text);

    /** Returns the buffer's current content. */
    public abstract string get_text ();

    /** Replaces the buffer with a non-editable placeholder message. */
    public abstract void set_placeholder (string message);

    /** Returns to normal, editable text display. */
    public abstract void clear_placeholder ();
}
