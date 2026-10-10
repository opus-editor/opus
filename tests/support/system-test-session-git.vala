/** Git view DSL — GitView.StagingPane's rows, buttons and dialogs over the dev D-Bus surface, composed into SystemTestSession the same way SystemTestCommandBar is: only the shared proxy, nothing from its sibling modules. */
public class SystemTestGit : Object {
    // Every list refresh is asynchronous and debounced (StagingPane's own
    // refresh_working_tree()), so a test never reads straight after an
    // action — it waits for the state it expects, or fails after this.
    private const int WAIT_TIMEOUT_MSEC = 5000;
    private const int POLL_INTERVAL_MSEC = 50;

    private DBusProxy proxy;

    public SystemTestGit (DBusProxy proxy) {
        this.proxy = proxy;
    }

    /** The header switcher's "Git" page. */
    public void show () throws Error {
        call ("ShowGitView");
    }

    /** `section` is "conflicts"/"unstaged"/"staged"; each row is "<code> <relative path>". */
    public string[] changes (string section) throws Error {
        return strings (call ("GitListChanges", new Variant ("(s)", section)));
    }

    /** Polls until `section` lists exactly `expected`, in order. */
    public void wait_for_changes (string section, string[] expected) throws Error {
        wait (() => same (changes (section), expected), "%s to be [%s], last saw [%s]".printf (section, string.joinv (", ", expected), string.joinv (", ", changes (section))));
    }

    public void stage_all () throws Error {
        call ("GitStageAll");
    }

    public void unstage_all () throws Error {
        call ("GitUnstageAll");
    }

    public void discard_all () throws Error {
        call ("GitDiscardAll");
    }

    /** A double-click on `path`'s row in `section`. */
    public void activate (string section, string path) throws Error {
        call ("GitActivateRow", new Variant ("(ss)", section, path));
    }

    public void accept_current (string path) throws Error {
        call ("GitAcceptCurrent", new Variant ("(s)", path));
    }

    public void accept_incoming (string path) throws Error {
        call ("GitAcceptIncoming", new Variant ("(s)", path));
    }

    public string commit_label () throws Error {
        return call ("GitCommitLabel").get_child_value (0).get_string ();
    }

    /** "none", "merge", "rebase", "cherry-pick" or "revert". */
    public string operation () throws Error {
        return call ("GitOperation").get_child_value (0).get_string ();
    }

    public void wait_for_operation (string expected) throws Error {
        wait (() => operation () == expected, "operation to be %s, last saw %s".printf (expected, operation ()));
    }

    public bool commit_enabled () throws Error {
        return call ("GitCommitEnabled").get_child_value (0).get_boolean ();
    }

    public void wait_for_commit_enabled (bool expected) throws Error {
        wait (() => commit_enabled () == expected, "the commit button to be %s".printf (expected ? "enabled" : "disabled"));
    }

    public void set_commit_message (string text) throws Error {
        call ("GitSetCommitMessage", new Variant ("(s)", text));
    }

    public string commit_message () throws Error {
        return call ("GitCommitMessage").get_child_value (0).get_string ();
    }

    public void commit () throws Error {
        call ("GitCommit");
    }

    public void abort () throws Error {
        call ("GitAbort");
    }

    /** The last failure toast's summary, "" until one happened. */
    public string last_failure () throws Error {
        return call ("GitLastFailure").get_child_value (0).get_string ();
    }

    public string wait_for_failure () throws Error {
        wait (() => last_failure () != "", "a failure toast");
        return last_failure ();
    }

    /** The heading of the dialog showing, polled until one is. */
    public string wait_for_dialog () throws Error {
        wait (() => dialog_heading () != "", "a dialog");
        return dialog_heading ();
    }

    public string dialog_heading () throws Error {
        return call ("DialogHeading").get_child_value (0).get_string ();
    }

    /** Clicks the showing dialog's button: "cancel", "confirm", "first", "second" or "ok". */
    public void respond (string response_id) throws Error {
        call ("RespondToDialog", new Variant ("(s)", response_id));
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

    private static string[] strings (Variant reply) {
        var array = reply.get_child_value (0);
        var result = new string[array.n_children ()];
        for (size_t i = 0; i < array.n_children (); i++) {
            result[i] = array.get_child_value (i).get_string ();
        }
        return result;
    }

    private Variant call (string method_name, Variant? parameters = null) throws Error {
        return proxy.call_sync (method_name, parameters, DBusCallFlags.NONE, -1);
    }
}
