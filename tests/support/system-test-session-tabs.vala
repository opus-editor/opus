/** Tab lifecycle DSL — new_file/close_tab/active_tab, composed into SystemTestSession the same way CodeEditorCursors/CodeEditorSearch compose into CodeEditor: an independent module that only needs the shared D-Bus proxy, nothing from its sibling modules. */
public class SystemTestTabs : Object {
    private DBusProxy proxy;

    public SystemTestTabs (DBusProxy proxy) {
        this.proxy = proxy;
    }

    public void new_file () throws Error {
        call ("NewFile");
    }

    /** Opens `path` as a permanent tab — same as "Open File…" or a sidebar double-click. */
    /** A single click in the explorer: a preview tab. */
    public void open_preview_tab (string path) throws Error {
        call ("OpenPreviewTab", new Variant ("(s)", path));
    }

    /** How many document tabs exist in memory. */
    public int live_tabs () throws Error {
        return call ("GetLiveTabs").get_child_value (0).get_int32 ();
    }

    /** Ctrl+Shift+T. */
    public void reopen_closed_tab () throws Error {
        call ("ReopenClosedTab");
    }

    public void open_tab (string path) throws Error {
        call ("OpenTab", new Variant ("(s)", path));
    }

    /** Every open tab's own user-facing name (a real path, or a synthetic tab's display name), in no particular order. */
    public string[] open_tabs () throws Error {
        return call ("ListOpenTabs").get_child_value (0).dup_strv ();
    }

    /**
     * Waits until `expected` is the active tab, for a change that lands
     * asynchronously on the Opus side (a Find in Files search runs off
     * the D-Bus call's own return) — the same poll-with-deadline shape
     * SystemTestSession's own readiness wait uses. Fails if it never does.
     */
    public void wait_for_active_tab (string expected) throws Error {
        int64 deadline = get_monotonic_time () + WAIT_TIMEOUT_USEC;
        while (active_tab () != expected) {
            if (get_monotonic_time () >= deadline) {
                throw new IOError.TIMED_OUT ("\"%s\" never became the active tab (active: \"%s\")".printf (expected, active_tab ()));
            }
            Thread.usleep (WAIT_POLL_INTERVAL_MSEC * 1000);
        }
    }

    private const int64 WAIT_TIMEOUT_USEC = 5 * 1000 * 1000;
    private const uint WAIT_POLL_INTERVAL_MSEC = 50;

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

    private Variant call (string method_name, Variant? parameters = null) throws Error {
        return proxy.call_sync (method_name, parameters, DBusCallFlags.NONE, -1);
    }
}
