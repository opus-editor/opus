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
 *
 * This class itself is just the orchestrator: session lifecycle
 * (spawning Broadway + Opus, waiting for the D-Bus name to come up,
 * closing both down again) plus one forwarder per DSL method, each
 * delegating to whichever composed module actually implements it
 * (SystemTestTabs/SystemTestEditorText/SystemTestCursors/
 * SystemTestSearch, each in its own file) — the same split TextEditor
 * itself uses for TextEditorCursors/TextEditorSearch, applied here so
 * this file doesn't keep growing with every new area of the app a
 * system test needs to drive. Forwarders stay undocumented on purpose:
 * the real doc comment lives on each module's own implementation.
 */
public class SystemTestSession : Object {
    private const string INTERFACE_NAME = "io.github.nowaos.Opus.Dev";
    private const int64 READY_TIMEOUT_USEC = 5 * 1000 * 1000;
    private const uint READY_POLL_INTERVAL_MSEC = 50;

    private Subprocess broadway_process;
    private Subprocess process;
    private DBusProxy proxy;

    private SystemTestTabs tabs;
    private SystemTestEditorText editor_text;
    private SystemTestCursors cursors;
    private SystemTestSearch search;

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
    /** `folder_path`, if given, is linked as the workspace root exactly like `opus <folder>` on the real command line — for a scenario that needs a real `.editorconfig` picked up (EditorController.root_path/EditorConfig.load()). Null (the default) launches a blank window, same as every existing test. */
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
        // GLib.Environment.get_user_config_dir() (what UserSettings.ensure_exists()
        // resolves against) already respects XDG_CONFIG_HOME — same
        // isolation reasoning as OPUS_APP_ID just above, so a test
        // opening the primary menu's "Settings" writes into a throwaway
        // directory instead of the developer's real ~/.config/opus.
        launcher.setenv ("XDG_CONFIG_HOME", Path.build_filename (Environment.get_tmp_dir (), "opus-test-config-%u".printf (broadway_display_num)), true);
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
        bool ready = false;
        while (get_monotonic_time () < deadline) {
            try {
                // A cheap, real call — proves the object is actually
                // reachable, not just that constructing the proxy
                // itself didn't throw (it doesn't, even before the
                // name has an owner).
                proxy.call_sync ("ListOpenTabs", null, DBusCallFlags.NONE, -1);
                ready = true;
                break;
            } catch (Error e) {
                last_error = e;
                Thread.usleep (READY_POLL_INTERVAL_MSEC * 1000);
            }
        }
        if (!ready) {
            throw last_error ?? new IOError.TIMED_OUT ("Opus never became reachable over D-Bus");
        }

        tabs = new SystemTestTabs (proxy);
        editor_text = new SystemTestEditorText (proxy);
        cursors = new SystemTestCursors (proxy, editor_text);
        search = new SystemTestSearch (proxy);
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

    // --- SystemTestTabs ---
    public void new_file () throws Error { tabs.new_file (); }
    public void close_tab (string path) throws Error { tabs.close_tab (path); }
    public string active_tab () throws Error { return tabs.active_tab (); }
    public void assert_active_tab (string expected) throws Error { tabs.assert_active_tab (expected); }

    // --- SystemTestEditorText ---
    public void editor_write (string text) throws Error { editor_text.editor_write (text); }
    public void type (string text) throws Error { editor_text.type (text); }
    public bool type_cmd (string name) throws Error { return editor_text.type_cmd (name); }
    public bool key_press (uint keyval, uint modifiers) throws Error { return editor_text.key_press (keyval, modifiers); }
    public void select_all () throws Error { editor_text.select_all (); }
    public string active_text () throws Error { return editor_text.active_text (); }
    public void assert_editor_text (string expected) throws Error { editor_text.assert_editor_text (expected); }

    // --- SystemTestCursors ---
    public void set_cursors (int[,] pairs) throws Error { cursors.set_cursors (pairs); }
    public void set_selections (int[,] triples) throws Error { cursors.set_selections (triples); }
    public void active_cursors (out int[] anchors, out int[] positions) throws Error { cursors.active_cursors (out anchors, out positions); }
    public void assert_cursors (int[,] expected) throws Error { cursors.assert_cursors (expected); }

    // --- SystemTestSearch ---
    public void search_set_text (string text) throws Error { search.search_set_text (text); }
    public void search_set_options (bool regex, bool case_sensitive, bool whole_word) throws Error { search.search_set_options (regex, case_sensitive, whole_word); }
    public void search_next () throws Error { search.search_next (); }
    public void search_previous () throws Error { search.search_previous (); }
    public void search_position (out int position, out int count) throws Error { search.search_position (out position, out count); }
    public void assert_search_position (int expected_position, int expected_count) throws Error { search.assert_search_position (expected_position, expected_count); }
}
