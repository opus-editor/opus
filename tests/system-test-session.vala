/**
 * Drives a real, headless (Broadway-backed) Opus process over its own
 * debug D-Bus interface (see src/modules/dev-server/index.vala) — a
 * Capybara-style DSL for system-level tests that exercise the whole real
 * stack (keyboard -> CursorController -> EditHistory -> the actual
 * buffer), not one layer of it in isolation. Lives directly under
 * tests/, not tests/system/ — same layering as Rails'
 * own ApplicationSystemTestCase (test/application_system_test_case.rb)
 * vs. the actual tests in test/system/: this is the harness, tests/
 * system/ holds the tests that use it.
 *
 * Talks to the dev D-Bus interface through a plain, dynamic
 * Gio.DBusProxy — calling methods by name and building/parsing Variants
 * by hand — rather than a generated, strongly-typed proxy. That would
 * need Opus.Dev.DevInterface visible to this test binary too, meaning
 * either linking the whole GTK-dependent app into it just for one
 * interface declaration, or duplicating that declaration by hand in two
 * places. Calling by name avoids both: this file only needs to agree
 * with dev-server/index.vala's own method names/signatures, in exactly
 * the shape `gdbus call` itself already uses against the same interface.
 */
public class SystemTestSession : Object {
    private const string INTERFACE_NAME = "io.github.nowaos.Opus.Dev";
    private const int64 READY_TIMEOUT_USEC = 5 * 1000 * 1000;
    private const uint READY_POLL_INTERVAL_MSEC = 50;

    private Subprocess broadway_process;
    private Subprocess process;
    private DBusProxy proxy;

    /**
     * Launches a headless Broadway display server plus a fresh Opus
     * instance pointed at it, and blocks until Opus's dev D-Bus interface
     * actually answers a call — not just until the processes start, which
     * happens well before Opus finishes initializing and owning its bus
     * name. Throws if it never comes up within a few seconds.
     *
     * `GDK_BACKEND=broadway` alone isn't enough to run headless: it only
     * tells GTK which backend to use, and that backend still needs a real
     * server to connect to (`gtk4-broadwayd`) or Opus fails to open a
     * display at all and exits immediately.
     *
     * `broadway_display_num` must be distinct across every system-test
     * binary that might run at the same time — `meson test` runs them in
     * parallel by default, and broadwayd's httpd port is always 8080 +
     * this number, so two sessions sharing one would fight over the same
     * port instead of getting their own isolated display.
     */
    /** `folder_path`, if given, is linked as the workspace root exactly like `opus <folder>` on the real command line — for a scenario that needs a real `.editorconfig` picked up (EditorController.root_path/EditorConfig.load()), which no test needed before this. Null (the default) launches a blank window, same as every existing test. */
    public SystemTestSession (string opus_binary_path, uint broadway_display_num, string? folder_path = null) throws Error {
        var broadway_launcher = new SubprocessLauncher (SubprocessFlags.NONE);
        // See the identical spawnv() argv warning/explanation below.
        string[] broadway_argv = { "gtk4-broadwayd", ":%u".printf (broadway_display_num) };
        broadway_process = broadway_launcher.spawnv (broadway_argv);
        wait_for_port ((uint16) (8080 + broadway_display_num));

        // A dedicated app id, unique to this one session (reusing
        // broadway_display_num — already guaranteed distinct across
        // every concurrently-running system-test binary, see this
        // constructor's own doc comment above) — see main.vala's own
        // OPUS_APP_ID comment for why this matters: without it, this
        // whole session would silently drive any real Opus window the
        // developer happens to already have open instead of the
        // isolated one just spawned for it.
        var app_id = "io.github.nowaos.Opus.Test%u".printf (broadway_display_num);

        var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
        launcher.setenv ("GDK_BACKEND", "broadway", true);
        launcher.setenv ("BROADWAY_DISPLAY", ":%u".printf (broadway_display_num), true);
        launcher.setenv ("OPUS_APP_ID", app_id, true);
        // spawnv() takes a `const gchar * const *`; valac always marshals
        // a string[] as a plain, non-const `gchar**` — see the identical
        // warning/explanation at file-tree-controller.vala's own spawnv()
        // call, an upstream wart, not something fixable here.
        string[] argv;
        if (folder_path != null) {
            argv = { opus_binary_path, folder_path };
        } else {
            argv = { opus_binary_path };
        }
        process = launcher.spawnv (argv);

        // GApplication's own object path is just its app id with dots
        // turned into slashes, a leading one added (confirmed against
        // main.vala's own dev_server.start() call, which reads it
        // straight back via app.get_dbus_object_path() rather than
        // building it by hand the way this has to) — "/Dev" is
        // DevServer's own suffix on top of that, see dev-server/
        // index.vala's own doc comment for why it piggybacks there
        // instead of owning a separate name.
        var bus_name = app_id;
        var object_path = "/" + app_id.replace (".", "/") + "/Dev";

        var connection = Bus.get_sync (BusType.SESSION);
        proxy = new DBusProxy.sync (connection, DBusProxyFlags.NONE, null, bus_name, object_path, INTERFACE_NAME);

        int64 deadline = get_monotonic_time () + READY_TIMEOUT_USEC;
        Error? last_error = null;
        while (get_monotonic_time () < deadline) {
            try {
                // A cheap, real call — proves the object is actually
                // reachable, not just that constructing the proxy
                // itself didn't throw (it doesn't, even before the
                // name has an owner).
                call ("ListOpenTabs");
                return;
            } catch (Error e) {
                last_error = e;
                Thread.usleep (READY_POLL_INTERVAL_MSEC * 1000);
            }
        }
        throw last_error ?? new IOError.TIMED_OUT ("Opus never became reachable over D-Bus");
    }

    /**
     * Terminates the launched processes — call once a test is done with
     * this session. Waits for both to actually exit, not just for the
     * kill signal to be sent: a caller reusing the same Broadway display
     * number for a next session (most test files do, sequentially)
     * would otherwise race broadwayd's own port release and
     * occasionally fail to bind it.
     */
    public void close () {
        if (process != null) {
            process.force_exit ();
            try {
                process.wait ();
            } catch (Error e) {
                // best-effort cleanup — nothing left to do about a
                // failed wait here
            }
            process = null;
        }
        if (broadway_process != null) {
            broadway_process.force_exit ();
            try {
                broadway_process.wait ();
            } catch (Error e) {
                // best-effort cleanup, same as above
            }
            broadway_process = null;
        }
    }

    private static void wait_for_port (uint16 port) throws Error {
        int64 deadline = get_monotonic_time () + READY_TIMEOUT_USEC;
        Error? last_error = null;
        while (get_monotonic_time () < deadline) {
            try {
                var connection = new SocketClient ().connect_to_host ("127.0.0.1", port);
                connection.close ();
                return;
            } catch (Error e) {
                last_error = e;
                Thread.usleep (READY_POLL_INTERVAL_MSEC * 1000);
            }
        }
        throw last_error ?? new IOError.TIMED_OUT ("broadwayd never started listening");
    }

    public void new_file () throws Error {
        call ("NewFile");
    }

    /** Closes `path`'s tab outright, no unsaved-changes prompt (matching CloseTab's own semantics — see dev-server/index.vala) — fine for a clean, just-created test document. */
    public void close_tab (string path) throws Error {
        call ("CloseTab", new Variant ("(s)", path));
    }

    /** The active tab's path, or "" if none is. */
    public string active_tab () throws Error {
        string path;
        call ("GetActiveTab").get_child (0, "s", out path);
        return path;
    }

    public void assert_active_tab (string expected) throws Error {
        assert_cmpstr (active_tab (), CompareOperator.EQ, expected);
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

    /** `pairs[i] = { line, column }` (both 0-based) — one collapsed cursor per pair, resolved against the buffer's current text. */
    public void set_cursors (int[,] pairs) throws Error {
        var lines = active_text ().split ("\n");

        var anchors = new VariantBuilder (new VariantType ("ai"));
        var positions = new VariantBuilder (new VariantType ("ai"));
        for (int i = 0; i < pairs.length[0]; i++) {
            int offset = offset_for_line_column (lines, pairs[i, 0], pairs[i, 1]);
            anchors.add ("i", offset);
            positions.add ("i", offset);
        }

        call ("SetActiveCursors", new Variant ("(@ai@ai)", anchors.end (), positions.end ()));
    }

    /** `triples[i] = { line, start_column, end_column }` (0-based) — one cursor per triple, selecting `[start_column, end_column)` on that line, anchored at the start (position/caret lands at the end, matching a left-to-right drag-select). Resolved against the buffer's current text. */
    public void set_selections (int[,] triples) throws Error {
        var lines = active_text ().split ("\n");

        var anchors = new VariantBuilder (new VariantType ("ai"));
        var positions = new VariantBuilder (new VariantType ("ai"));
        for (int i = 0; i < triples.length[0]; i++) {
            anchors.add ("i", offset_for_line_column (lines, triples[i, 0], triples[i, 1]));
            positions.add ("i", offset_for_line_column (lines, triples[i, 0], triples[i, 2]));
        }

        call ("SetActiveCursors", new Variant ("(@ai@ai)", anchors.end (), positions.end ()));
    }

    public string active_text () throws Error {
        string text;
        call ("GetActiveText").get_child (0, "s", out text);
        return text;
    }

    public void assert_editor_text (string expected) throws Error {
        assert_cmpstr (active_text (), CompareOperator.EQ, expected);
    }

    /** The current cursor set as raw buffer offsets — anchors[i]/positions[i] pair up into one cursor each (equal when collapsed). */
    public void active_cursors (out int[] anchors, out int[] positions) throws Error {
        var result = call ("GetActiveCursors");
        anchors = variant_to_int_array (result.get_child_value (0));
        positions = variant_to_int_array (result.get_child_value (1));
    }

    /** Asserts the current cursor set matches exactly: expected[i] = { anchor_offset, position_offset } (equal when collapsed) — raw buffer offsets, since a selection's anchor and position can't both be expressed as one line/column pair the way set_cursors()'s collapsed cursors can. */
    public void assert_cursors (int[,] expected) throws Error {
        int[] anchors;
        int[] positions;
        active_cursors (out anchors, out positions);

        assert_cmpint (anchors.length, CompareOperator.EQ, expected.length[0]);
        for (int i = 0; i < expected.length[0]; i++) {
            assert_cmpint (anchors[i], CompareOperator.EQ, expected[i, 0]);
            assert_cmpint (positions[i], CompareOperator.EQ, expected[i, 1]);
        }
    }

    private static int[] variant_to_int_array (Variant array_variant) {
        var result = new int[array_variant.n_children ()];
        for (size_t i = 0; i < array_variant.n_children (); i++) {
            result[i] = array_variant.get_child_value (i).get_int32 ();
        }
        return result;
    }

    private static int offset_for_line_column (string[] lines, int line, int column) {
        int offset = 0;
        for (int i = 0; i < line; i++) {
            offset += lines[i].char_count () + 1; // +1 for the newline split() consumed
        }
        return offset + column;
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
        default:
            throw new IOError.INVALID_ARGUMENT ("Unknown type_cmd: %s".printf (name));
        }
    }

    private Variant call (string method_name, Variant? parameters = null) throws Error {
        return proxy.call_sync (method_name, parameters, DBusCallFlags.NONE, -1);
    }
}
