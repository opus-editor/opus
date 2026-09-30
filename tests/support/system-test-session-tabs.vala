/** Tab lifecycle DSL — new_file/close_tab/active_tab, composed into SystemTestSession the same way CodeEditorCursors/CodeEditorSearch compose into CodeEditor: an independent module that only needs the shared D-Bus proxy, nothing from its sibling modules. */
public class SystemTestTabs : Object {
    private DBusProxy proxy;

    public SystemTestTabs (DBusProxy proxy) {
        this.proxy = proxy;
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

    private Variant call (string method_name, Variant? parameters = null) throws Error {
        return proxy.call_sync (method_name, parameters, DBusCallFlags.NONE, -1);
    }
}
