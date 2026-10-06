int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/models/closed-tabs/the_latest_closed_comes_back_first", () => {
        var closed = new ClosedTabs ();
        closed.record ("/p/a.rb", 1, 0);
        closed.record ("/p/b.rb", 1, 0);

        var first = closed.take ();
        var second = closed.take ();

        assert_cmpstr (first.path, CompareOperator.EQ, "/p/b.rb");
        assert_cmpstr (second.path, CompareOperator.EQ, "/p/a.rb");
    });

    Test.add_func ("/models/closed-tabs/a_tab_taken_is_gone", () => {
        var closed = new ClosedTabs ();
        closed.record ("/p/a.rb", 1, 0);

        closed.take ();

        assert_true (closed.is_empty);
        assert_null (closed.take ());
    });

    Test.add_func ("/models/closed-tabs/a_tab_keeps_where_its_cursor_was", () => {
        var closed = new ClosedTabs ();

        closed.record ("/p/a.rb", 12, 4);

        var tab = closed.take ();
        assert_cmpint (tab.line, CompareOperator.EQ, 12);
        assert_cmpint (tab.column, CompareOperator.EQ, 4);
    });

    Test.add_func ("/models/closed-tabs/nothing_closed_gives_nothing_back", () => {
        var closed = new ClosedTabs ();

        assert_true (closed.is_empty);
        assert_null (closed.take ());
    });

    Test.add_func ("/models/closed-tabs/closing_a_file_again_moves_it_up_instead_of_repeating_it", () => {
        var closed = new ClosedTabs ();
        closed.record ("/p/a.rb", 1, 0);
        closed.record ("/p/b.rb", 1, 0);

        closed.record ("/p/a.rb", 7, 2);

        var first = closed.take ();
        var second = closed.take ();
        assert_cmpstr (first.path, CompareOperator.EQ, "/p/a.rb");
        assert_cmpint (first.line, CompareOperator.EQ, 7);
        assert_cmpstr (second.path, CompareOperator.EQ, "/p/b.rb");
        assert_true (closed.is_empty);
    });

    Test.add_func ("/models/closed-tabs/only_the_last_twenty_are_kept", () => {
        var closed = new ClosedTabs ();
        for (int i = 0; i < ClosedTabs.CAPACITY + 1; i++) {
            closed.record ("/p/%d.rb".printf (i), 1, 0);
        }

        ClosedTab? oldest = null;
        for (int i = 0; i < ClosedTabs.CAPACITY; i++) {
            oldest = closed.take ();
        }

        assert_cmpstr (oldest.path, CompareOperator.EQ, "/p/1.rb");
        assert_true (closed.is_empty);
    });

    Test.add_func ("/models/closed-tabs/a_forgotten_file_is_skipped", () => {
        var closed = new ClosedTabs ();
        closed.record ("/p/a.rb", 1, 0);
        closed.record ("/p/b.rb", 1, 0);

        closed.forget ("/p/b.rb");

        assert_cmpstr (closed.take ().path, CompareOperator.EQ, "/p/a.rb");
        assert_true (closed.is_empty);
    });

    Test.add_func ("/models/closed-tabs/forgetting_a_file_never_closed_changes_nothing", () => {
        var closed = new ClosedTabs ();
        closed.record ("/p/a.rb", 1, 0);

        closed.forget ("/p/zzz.rb");

        assert_cmpstr (closed.take ().path, CompareOperator.EQ, "/p/a.rb");
    });

    return Test.run ();
}
