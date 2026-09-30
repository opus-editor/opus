/** Typing/keystroke DSL over the active tab's own buffer — editor_write/type/type_cmd/key_press/select_all, plus reading the buffer back for assertions. Composed into SystemTestSession the same way CodeEditorCursors/CodeEditorSearch compose into CodeEditor. */
public class SystemTestEditorText : Object {
    private DBusProxy proxy;

    public SystemTestEditorText (DBusProxy proxy) {
        this.proxy = proxy;
    }

    /**
     * Sets the active tab's buffer content directly, for arranging a
     * scenario's starting text — unlike type(), this doesn't simulate
     * keystrokes and leaves no undo entry behind, so a test's setup
     * never becomes something a later type_cmd("undo") could reach.
     */
    public void editor_write (string text) throws Error {
        call ("SetActiveText", new Variant ("(s)", text));
    }

    /** Simulates typing `text` one character at a time, exactly as real keystrokes would arrive. */
    public void type (string text) throws Error {
        int index = 0;
        unichar c;
        while (text.get_next_char (ref index, out c)) {
            key_press (Gdk.unicode_to_keyval (c), 0);
        }
    }

    /** Runs a named command exactly as its real keyboard shortcut would — see command_keyval() for the supported names. Returns whether the key was claimed, same as key_press(). */
    public bool type_cmd (string name) throws Error {
        uint keyval;
        uint modifiers;
        command_keyval (name, out keyval, out modifiers);
        return key_press (keyval, modifiers);
    }

    /** Returns whether anything claimed the key — same as a real keypress's own dispatch result. */
    public bool key_press (uint keyval, uint modifiers) throws Error {
        bool claimed;
        call ("KeyPress", new Variant ("(uu)", keyval, modifiers)).get_child (0, "b", out claimed);
        return claimed;
    }

    /**
     * Fires GtkTextView's own native "select-all" (Ctrl+A) action
     * directly, not via key_press(): unlike an ordinary keystroke,
     * "select-all" is a GTK keybinding-action signal — reachable (and
     * exercised faithfully, not approximated) without a real GTK event.
     */
    public void select_all () throws Error {
        call ("SelectAll");
    }

    public string active_text () throws Error {
        string text;
        call ("GetActiveText").get_child (0, "s", out text);
        return text;
    }

    public void assert_editor_text (string expected) throws Error {
        assert_cmpstr (active_text (), CompareOperator.EQ, expected);
    }

    private static void command_keyval (string name, out uint keyval, out uint modifiers) throws Error {
        switch (name) {
        case "tab":
            keyval = Gdk.Key.Tab;
            modifiers = 0;
            break;
        case "enter":
            keyval = Gdk.Key.Return;
            modifiers = 0;
            break;
        case "backspace":
            keyval = Gdk.Key.BackSpace;
            modifiers = 0;
            break;
        case "alt+up":
            keyval = Gdk.Key.Up;
            modifiers = Gdk.ModifierType.ALT_MASK;
            break;
        case "alt+down":
            keyval = Gdk.Key.Down;
            modifiers = Gdk.ModifierType.ALT_MASK;
            break;
        case "undo":
            keyval = Gdk.Key.z;
            modifiers = Gdk.ModifierType.CONTROL_MASK;
            break;
        case "redo":
            keyval = Gdk.Key.z;
            modifiers = Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK;
            break;
        case "escape":
            keyval = Gdk.Key.Escape;
            modifiers = 0;
            break;
        case "shift+left":
            keyval = Gdk.Key.Left;
            modifiers = Gdk.ModifierType.SHIFT_MASK;
            break;
        case "shift+right":
            keyval = Gdk.Key.Right;
            modifiers = Gdk.ModifierType.SHIFT_MASK;
            break;
        case "shift+up":
            keyval = Gdk.Key.Up;
            modifiers = Gdk.ModifierType.SHIFT_MASK;
            break;
        case "shift+down":
            keyval = Gdk.Key.Down;
            modifiers = Gdk.ModifierType.SHIFT_MASK;
            break;
        case "ctrl+left":
            keyval = Gdk.Key.Left;
            modifiers = Gdk.ModifierType.CONTROL_MASK;
            break;
        case "ctrl+right":
            keyval = Gdk.Key.Right;
            modifiers = Gdk.ModifierType.CONTROL_MASK;
            break;
        case "ctrl+d":
            keyval = Gdk.Key.d;
            modifiers = Gdk.ModifierType.CONTROL_MASK;
            break;
        case "ctrl+x":
            keyval = Gdk.Key.x;
            modifiers = Gdk.ModifierType.CONTROL_MASK;
            break;
        case "ctrl+v":
            keyval = Gdk.Key.v;
            modifiers = Gdk.ModifierType.CONTROL_MASK;
            break;
        case "shift+alt+up":
            keyval = Gdk.Key.Up;
            modifiers = Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.ALT_MASK;
            break;
        case "shift+alt+down":
            keyval = Gdk.Key.Down;
            modifiers = Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.ALT_MASK;
            break;
        case "insert":
            keyval = Gdk.Key.Insert;
            modifiers = 0;
            break;
        default:
            throw new IOError.INVALID_ARGUMENT ("Unknown type_cmd: %s".printf (name));
        }
    }

    private Variant call (string method_name, Variant? parameters = null) throws Error {
        return proxy.call_sync (method_name, parameters, DBusCallFlags.NONE, -1);
    }
}
