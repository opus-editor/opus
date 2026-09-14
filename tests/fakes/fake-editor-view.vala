/** Test double for {@link IEditorView}: records calls, never touches Gtk. */
public class FakeEditorView : Object, IEditorView {
    public string text = "";
    public bool showing_placeholder = false;
    public string? placeholder_message = null;

    public void set_text (string text) {
        this.text = text;
        showing_placeholder = false;
        placeholder_message = null;
    }

    public string get_text () {
        return text;
    }

    public void set_placeholder (string message) {
        placeholder_message = message;
        showing_placeholder = true;
    }

    public void clear_placeholder () {
        showing_placeholder = false;
        placeholder_message = null;
    }

    /** Test helper: simulate the user typing. */
    public void edit_text (string new_text) {
        text = new_text;
        text_changed (new_text);
    }
}
