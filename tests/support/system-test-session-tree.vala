/** Git tree DSL — GitView.TreePane's rows and selection over the dev D-Bus surface, composed into SystemTestSession like SystemTestGit: only the shared proxy. */
public class SystemTestTree : Object {
    private const int WAIT_TIMEOUT_MSEC = 8000;
    private const int POLL_INTERVAL_MSEC = 50;

    private DBusProxy proxy;

    public SystemTestTree (DBusProxy proxy) {
        this.proxy = proxy;
    }

    /** Every row as "<kind>|<lane>|<refs>|<text>|<hash>" — see TreePane.describe_rows(). */
    public string[] rows () throws Error {
        var array = call ("GitTreeRows").get_child_value (0);
        var result = new string[array.n_children ()];
        for (size_t i = 0; i < array.n_children (); i++) {
            result[i] = array.get_child_value (i).get_string ();
        }
        return result;
    }

    /** rows() without the hash column — what a test can predict. */
    public string[] rows_without_hash () throws Error {
        var all = rows ();
        var result = new string[all.length];
        for (int i = 0; i < all.length; i++) {
            var fields = all[i].split ("|", 5);
            result[i] = string.joinv ("|", fields[0:4]);
        }
        return result;
    }

    public void wait_for_rows (string[] expected) throws Error {
        wait (() => same (rows_without_hash (), expected), "tree rows [%s], last saw [%s]".printf (string.joinv (", ", expected), string.joinv (", ", rows_without_hash ())));
    }

    public void wait_for_row_count (int expected) throws Error {
        wait (() => rows ().length == expected, "%d tree rows, last saw %d".printf (expected, rows ().length));
    }

    public void select (string hash_prefix) throws Error {
        call ("GitTreeSelect", new Variant ("(s)", hash_prefix));
    }

    public string selected () throws Error {
        return call ("GitTreeSelected").get_child_value (0).get_string ();
    }

    public int loaded () throws Error {
        return call ("GitTreeLoaded").get_child_value (0).get_int32 ();
    }

    public void load_more () throws Error {
        call ("GitTreeLoadMore");
    }

    public void select_wip () throws Error {
        call ("GitTreeSelectWip");
    }

    /** "staging" or "history". */
    public string sidebar_pane () throws Error {
        return call ("GitSidebarPane").get_child_value (0).get_string ();
    }

    public void wait_for_sidebar_pane (string expected) throws Error {
        wait (() => sidebar_pane () == expected, "the %s pane in the sidebar".printf (expected));
    }

    public string history_header () throws Error {
        return call ("GitHistoryHeader").get_child_value (0).get_string ();
    }

    public string[] history_files () throws Error {
        var array = call ("GitHistoryFiles").get_child_value (0);
        var result = new string[array.n_children ()];
        for (size_t i = 0; i < array.n_children (); i++) {
            result[i] = array.get_child_value (i).get_string ();
        }
        return result;
    }

    public void wait_for_history_files (string[] expected) throws Error {
        wait (() => same (history_files (), expected), "history files [%s], last saw [%s]".printf (string.joinv (", ", expected), string.joinv (", ", history_files ())));
    }

    public void history_back () throws Error {
        call ("GitHistoryBack");
    }

    private delegate bool Condition () throws Error;

    private void wait (Condition condition, string what) throws Error {
        int64 deadline = get_monotonic_time () + WAIT_TIMEOUT_MSEC * 1000;
        while (get_monotonic_time () < deadline) {
            if (condition ()) {
                return;
            }
            Thread.usleep (POLL_INTERVAL_MSEC * 1000);
        }
        throw new IOError.TIMED_OUT ("waited for %s".printf (what));
    }

    private static bool same (string[] a, string[] b) {
        if (a.length != b.length) {
            return false;
        }
        for (int i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    private Variant call (string method_name, Variant? parameters = null) throws Error {
        return proxy.call_sync (method_name, parameters, DBusCallFlags.NONE, -1);
    }
}
