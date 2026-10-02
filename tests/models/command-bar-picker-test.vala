private GenericArray<CommandBar.Item> three_items () {
    var items = new GenericArray<CommandBar.Item> ();
    items.add (new CommandBar.Item ("/a", "a"));
    items.add (new CommandBar.Item ("/b", "b"));
    items.add (new CommandBar.Item ("/c", "c"));
    return items;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/command-bar/picker/filter-strips-the-prefix-and-surrounding-whitespace", () => {
        var picker = new CommandBar.Picker (">");
        string? reported = null;
        picker.filter_changed.connect ((filter) => reported = filter);

        picker.text = "> open file ";

        assert_cmpstr (picker.filter, CompareOperator.EQ, "open file");
        assert_cmpstr (reported, CompareOperator.EQ, "open file");
    });

    Test.add_func ("/command-bar/picker/text-without-its-prefix-is-the-whole-filter", () => {
        var picker = new CommandBar.Picker (">");

        picker.text = "plain";

        assert_cmpstr (picker.filter, CompareOperator.EQ, "plain");
    });

    Test.add_func ("/command-bar/picker/filter-changed-only-fires-when-the-filter-actually-changes", () => {
        var picker = new CommandBar.Picker ("");
        int fired = 0;
        picker.filter_changed.connect (() => fired++);

        picker.text = "a";
        picker.text = "a ";
        picker.text = " a";

        assert_cmpint (fired, CompareOperator.EQ, 1);
    });

    Test.add_func ("/command-bar/picker/set-items-activates-the-first-row", () => {
        var picker = new CommandBar.Picker ("");
        int reported = -2;
        picker.active_changed.connect ((index) => reported = index);

        picker.set_items (three_items ());

        assert_cmpint (picker.active_index, CompareOperator.EQ, 0);
        assert_cmpint (reported, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/picker/set-items-can-activate-another-row", () => {
        var picker = new CommandBar.Picker ("");

        picker.set_items (three_items (), 1);

        assert_cmpint (picker.active_index, CompareOperator.EQ, 1);
    });

    Test.add_func ("/command-bar/picker/no-items-means-no-active-row", () => {
        var picker = new CommandBar.Picker ("");
        picker.set_items (three_items ());

        picker.set_items (new GenericArray<CommandBar.Item> ());

        assert_cmpint (picker.active_index, CompareOperator.EQ, -1);
    });

    Test.add_func ("/command-bar/picker/move-active-wraps-at-both-ends", () => {
        var picker = new CommandBar.Picker ("");
        picker.set_items (three_items ());

        picker.move_active (-1);
        int after_up = picker.active_index;
        picker.move_active (1);
        int after_down = picker.active_index;

        assert_cmpint (after_up, CompareOperator.EQ, 2);
        assert_cmpint (after_down, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/picker/page-and-first-last-moves-clamp-instead-of-wrapping", () => {
        var picker = new CommandBar.Picker ("");
        picker.set_items (three_items ());

        picker.move_active_by_page (10, 1);
        int page_down = picker.active_index;
        picker.move_active_by_page (10, -1);
        int page_up = picker.active_index;
        picker.move_active_to_last ();
        int last = picker.active_index;
        picker.move_active_to_first ();
        int first = picker.active_index;

        assert_cmpint (page_down, CompareOperator.EQ, 2);
        assert_cmpint (page_up, CompareOperator.EQ, 0);
        assert_cmpint (last, CompareOperator.EQ, 2);
        assert_cmpint (first, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/picker/moving-with-no-items-is-a-no-op", () => {
        var picker = new CommandBar.Picker ("");
        int fired = 0;
        picker.active_changed.connect (() => fired++);

        picker.move_active (1);
        picker.move_active_to_last ();

        assert_cmpint (picker.active_index, CompareOperator.EQ, -1);
        assert_cmpint (fired, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/picker/accept-emits-the-active-item", () => {
        var picker = new CommandBar.Picker ("");
        picker.set_items (three_items ());
        picker.move_active (1);
        string? accepted_id = null;
        picker.accepted.connect ((item) => accepted_id = item.id);

        picker.accept ();

        assert_cmpstr (accepted_id, CompareOperator.EQ, "/b");
    });

    Test.add_func ("/command-bar/picker/accept-with-no-items-emits-nothing", () => {
        var picker = new CommandBar.Picker ("");
        bool fired = false;
        picker.accepted.connect (() => fired = true);

        picker.accept ();

        assert_false (fired);
    });

    Test.add_func ("/command-bar/picker/close-fires-once", () => {
        var picker = new CommandBar.Picker ("");
        int fired = 0;
        picker.closed.connect (() => fired++);

        picker.close ();
        picker.close ();

        assert_true (picker.is_closed);
        assert_cmpint (fired, CompareOperator.EQ, 1);
    });

    return Test.run ();
}
