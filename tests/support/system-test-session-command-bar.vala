/** Command Bar DSL — open/type/accept and the rows it shows, composed into SystemTestSession the same way SystemTestTabs is: only the shared D-Bus proxy, nothing from its sibling modules. */
public class SystemTestCommandBar : Object {
    // The bar's file list is walked in the background after opening, so
    // the first rows only exist once that walk answers — a test asks for
    // them through wait_for_items(), never straight after typing.
    private const int ITEMS_TIMEOUT_MSEC = 5000;
    private const int ITEMS_POLL_INTERVAL_MSEC = 50;

    private DBusProxy proxy;

    public SystemTestCommandBar (DBusProxy proxy) {
        this.proxy = proxy;
    }

    public void open () throws Error {
        call ("OpenCommandBar");
    }

    /** Opens the bar on its list of commands — Ctrl+Shift+P, which needs no folder. */
    public void open_commands () throws Error {
        call ("OpenCommands");
    }

    public void type (string text) throws Error {
        call ("CommandBarSetText", new Variant ("(s)", text));
    }

    public void accept () throws Error {
        call ("CommandBarAccept");
    }

    /** Every row currently shown, top to bottom, as the paths they'd open. */
    public string[] items () throws Error {
        var array_variant = call ("CommandBarListItems").get_child_value (0);
        var ids = new string[array_variant.n_children ()];
        for (size_t i = 0; i < array_variant.n_children (); i++) {
            ids[i] = array_variant.get_child_value (i).get_string ();
        }
        return ids;
    }

    /** Polls until at least one row shows, failing after ITEMS_TIMEOUT_MSEC. */
    public string[] wait_for_items () throws Error {
        int64 deadline = get_monotonic_time () + ITEMS_TIMEOUT_MSEC * 1000;
        while (get_monotonic_time () < deadline) {
            var current = items ();
            if (current.length > 0) {
                return current;
            }
            Thread.usleep (ITEMS_POLL_INTERVAL_MSEC * 1000);
        }
        throw new IOError.TIMED_OUT ("the Command Bar never listed any item");
    }

    private Variant call (string method_name, Variant? parameters = null) throws Error {
        return proxy.call_sync (method_name, parameters, DBusCallFlags.NONE, -1);
    }
}
