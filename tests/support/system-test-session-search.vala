/** Find/Replace DSL — search_set_text/search_next/search_previous/assert_search_position. Composed into SystemTestSession the same way TextEditorSearch composes into TextEditor: an independent module that only needs the shared D-Bus proxy. */
public class SystemTestSearch : Object {
    private DBusProxy proxy;

    public SystemTestSearch (DBusProxy proxy) {
        this.proxy = proxy;
    }

    /** Sets the active tab's live Find search text — same as typing into FindBar's own entry. */
    public void search_set_text (string text) throws Error {
        call ("SearchSetText", new Variant ("(s)", text));
    }

    /** Regular Expressions/Case Sensitive/Match Whole Word Only — same as FindBar's own three toggle buttons. */
    public void search_set_options (bool regex, bool case_sensitive, bool whole_word) throws Error {
        call ("SearchSetOptions", new Variant ("(bbb)", regex, case_sensitive, whole_word));
    }

    /** Next Match — same as FindBar's own move_next_button/plain Return. */
    public void search_next () throws Error {
        call ("SearchNext");
    }

    /** Previous Match — same as FindBar's own move_previous_button/Shift+Return. */
    public void search_previous () throws Error {
        call ("SearchPrevious");
    }

    /** The live search's current (position, count), same numbers FindBar's own "N of M" counter would show. */
    public void search_position (out int position, out int count) throws Error {
        var result = call ("SearchGetPosition");
        result.get_child (0, "i", out position);
        result.get_child (1, "i", out count);
    }

    /** Asserts the live search's current (position, count) matches exactly. */
    public void assert_search_position (int expected_position, int expected_count) throws Error {
        int position;
        int count;
        search_position (out position, out count);
        assert_cmpint (position, CompareOperator.EQ, expected_position);
        assert_cmpint (count, CompareOperator.EQ, expected_count);
    }

    private Variant call (string method_name, Variant? parameters = null) throws Error {
        return proxy.call_sync (method_name, parameters, DBusCallFlags.NONE, -1);
    }
}
