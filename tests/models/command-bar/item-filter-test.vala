private GenericArray<CommandBar.Item> rows (string[] labels) {
    var all = new GenericArray<CommandBar.Item> ();
    foreach (unowned string label in labels) {
        all.add (new CommandBar.Item (label.down (), label));
    }
    return all;
}

private string[] labels_of (GenericArray<CommandBar.Item> items) {
    string[] labels = {};
    foreach (var item in items) {
        labels += item.label;
    }
    return labels;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/command-bar/item-filter/nothing-typed-keeps-every-row-in-its-own-order", () => {
        var all = rows ({ "Ruby", "C", "Python" });

        var narrowed = CommandBar.ItemFilter.narrow (all, "");

        assert_cmpstrv (labels_of (narrowed), { "Ruby", "C", "Python" });
    });

    Test.add_func ("/command-bar/item-filter/typing-keeps-only-the-rows-that-match", () => {
        var all = rows ({ "Ruby", "C", "Python", "Rust" });

        var narrowed = CommandBar.ItemFilter.narrow (all, "ru");

        assert_cmpstrv (labels_of (narrowed), { "Ruby", "Rust" });
    });

    Test.add_func ("/command-bar/item-filter/matching-ignores-case", () => {
        var all = rows ({ "Ruby", "Python" });

        var narrowed = CommandBar.ItemFilter.narrow (all, "RUBY");

        assert_cmpstrv (labels_of (narrowed), { "Ruby" });
    });

    Test.add_func ("/command-bar/item-filter/letters-need-not-be-together", () => {
        var all = rows ({ "Editor / Toggle word wrap", "User Settings" });

        var narrowed = CommandBar.ItemFilter.narrow (all, "tww");

        assert_cmpstrv (labels_of (narrowed), { "Editor / Toggle word wrap" });
    });

    Test.add_func ("/command-bar/item-filter/a-match-at-the-start-comes-first", () => {
        var all = rows ({ "TypeScript", "JavaScript", "Java" });

        var narrowed = CommandBar.ItemFilter.narrow (all, "java");

        assert_cmpstr (narrowed[0].label, CompareOperator.EQ, "Java");
        assert_cmpuint (narrowed.length, CompareOperator.EQ, 2);
    });

    Test.add_func ("/command-bar/item-filter/a-matching-row-says-where-it-matched", () => {
        var all = rows ({ "Ruby" });

        var narrowed = CommandBar.ItemFilter.narrow (all, "ru");

        assert_cmpint (narrowed[0].label_highlights.length, CompareOperator.EQ, 2);
        assert_cmpint (narrowed[0].label_highlights[0], CompareOperator.EQ, 0);
        assert_cmpint (narrowed[0].label_highlights[1], CompareOperator.EQ, 2);
    });

    Test.add_func ("/command-bar/item-filter/a-matching-row-keeps-its-id-and-description", () => {
        var all = new GenericArray<CommandBar.Item> ();
        var row = new CommandBar.Item ("cpp", "C++");
        row.description = "cpp";
        all.add (row);

        var narrowed = CommandBar.ItemFilter.narrow (all, "c");

        assert_cmpstr (narrowed[0].id, CompareOperator.EQ, "cpp");
        assert_cmpstr (narrowed[0].description, CompareOperator.EQ, "cpp");
    });

    Test.add_func ("/command-bar/item-filter/the-rows-given-are-left-without-highlights", () => {
        var all = rows ({ "Ruby" });

        CommandBar.ItemFilter.narrow (all, "ru");

        assert_cmpint (all[0].label_highlights.length, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/item-filter/nothing-matching-leaves-no-rows", () => {
        var all = rows ({ "Ruby", "Python" });

        var narrowed = CommandBar.ItemFilter.narrow (all, "zzz");

        assert_cmpuint (narrowed.length, CompareOperator.EQ, 0);
    });

    return Test.run ();
}
