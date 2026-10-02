private class Scenario {
    public CommandBar.GoToLineProvider provider;
    public CommandBar.Picker picker;

    /** `line`/`line_count` are what the host reports as the caret; a `line` of 0 means no document is open. */
    public Scenario (int line = 12, int line_count = 200) {
        provider = new CommandBar.GoToLineProvider ((out out_line, out out_count) => {
            out_line = line;
            out_count = line_count;
            return line > 0;
        });
        picker = new CommandBar.Picker (":");
        provider.provide (picker, new Cancellable ());
    }
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/command-bar/go-to-line-provider/line-alone-offers-one-row-at-column-zero", () => {
        var scenario = new Scenario ();

        scenario.picker.text = ":30";

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 1);
        var item = scenario.picker.items[0];
        assert_cmpstr (item.label, CompareOperator.EQ, "Go to line 30");
        int line, column;
        CommandBar.GoToLineProvider.decode (item.id, out line, out column);
        assert_cmpint (line, CompareOperator.EQ, 30);
        assert_cmpint (column, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/go-to-line-provider/colon-column-is-one-based-as-typed", () => {
        var scenario = new Scenario ();

        scenario.picker.text = ":30:5";

        var item = scenario.picker.items[0];
        assert_cmpstr (item.label, CompareOperator.EQ, "Go to line 30, column 5");
        int line, column;
        CommandBar.GoToLineProvider.decode (item.id, out line, out column);
        assert_cmpint (line, CompareOperator.EQ, 30);
        assert_cmpint (column, CompareOperator.EQ, 4);
    });

    Test.add_func ("/command-bar/go-to-line-provider/comma-separates-the-column-too", () => {
        var scenario = new Scenario ();

        scenario.picker.text = ":30,5";

        int line, column;
        CommandBar.GoToLineProvider.decode (scenario.picker.items[0].id, out line, out column);
        assert_cmpint (line, CompareOperator.EQ, 30);
        assert_cmpint (column, CompareOperator.EQ, 4);
    });

    Test.add_func ("/command-bar/go-to-line-provider/dangling-separator-still-offers-the-line", () => {
        var scenario = new Scenario ();

        scenario.picker.text = ":30:";

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 1);
        assert_cmpstr (scenario.picker.items[0].label, CompareOperator.EQ, "Go to line 30");
    });

    Test.add_func ("/command-bar/go-to-line-provider/empty-filter-reports-the-caret-position", () => {
        var scenario = new Scenario (12, 200);

        scenario.picker.text = ":";

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
        assert_cmpstr (scenario.picker.empty_message, CompareOperator.EQ, "Current line 12 of 200 — type a line number");
    });

    Test.add_func ("/command-bar/go-to-line-provider/empty-filter-without-a-document-says-so", () => {
        var scenario = new Scenario (0, 0);

        scenario.picker.text = ":";

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
        assert_cmpstr (scenario.picker.empty_message, CompareOperator.EQ, "Open a file to go to a line");
    });

    Test.add_func ("/command-bar/go-to-line-provider/non-numeric-input-offers-nothing-with-a-hint", () => {
        var scenario = new Scenario ();

        scenario.picker.text = ":abc";

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
        assert_cmpstr (scenario.picker.empty_message, CompareOperator.EQ, "Type a line number, e.g. 30 or 30:5");
    });

    Test.add_func ("/command-bar/go-to-line-provider/line-zero-is-not-a-line", () => {
        var scenario = new Scenario ();

        scenario.picker.text = ":0";

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/go-to-line-provider/closed-picker-is-let-go", () => {
        var scenario = new Scenario ();
        scenario.picker.text = ":30";

        scenario.picker.close ();
        scenario.picker.text = ":31";

        assert_cmpstr (scenario.picker.items[0].label, CompareOperator.EQ, "Go to line 30");
    });

    return Test.run ();
}
